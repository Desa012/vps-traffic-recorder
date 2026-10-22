#!/usr/bin/env bash
# Menghapus perekam lalu lintas.
#
#   sudo bash uninstall.sh          hentikan & hapus program; data dan konfigurasi dipertahankan
#   sudo bash uninstall.sh --purge  hapus semuanya, termasuk data, konfigurasi, dan user trafficrec
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Jalankan sebagai root: sudo bash uninstall.sh"
    exit 1
fi

systemctl disable --now traffic-recorder.service traffic-uploader.timer 2>/dev/null || true
systemctl stop traffic-uploader.service 2>/dev/null || true
rm -f /etc/systemd/system/traffic-recorder.service \
      /etc/systemd/system/traffic-uploader.service \
      /etc/systemd/system/traffic-uploader.timer
systemctl daemon-reload
rm -rf /opt/traffic-recorder
echo "[ok] layanan dihentikan dan program dihapus"

if [[ "${1:-}" == "--purge" ]]; then
    rm -rf /etc/traffic-recorder /var/lib/traffic-recorder
    userdel trafficrec 2>/dev/null || true
    echo "[ok] data, konfigurasi, rclone.conf, dan user trafficrec dihapus"
else
    echo "[--] data di /var/lib/traffic-recorder dan konfigurasi di /etc/traffic-recorder dipertahankan"
    echo "     jalankan 'sudo bash uninstall.sh --purge' untuk menghapus semuanya"
fi
