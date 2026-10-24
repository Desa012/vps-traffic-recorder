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
    ok "pengolah & pengirim aktif (setiap 15 menit)"
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
AUDIT="$STATE/audit_log.csv"
URL=$(sed -n 's/^UPLOAD_URL=//p' "$CONF" | tr -d '"')
if [[ -n "$URL" ]]; then
    ok "server penerima: $(sed -E 's#^(https?://[^/]+).*#\1#' <<< "$URL")"
else
    info "UPLOAD_URL belum diisi — berkas disimpan di server dulu"
fi
if [[ -s "$STATE/token" ]]; then
    ok "token instalasi terpasang"
else
    info "token belum dipasang — berkas disimpan di server dulu"
fi
if [[ -s "$AUDIT" ]] && [[ $(wc -l < "$AUDIT") -gt 1 ]]; then
    sejak=$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ)
    read -r n_ok n_gagal < <(awk -F, -v s="$sejak" 'NR > 1 && $1 >= s {
        if ($5 == "TERKIRIM") a++; else if ($5 == "GAGAL_KIRIM") b++ } END {print a + 0, b + 0}' "$AUDIT")
    info "24 jam terakhir: $n_ok berkas terkirim, $n_gagal percobaan gagal"
    terakhir=$(awk -F, '$5 == "TERKIRIM" || $5 == "GAGAL_KIRIM"' "$AUDIT" | tail -n1)
    case "$terakhir" in
        "")           info "belum ada percobaan pengiriman" ;;
        *,TERKIRIM,*) ok "pengiriman terakhir berhasil: $(cut -d, -f1,2 <<< "$terakhir")" ;;
        *)            gagal "pengiriman terakhir gagal (HTTP $(cut -d, -f6 <<< "$terakhir")): $(cut -d, -f7 <<< "$terakhir")" ;;
    esac
    info "catatan lengkap: sudo cat $AUDIT"
else
    info "belum ada catatan audit"
fi

echo
echo "5. VERIFIKASI PAYLOAD (berkas terbaru di outbox)"
F=$(ls -t "$STATE"/outbox/*.hdr.pcap.gz 2>/dev/null | head -n1)
if [[ -z "$F" ]]; then
    if grep -q ',TERKIRIM,' "$AUDIT" 2>/dev/null; then
        info "outbox kosong — semua berkas sudah terkirim"
    else
        info "belum ada berkas hasil — berkas pertama siap ±1 jam setelah perekam dimulai"
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
