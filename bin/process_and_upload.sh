#!/usr/bin/env bash
# Pengolah & pengirim. Dijalankan berkala oleh traffic-uploader.timer
# sebagai user "trafficrec" (tanpa hak istimewa apa pun).
#
# 1. Mengosongkan payload setiap berkas rekaman yang sudah selesai ditulis
# 2. Menjaga total pemakaian disk di bawah MAX_DISK_MB
# 3. Mengirim setiap berkas ke server penerima lewat HTTPS dengan token per
#    instalasi; salinan lokal baru dihapus bila penerima membalas checksum yang sama
# 4. Mencatat setiap kejadian ke audit_log.csv
set -euo pipefail
shopt -s nullglob
export LC_ALL=C     # urutan glob konsisten: cap_YYYYmmdd_HHMMSS urut menurut waktu

STATE="${STATE_DIR:-/var/lib/traffic-recorder}"
BIN="${BIN_DIR:-/opt/traffic-recorder/bin}"
SPOOL="$STATE/spool"
OUTBOX="$STATE/outbox"
TMPDIR_KERJA="$STATE/tmp"
AUDIT="$STATE/audit_log.csv"
TOKEN_FILE="$STATE/token"
MAX_DISK_MB="${MAX_DISK_MB:-2048}"
UPLOAD_URL="${UPLOAD_URL:-}"
UPLOAD_CA_FILE="${UPLOAD_CA_FILE:-}"
UPLOAD_BWLIMIT="${UPLOAD_BWLIMIT:-1M}"
ALLOW_HTTP="${ALLOW_HTTP:-0}"          # hanya untuk uji lokal

waktu() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# audit NAMA UKURAN SHA256 STATUS KODE_HTTP KETERANGAN
audit() {
    local ket="${6:-}"
    ket="${ket//,/;}"; ket="${ket//$'\n'/ }"; ket="${ket//$'\r'/ }"
    printf '%s,%s,%s,%s,%s,%s,%s\n' "$(waktu)" "$1" "$2" "$3" "$4" "$5" "$ket" >> "$AUDIT"
}

mkdir -p "$SPOOL" "$OUTBOX" "$TMPDIR_KERJA"
[[ -s "$AUDIT" ]] || echo "waktu_utc,nama_file,ukuran_byte,sha256,status,kode_http,keterangan" > "$AUDIT"

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
    if (( perekam_aktif )) && [[ "$f" == "$terbaru" ]]; then
        continue                         # masih ditulis tcpdump
    fi
    dasar=$(basename "$f" .pcap)
    hasil="$dasar.hdr.pcap.gz"
    # Ditulis dulu ke folder sementara (nama harus berakhiran .gz agar langsung
    # terkompresi), lalu dipindah ke outbox setelah lengkap.
    if python3 "$BIN/strip_payload.py" "$f" "$TMPDIR_KERJA/$hasil"; then
        mv "$TMPDIR_KERJA/$hasil" "$OUTBOX/$hasil"
        audit "$hasil" "$(stat -c %s "$OUTBOX/$hasil")" \
              "$(sha256sum "$OUTBOX/$hasil" | cut -d' ' -f1)" SIAP_KIRIM - ""
    else
        rm -f "$TMPDIR_KERJA/$hasil"
        audit "$hasil" 0 - GAGAL_DIPROSES - "berkas rekaman rusak"
    fi
    rm -f "$f"                           # berkas mentah selalu dihapus
done

# ---------------------------------------------------------------- 2. batas disk
batas=$(( MAX_DISK_MB * 1024 * 1024 ))
pakai=$(du -sb "$SPOOL" "$OUTBOX" | awk '{s += $1} END {print s + 0}')
if (( pakai > batas )); then
    for f in "$OUTBOX"/*.hdr.pcap.gz; do       # urut dari yang tertua
        (( pakai <= batas )) && break
        ukuran=$(stat -c %s "$f")
        audit "$(basename "$f")" "$ukuran" - DIBUANG_KUOTA - "melebihi MAX_DISK_MB"
        rm -f "$f"
        pakai=$(( pakai - ukuran ))
    done
fi

# ---------------------------------------------------------------- 3. kirim
berkas=("$OUTBOX"/*.hdr.pcap.gz)
(( ${#berkas[@]} )) || exit 0

if [[ -z "$UPLOAD_URL" || ! -s "$TOKEN_FILE" ]]; then
    echo "UPLOAD_URL atau token belum dipasang; ${#berkas[@]} berkas disimpan lokal sampai tersedia."
    exit 0
fi
case "$UPLOAD_URL" in
    https://*) ;;
    http://*)
        if [[ "$ALLOW_HTTP" != "1" ]]; then
            echo "Ditolak: UPLOAD_URL harus memakai https://"
            exit 1
        fi ;;
    *)  echo "UPLOAD_URL tidak valid: $UPLOAD_URL"; exit 1 ;;
esac

# Token ditulis ke berkas header sementara (izin 600) agar tidak terlihat di
# daftar proses (ps) seperti bila dituliskan langsung sebagai argumen curl.
umask 077
HEADER="$TMPDIR_KERJA/auth.header"
printf 'Authorization: Bearer %s\n' "$(tr -d '[:space:]' < "$TOKEN_FILE")" > "$HEADER"
trap 'rm -f "$HEADER" "$TMPDIR_KERJA/balasan.json" "$TMPDIR_KERJA/curl.err"' EXIT

opsi=(--silent --show-error --connect-timeout 20 --max-time 900
      --limit-rate "$UPLOAD_BWLIMIT" -H @"$HEADER" -A "vps-traffic-recorder")
[[ -n "$UPLOAD_CA_FILE" ]] && opsi+=(--cacert "$UPLOAD_CA_FILE")
[[ "$ALLOW_HTTP" == "1" ]] || opsi+=(--proto "=https")

terkirim=0; gagal=0
for f in "${berkas[@]}"; do
    nama=$(basename "$f")
    ukuran=$(stat -c %s "$f")
    sha=$(sha256sum "$f" | cut -d' ' -f1)
    balasan="$TMPDIR_KERJA/balasan.json"
    rm -f "$balasan" "$TMPDIR_KERJA/curl.err"

    kode=$(curl "${opsi[@]}" -X PUT -o "$balasan" -w '%{http_code}' \
                -H "Content-Type: application/gzip" -H "X-Content-SHA256: $sha" \
                --data-binary @"$f" "${UPLOAD_URL%/}/$nama" \
                2>"$TMPDIR_KERJA/curl.err") || true
    kode="${kode:-000}"

    # Checksum yang diakui penerima harus sama dengan checksum berkas lokal
    sha_diterima=$(python3 -c 'import json,sys
try: print(json.load(open(sys.argv[1])).get("sha256", ""))
except Exception: print("")' "$balasan" 2>/dev/null || true)

    if [[ "$kode" =~ ^(200|201|409)$ && "$sha_diterima" == "$sha" ]]; then
        rm -f "$f"
        ket=""; [[ "$kode" == "409" ]] && ket="sudah ada di penerima"
        audit "$nama" "$ukuran" "$sha" TERKIRIM "$kode" "$ket"
        terkirim=$(( terkirim + 1 ))
    else
        if [[ -s "$TMPDIR_KERJA/curl.err" ]]; then
            ket=$(head -c 200 "$TMPDIR_KERJA/curl.err")
        elif [[ -n "$sha_diterima" ]]; then
            ket="checksum balasan tidak cocok"
        else
            ket=$(head -c 200 "$balasan" 2>/dev/null || true)
        fi
        audit "$nama" "$ukuran" "$sha" GAGAL_KIRIM "$kode" "$ket"
        gagal=$(( gagal + 1 ))
        # Token ditolak atau penerima tidak terjangkau: hentikan putaran ini,
        # berkas tetap aman di outbox dan dicoba lagi pada jadwal berikutnya.
        [[ "$kode" =~ ^(000|401|403)$ ]] && break
    fi
done
echo "Pengiriman: $terkirim berhasil, $gagal gagal, $(( ${#berkas[@]} - terkirim - gagal )) menunggu"
