#!/usr/bin/env bash
# Pengolah & pengunggah. Dijalankan berkala oleh traffic-uploader.timer
# sebagai user "trafficrec" (tanpa hak istimewa apa pun).
#
# 1. Mengosongkan payload setiap berkas rekaman yang sudah selesai ditulis
# 2. Menjaga total pemakaian disk di bawah MAX_DISK_MB
# 3. Mengunggah berkas ke Google Drive lewat rclone, lalu menghapus salinan lokal
set -euo pipefail
shopt -s nullglob
export LC_ALL=C     # urutan glob konsisten: cap_YYYYmmdd_HHMMSS urut menurut waktu

STATE="${STATE_DIR:-/var/lib/traffic-recorder}"
BIN="${BIN_DIR:-/opt/traffic-recorder/bin}"
SPOOL="$STATE/spool"
OUTBOX="$STATE/outbox"
TMPDIR_KERJA="$STATE/tmp"
LOG="$STATE/upload_log.csv"
RCLONE_CONF="$STATE/rclone.conf"
MAX_DISK_MB="${MAX_DISK_MB:-2048}"
UPLOAD_BWLIMIT="${UPLOAD_BWLIMIT:-1M}"
: "${RCLONE_REMOTE:?RCLONE_REMOTE belum diisi di /etc/traffic-recorder/config.env}"

waktu() { date -u +%Y-%m-%dT%H:%M:%SZ; }

mkdir -p "$SPOOL" "$OUTBOX" "$TMPDIR_KERJA"
[[ -s "$LOG" ]] || echo "mulai_utc,selesai_utc,jumlah_berkas,status" > "$LOG"

# Cegah dua proses berjalan bersamaan
exec 9>"$STATE/.lock"
flock -n 9 || { echo "Proses sebelumnya masih berjalan, dilewati."; exit 0; }
rm -f "$TMPDIR_KERJA"/*        # sisa proses yang terhenti di tengah jalan

# ---------------------------------------------------------------- 1. kosongkan payload
perekam_aktif=0
if pgrep -x tcpdump -u "$(id -un)" >/dev/null 2>&1; then
    perekam_aktif=1
fi
# Berkas terbaru ditentukan dari NAMANYA (waktu berkas dibuat), bukan dari waktu
# modifikasi: saat rotasi, tcpdump masih menulis sisa buffer ke berkas lama
# sehingga waktu modifikasi berkas lama bisa lebih baru dari berkas aktif.
semua=("$SPOOL"/cap_*.pcap)
terbaru=""
(( ${#semua[@]} )) && terbaru="${semua[${#semua[@]}-1]}"

for f in "${semua[@]}"; do
    # Berkas terbaru masih ditulis tcpdump selama perekam aktif
    if (( perekam_aktif )) && [[ "$f" == "$terbaru" ]]; then
        continue
    fi
    dasar=$(basename "$f" .pcap)
    # Ditulis dulu ke folder sementara (nama harus berakhiran .gz agar langsung
    # terkompresi), lalu dipindah ke outbox setelah lengkap.
    sementara="$TMPDIR_KERJA/$dasar.hdr.pcap.gz"
    if python3 "$BIN/strip_payload.py" "$f" "$sementara"; then
        mv "$sementara" "$OUTBOX/$dasar.hdr.pcap.gz"
    else
        rm -f "$sementara"
        echo "$(waktu),,0,GAGAL_DIPROSES:$dasar" >> "$LOG"
    fi
    rm -f "$f"     # berkas mentah selalu dihapus, berhasil maupun gagal
done

# ---------------------------------------------------------------- 2. batas disk
batas=$(( MAX_DISK_MB * 1024 * 1024 ))
pakai=$(du -sb "$SPOOL" "$OUTBOX" | awk '{s += $1} END {print s + 0}')
if (( pakai > batas )); then
    for f in $(ls -1tr "$OUTBOX"/*.hdr.pcap.gz 2>/dev/null); do
        (( pakai <= batas )) && break
        ukuran=$(stat -c %s "$f")
        rm -f "$f"
        pakai=$(( pakai - ukuran ))
        echo "$(waktu),,0,DIBUANG_KUOTA:$(basename "$f")" >> "$LOG"
    done
fi

# ---------------------------------------------------------------- 3. unggah
berkas=("$OUTBOX"/*.hdr.pcap.gz)
(( ${#berkas[@]} )) || exit 0

if [[ ! -f "$RCLONE_CONF" ]]; then
    echo "rclone.conf belum dipasang; ${#berkas[@]} berkas disimpan lokal sampai konfigurasi tersedia."
    exit 0
fi

mulai=$(waktu)
if rclone --config "$RCLONE_CONF" move "$OUTBOX" "$RCLONE_REMOTE" \
        --include "*.hdr.pcap.gz" --bwlimit "$UPLOAD_BWLIMIT" --transfers 1 \
        --retries 3 --low-level-retries 5 --log-level NOTICE; then
    status=OK
else
    status=GAGAL
fi
echo "$mulai,$(waktu),${#berkas[@]},$status" >> "$LOG"
echo "Unggah $status: ${#berkas[@]} berkas"

# Catatan waktu unggah ikut dikirim, agar lalu lintas unggahan ini sendiri
# dapat dikeluarkan dari data saat analisis
rclone --config "$RCLONE_CONF" copyto "$LOG" "$RCLONE_REMOTE/upload_log.csv" \
    --log-level ERROR || true
