#!/usr/bin/env bash
# Pemasang perekam lalu lintas.
#
#   sudo bash install.sh                       pasang tanpa konfigurasi unggah
#   sudo bash install.sh /path/ke/rclone.conf  pasang sekaligus konfigurasi unggah
#
# Skrip ini TIDAK menjalankan perekaman. Perekaman baru dimulai setelah
# administrator memeriksa konfigurasi lalu menjalankan perintah systemctl
# yang ditampilkan di akhir.
set -euo pipefail
cd "$(dirname "$0")"

USR=trafficrec
OPT=/opt/traffic-recorder
ETC=/etc/traffic-recorder
STATE=/var/lib/traffic-recorder

if [[ $EUID -ne 0 ]]; then
    echo "Jalankan sebagai root: sudo bash install.sh"
    exit 1
fi

# ---------------------------------------------------------------- 1. dependensi
kurang=()
for c in tcpdump python3 rclone flock timeout pgrep gzip systemctl; do
    command -v "$c" >/dev/null 2>&1 || kurang+=("$c")
done
if (( ${#kurang[@]} )); then
    echo "Program berikut belum terpasang: ${kurang[*]}"
    echo "  Debian/Ubuntu     : apt install tcpdump python3 rclone util-linux coreutils procps gzip"
    echo "  RHEL/Alma/Rocky   : dnf install epel-release && dnf install tcpdump python3 rclone util-linux coreutils procps-ng gzip"
    exit 1
fi
python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 5) else 1)' \
    || { echo "Dibutuhkan Python 3.5 atau lebih baru."; exit 1; }

# ---------------------------------------------------------------- 2. user khusus tanpa login
if ! id "$USR" >/dev/null 2>&1; then
    useradd --system --no-create-home --home-dir "$STATE" --shell /usr/sbin/nologin "$USR"
    echo "[ok] user sistem '$USR' dibuat (tanpa login, tanpa password)"
fi

# ---------------------------------------------------------------- 3. program (milik root)
install -d -m 755 "$OPT" "$OPT/bin"
install -m 755 bin/record.sh bin/process_and_upload.sh bin/strip_payload.py bin/cek-status.sh "$OPT/bin/"
install -m 644 README.md "$OPT/"
echo "[ok] program dipasang di $OPT (hanya root yang dapat mengubah)"

# ---------------------------------------------------------------- 4. konfigurasi
install -d -m 750 -g "$USR" "$ETC"
if [[ ! -f "$ETC/config.env" ]]; then
    install -m 640 -g "$USR" config.env.example "$ETC/config.env"
    iface=$(ip route show default 2>/dev/null | awk '{for (i = 1; i < NF; i++) if ($i == "dev") {print $(i + 1); exit}}')
    if [[ -n "$iface" ]]; then
        sed -i "s/^INTERFACE=.*/INTERFACE=$iface/" "$ETC/config.env"
        echo "[ok] konfigurasi dibuat di $ETC/config.env (antarmuka terdeteksi: $iface)"
    else
        echo "[!!] konfigurasi dibuat di $ETC/config.env — isi INTERFACE secara manual"
    fi
else
    echo "[ok] konfigurasi lama di $ETC/config.env dipertahankan"
fi

# ---------------------------------------------------------------- 5. folder data
install -d -m 700 -o "$USR" -g "$USR" "$STATE" "$STATE/spool" "$STATE/outbox"
if [[ -n "${1:-}" ]]; then
    install -m 600 -o "$USR" -g "$USR" "$1" "$STATE/rclone.conf"
    echo "[ok] rclone.conf dipasang di $STATE/rclone.conf (hanya dapat dibaca user $USR)"
else
    echo "[--] rclone.conf belum dipasang; berkas akan tersimpan lokal sampai dipasang:"
    echo "     sudo install -m 600 -o $USR -g $USR rclone.conf $STATE/rclone.conf"
fi

# ---------------------------------------------------------------- 6. cek antarmuka
INTERFACE=$(sed -n 's/^INTERFACE=//p' "$ETC/config.env" | tr -d '"')
if ! ip link show "$INTERFACE" >/dev/null 2>&1; then
    echo "[!!] antarmuka '$INTERFACE' tidak ditemukan. Lihat daftar dengan: ip -br link"
fi

# ---------------------------------------------------------------- 7. systemd
install -m 644 systemd/traffic-recorder.service systemd/traffic-uploader.service \
    systemd/traffic-uploader.timer /etc/systemd/system/
systemctl daemon-reload
if systemctl is-active --quiet traffic-recorder.service; then
    echo "[ok] layanan systemd diperbarui (perekam yang sedang berjalan tidak diganggu)"
else
    echo "[ok] layanan systemd dipasang (belum dijalankan)"
fi

cat <<EOF

Pemasangan selesai. Langkah berikutnya:

  1. Periksa konfigurasi : sudo nano $ETC/config.env
  2. Mulai merekam       : sudo systemctl enable --now traffic-recorder.service traffic-uploader.timer
  3. Cek kondisi         : sudo bash $OPT/bin/cek-status.sh
  4. Hentikan            : sudo systemctl disable --now traffic-recorder.service traffic-uploader.timer
  5. Hapus seluruhnya    : sudo bash uninstall.sh --purge

EOF
