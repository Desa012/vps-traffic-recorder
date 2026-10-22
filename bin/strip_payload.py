#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
strip_payload.py - mengosongkan payload pada berkas pcap.

Untuk setiap paket:
  * header link-layer, IP (v4/v6 + extension header) dan transport
    (TCP/UDP/ICMP/ICMPv6/SCTP) dipertahankan apa adanya;
  * seluruh byte sesudah header (payload) diganti dengan 0x00;
  * panjang paket dikembalikan ke panjang aslinya (orig_len), sehingga
    fitur berbasis ukuran paket pada CICFlowMeter tetap benar.

Isi komunikasi (HTTP, DNS, TLS, dll.) tidak pernah ikut keluar dari server.
Hanya memakai pustaka standar Python 3 (tanpa dependensi tambahan).

Bila nama keluaran berakhiran .gz, hasil langsung ditulis terkompresi
sehingga berkas tak terkompresi (yang besar karena payload nol) tidak
pernah terbentuk di disk.

Pemakaian:
    python3 strip_payload.py MASUK.pcap KELUAR.pcap.gz
"""
import gzip
import struct
import sys

SNAPLEN_OUT = 262144          # nilai snaplen standar tcpdump
MAX_PKT = 262144              # batas aman panjang paket keluaran

# link-type pcap yang didukung -> fungsi pencari awal header IP
LT_ETHERNET = 1
LT_RAW = 101
LT_RAW_ALT = 12
LT_IPV4 = 228
LT_IPV6 = 229
LT_SLL = 113
LT_SLL2 = 276

ETH_IPV4, ETH_IPV6 = 0x0800, 0x86DD
ETH_VLAN = (0x8100, 0x88A8, 0x9100)


def l3_start(linktype, d):
    """Kembalikan (offset_awal_ip, versi_ip) atau (panjang_header_link, None)."""
    if linktype == LT_ETHERNET:
        if len(d) < 14:
            return len(d), None
        off, etype = 14, struct.unpack_from("!H", d, 12)[0]
        while etype in ETH_VLAN and len(d) >= off + 4:     # tag VLAN (bisa bertumpuk)
            etype = struct.unpack_from("!H", d, off + 2)[0]
            off += 4
        if etype == ETH_IPV4:
            return off, 4
        if etype == ETH_IPV6:
            return off, 6
        return off, None
    if linktype == LT_SLL:
        if len(d) < 16:
            return len(d), None
        proto = struct.unpack_from("!H", d, 14)[0]
        return 16, {ETH_IPV4: 4, ETH_IPV6: 6}.get(proto)
    if linktype == LT_SLL2:
        if len(d) < 20:
            return len(d), None
        proto = struct.unpack_from("!H", d, 0)[0]
        return 20, {ETH_IPV4: 4, ETH_IPV6: 6}.get(proto)
    if linktype in (LT_RAW, LT_RAW_ALT, LT_IPV4, LT_IPV6):
        if not d:
            return 0, None
        v = d[0] >> 4
        return 0, (v if v in (4, 6) else None)
    raise ValueError("link-type %d tidak didukung" % linktype)


def l4_header_len(proto, d, off):
    """Panjang header transport mulai dari offset off (0 bila tidak dikenal)."""
    if proto == 6:                                   # TCP
        if len(d) >= off + 13:
            return max(20, (d[off + 12] >> 4) * 4)
        return 20
    if proto in (17, 136):                           # UDP, UDP-Lite
        return 8
    if proto in (1, 58):                             # ICMP, ICMPv6
        return 8
    if proto == 132:                                 # SCTP (header umum)
        return 12
    return 0


def header_len(linktype, d):
    """Jumlah byte header (link + IP + transport) yang dipertahankan."""
    off, ver = l3_start(linktype, d)
    if ver is None:
        return off                                   # bukan IP: simpan header link saja

    if ver == 4:
        if len(d) < off + 20:
            return len(d)
        ihl = (d[off] & 0x0F) * 4
        proto = d[off + 9]
        frag_off = struct.unpack_from("!H", d, off + 6)[0] & 0x1FFF
        l4 = off + ihl
        if frag_off:                                 # fragmen lanjutan: tanpa header L4
            return l4
        return l4 + l4_header_len(proto, d, l4)

    # IPv6 + extension header
    if len(d) < off + 40:
        return len(d)
    nxt = d[off + 6]
    p = off + 40
    for _ in range(8):
        if nxt in (0, 43, 60):                       # hop-by-hop, routing, destination
            if len(d) < p + 2:
                return p
            nxt, p = d[p], p + (d[p + 1] + 1) * 8
        elif nxt == 44:                              # fragment
            if len(d) < p + 8:
                return p
            frag = struct.unpack_from("!H", d, p + 2)[0] >> 3
            nxt, p = d[p], p + 8
            if frag:
                return p
        elif nxt == 51:                              # authentication header
            if len(d) < p + 2:
                return p
            nxt, p = d[p], p + (d[p + 1] + 2) * 4
        else:
            break
    if nxt == 50:                                    # ESP: terenkripsi, berhenti di sini
        return p
    return p + l4_header_len(nxt, d, p)


def proses(src, dst):
    with open(src, "rb") as fi:
        gh = fi.read(24)
        if len(gh) < 24:
            raise ValueError("bukan berkas pcap (terlalu pendek)")
        magic = gh[:4]
        if magic in (b"\xd4\xc3\xb2\xa1", b"\x4d\x3c\xb2\xa1"):
            e = "<"
        elif magic in (b"\xa1\xb2\xc3\xd4", b"\xa1\xb2\x3c\x4d"):
            e = ">"
        elif magic == b"\x0a\x0d\x0d\x0a":
            raise ValueError("format pcapng tidak didukung; gunakan pcap klasik (bawaan tcpdump -w)")
        else:
            raise ValueError("magic number pcap tidak dikenal")

        vmaj, vmin, tz, sig, _snap, net = struct.unpack(e + "HHiIII", gh[4:24])
        linktype = net & 0x0FFFFFFF
        l3_start(linktype, b"")                      # validasi link-type sejak awal

        n = hdr_bytes = zeroed = 0
        buka = (lambda p: gzip.open(p, "wb", compresslevel=6)) if dst.endswith(".gz") \
            else (lambda p: open(p, "wb"))
        with buka(dst) as fo:
            fo.write(magic + struct.pack(e + "HHiIII", vmaj, vmin, tz, sig, SNAPLEN_OUT, net))
            rec = struct.Struct(e + "IIII")
            while True:
                rh = fi.read(16)
                if not rh:
                    break
                if len(rh) < 16:
                    break                            # rekaman terakhir terpotong
                ts_s, ts_f, incl, orig = rec.unpack(rh)
                data = fi.read(incl)
                if len(data) < incl:
                    break
                keep = min(header_len(linktype, data), len(data))
                total = min(max(orig, keep), MAX_PKT)
                out = data[:keep] + b"\x00" * (total - keep)
                fo.write(rec.pack(ts_s, ts_f, total, orig))
                fo.write(out)
                n += 1
                hdr_bytes += keep
                zeroed += total - keep
    return n, hdr_bytes, zeroed


def main():
    if len(sys.argv) != 3:
        sys.stderr.write(__doc__)
        return 2
    try:
        n, h, z = proses(sys.argv[1], sys.argv[2])
    except (OSError, ValueError) as ex:
        sys.stderr.write("strip_payload: GAGAL - %s\n" % ex)
        return 1
    sys.stderr.write("strip_payload: %d paket | %d byte header dipertahankan | "
                     "%d byte payload dikosongkan\n" % (n, h, z))
    return 0


if __name__ == "__main__":
    sys.exit(main())
