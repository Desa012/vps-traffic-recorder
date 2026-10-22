#!/usr/bin/env bash
# Perekam lalu lintas. Dijalankan oleh systemd (traffic-recorder.service)
# sebagai user tanpa login "trafficrec" yang hanya memegang hak CAP_NET_RAW.
set -euo pipefail

STATE="${STATE_DIR:-/var/lib/traffic-recorder}"
SPOOL="$STATE/spool"

: "${INTERFACE:?INTERFACE belum diisi di /etc/traffic-recorder/config.env}"
SNAPLEN="${SNAPLEN:-160}"
ROTATE_SECONDS="${ROTATE_SECONDS:-3600}"
DURATION_DAYS="${DURATION_DAYS:-0}"
EXTRA_BPF="${EXTRA_BPF:-}"

mkdir -p "$SPOOL"

# Hanya paket IPv4/IPv6; filter tambahan dari konfigurasi bila ada
FILTER="(ip or ip6)"
if [[ -n "$EXTRA_BPF" ]]; then
    FILTER="$FILTER and ($EXTRA_BPF)"
fi

# Berhenti otomatis setelah DURATION_DAYS hari, dihitung sejak pertama kali dijalankan
PREFIX=()
if (( DURATION_DAYS > 0 )); then
    if [[ ! -s "$STATE/stop_at" ]]; then
        echo $(( $(date +%s) + DURATION_DAYS * 86400 )) > "$STATE/stop_at"
    fi
    sisa=$(( $(cat "$STATE/stop_at") - $(date +%s) ))
    if (( sisa <= 0 )); then
        echo "Masa perekaman ${DURATION_DAYS} hari sudah selesai. Perekam tidak dijalankan."
        exit 0
    fi
    echo "Perekaman akan berhenti otomatis dalam $(( sisa / 3600 )) jam."
    PREFIX=(timeout --signal=INT "$sisa")
fi

echo "Merekam antarmuka $INTERFACE | snaplen $SNAPLEN byte | berkas baru tiap $ROTATE_SECONDS detik"
echo "Filter: $FILTER"

# -n : tanpa resolusi DNS     -p : tanpa mode promiscuous
# -s : hanya SNAPLEN byte pertama tiap paket yang disalin dari kernel
# -G : berkas baru setiap ROTATE_SECONDS detik (nama memakai waktu UTC)
exec ${PREFIX[@]+"${PREFIX[@]}"} tcpdump -n -p -i "$INTERFACE" -s "$SNAPLEN" \
    -G "$ROTATE_SECONDS" -w "$SPOOL/cap_%Y%m%d_%H%M%S.pcap" "$FILTER"
