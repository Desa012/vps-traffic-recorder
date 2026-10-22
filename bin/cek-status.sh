#!/usr/bin/env bash
# Ringkasan kondisi perekam dalam satu layar.
#   sudo bash /opt/traffic-recorder/bin/cek-status.sh
STATE=/var/lib/traffic-recorder
CONF=/etc/traffic-recorder/config.env

ok()   { printf "  [OK] %s\n" "$*"; }
gagal(){ printf "  [!!] %s\n" "$*"; }
info() { printf "       %s\n" "$*"; }

if [[ $EUID -ne 0 ]]; then
    echo "Jalankan sebagai root: sudo bash $0"
    exit 1
fi
[[ -f "$CONF" ]] || { echo "Perekam belum dipasang (konfigurasi $CONF tidak ada)."; exit 1; }
MAX_DISK_MB=$(sed -n 's/^MAX_DISK_MB=//p' "$CONF" | tr -d '"')
INTERFACE=$(sed -n 's/^INTERFACE=//p' "$CONF" | tr -d '"')

echo
echo "1. LAYANAN"
if systemctl is-active --quiet traffic-recorder.service; then
    ok "perekam berjalan (antarmuka $INTERFACE)"
else
    gagal "perekam TIDAK berjalan — status: $(systemctl is-active traffic-recorder.service)"
fi
if systemctl is-active --quiet traffic-uploader.timer; then
    ok "pengolah & pengunggah aktif (setiap 15 menit)"
else
    gagal "timer pengunggah TIDAK aktif"
fi
if [[ -s "$STATE/stop_at" ]]; then
    info "berhenti otomatis pada: $(date -d @"$(cat "$STATE/stop_at")" '+%d %b %Y %H:%M %Z')"
fi

echo
echo "2. HAK AKSES PEREKAM"
pid=$(pgrep -x tcpdump | head -n1)
if [[ -n "$pid" ]]; then
    pemilik=$(stat -c %U "/proc/$pid")
    cap=$(awk '/^CapEff/ {print $2}' "/proc/$pid/status")
    [[ "$pemilik" == "trafficrec" ]] && ok "berjalan sebagai user 'trafficrec', bukan root" \
                                     || gagal "berjalan sebagai '$pemilik'"
    [[ "$cap" == "0000000000002000" ]] && ok "hak istimewa hanya CAP_NET_RAW (membaca paket)" \
                                       || gagal "hak istimewa tidak sesuai (CapEff=$cap)"
else
    info "proses tcpdump tidak ditemukan"
fi

echo
echo "3. BERKAS"
n_spool=$(find "$STATE/spool" -name 'cap_*.pcap' 2>/dev/null | wc -l)
n_outbox=$(find "$STATE/outbox" -name '*.hdr.pcap.gz' 2>/dev/null | wc -l)
info "sedang direkam         : $n_spool berkas"
info "siap dikirim (outbox)  : $n_outbox berkas"
info "pemakaian disk         : $(du -sh "$STATE" | cut -f1) (batas ${MAX_DISK_MB} MB)"

echo
echo "4. PENGIRIMAN"
if [[ -f "$STATE/rclone.conf" ]]; then
    ok "rclone.conf terpasang"
else
    info "rclone.conf belum dipasang — berkas disimpan di server dulu"
fi
if [[ -s "$STATE/upload_log.csv" ]] && [[ $(wc -l < "$STATE/upload_log.csv") -gt 1 ]]; then
    terakhir=$(tail -n1 "$STATE/upload_log.csv")
    case "$terakhir" in
        *,OK)     ok "unggahan terakhir berhasil: $terakhir" ;;
        *GAGAL*)  gagal "unggahan terakhir gagal: $terakhir — lihat: journalctl -u traffic-uploader.service -n 30" ;;
        *)        info "catatan terakhir: $terakhir" ;;
    esac
else
    info "belum ada unggahan"
fi

echo
echo "5. VERIFIKASI PAYLOAD (berkas terbaru di outbox)"
F=$(ls -t "$STATE"/outbox/*.hdr.pcap.gz 2>/dev/null | head -n1)
if [[ -z "$F" ]]; then
    if (( n_spool > 0 )) && [[ ! -f "$STATE/rclone.conf" || ! -s "$STATE/upload_log.csv" ]]; then
        info "belum ada berkas hasil — berkas pertama siap ±1 jam setelah perekam dimulai"
    else
        info "outbox kosong — semua berkas sudah terkirim"
    fi
else
    gzip -t "$F" 2>/dev/null && ok "format berkas valid: $(basename "$F")" || gagal "berkas rusak: $(basename "$F")"
    info "jumlah paket: $(zcat "$F" | tcpdump -r - -nn 2>/dev/null | wc -l)"
    teks=$(zcat "$F" | grep -a -c -E 'Host:|User-Agent|Cookie|SSH-2.0')
    if [[ "$teks" == "0" ]]; then
        ok "tidak ditemukan isi komunikasi (Host, User-Agent, Cookie, banner SSH)"
    else
        gagal "ditemukan $teks potongan isi komunikasi — hentikan perekam dan hubungi peneliti"
    fi
fi
echo
