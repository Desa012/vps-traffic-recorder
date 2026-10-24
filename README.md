# Perekam Header Lalu Lintas Jaringan

Perangkat ini merekam **header paket** lalu lintas jaringan server untuk penelitian Tugas Akhir
*"Rancang Bangun NIDS Berbasis Machine Learning untuk Deteksi Anomali, Monitoring, dan Notifikasi
pada Server VPS"* — Putu Satria Arya Putra, Teknologi Informasi, Universitas Udayana.

Hasil rekaman dikirim otomatis ke **server penerima melalui HTTPS**, dengan token unik untuk setiap
instalasi. Setiap pengiriman dicatat dalam **catatan audit** yang dapat diperiksa pihak perusahaan.

**Sudah diuji pada:** Ubuntu 24.04 LTS dan Ubuntu 26.04 LTS.

---

## Mulai dari sini

Dokumen ini dibaca dari atas ke bawah. Yang Bapak/Ibu terima dari Satria:

| Diterima | Lewat | Dipakai di |
|---|---|---|
| Link repositori ini | Chat | Langkah 2 |
| `token.txt` — token unggah khusus server perusahaan | Dokumen pribadi (bukan GitHub) | Langkah 3 |
| `login-dashboard.txt` — akun dashboard baca-saja | Dokumen pribadi | [Melihat berkas yang diterima](#melihat-berkas-yang-diterima-dashboard--api) |
| `token-api-baca.txt` — token API baca-saja (opsional) | Dokumen pribadi | [Melihat berkas yang diterima](#melihat-berkas-yang-diterima-dashboard--api) |

Urutannya: **[Pemasangan](#pemasangan--10-menit)** (Langkah 1–6, ± 10 menit) →
**[Melihat berkas yang diterima](#melihat-berkas-yang-diterima-dashboard--api)** →
bila perlu, **[Operasional sehari-hari](#operasional-sehari-hari)** dan
**[Pemecahan masalah](#pemecahan-masalah)**.

---

## Ringkasan untuk peninjauan keamanan

| Aspek | Penjelasan |
|---|---|
| **Yang dikirim keluar** | Header paket saja: alamat IP, port, protokol, flag TCP, ukuran paket, dan waktu |
| **Yang TIDAK dikirim** | Isi komunikasi (payload) — HTTP, DNS, email, isi TLS/SSH, dll. **diganti nol** sebelum berkas meninggalkan server |
| **Tujuan pengiriman** | Hanya satu alamat: `UPLOAD_URL` di konfigurasi. **Wajib HTTPS**; alamat `http://` ditolak |
| **Autentikasi** | Token unik per instalasi, disimpan dengan izin 600 dan **tidak terlihat di daftar proses** (`ps`) |
| **Integritas** | Setiap berkas dikirim bersama checksum SHA-256. Salinan lokal **baru dihapus bila penerima membalas checksum yang sama** |
| **Audit** | Setiap kejadian dicatat di `audit_log.csv`: nama berkas, ukuran, checksum, waktu, status, kode HTTP |
| **Hak akses** | Berjalan sebagai user khusus `trafficrec` (tanpa login, tanpa password). Satu-satunya hak istimewa: `CAP_NET_RAW` untuk membaca paket. **Tidak berjalan sebagai root** |
| **Port masuk** | Tidak membuka port apa pun. Hanya koneksi keluar HTTPS ke server penerima |
| **Sandbox** | Sistem berkas hanya-baca kecuali `/var/lib/traffic-recorder`; folder `/home` tidak dapat diakses |
| **Batas sumber daya** | CPU maks. 25–30%, memori maks. 256–512 MB, prioritas I/O terendah, disk maks. 2 GB, unggah maks. 1 MB/detik |
| **Batas waktu** | Berhenti otomatis setelah 14 hari |
| **Kode** | Empat skrip pendek (bash + Python standar) yang dapat dibaca di folder `bin/` |

---

## Isi folder ini

**Yang perlu dijalankan hanya `install.sh`** (dan `uninstall.sh` bila ingin menghapus).
Berkas lain disalin dan dipanggil otomatis oleh `install.sh` — tidak perlu dibuka satu per satu,
kecuali untuk ditinjau.

| Berkas | Fungsi |
|---|---|
| `install.sh` | **Pemasang** — satu-satunya yang dijalankan untuk memulai |
| `uninstall.sh` | Penghapus |
| `config.env.example` | Contoh konfigurasi (disalin otomatis ke `/etc/traffic-recorder/config.env`) |
| `bin/record.sh` | Menjalankan tcpdump untuk merekam |
| `bin/process_and_upload.sh` | Mengosongkan isi paket, mengirim ke server penerima, dan mencatat audit |
| `bin/strip_payload.py` | Bagian yang mengganti isi paket dengan nol |
| `bin/cek-status.sh` | Pemeriksa kondisi perekam (dipakai di Langkah 5) |
| `systemd/` | Tiga berkas layanan agar perekam berjalan otomatis di latar belakang |
| `.gitignore`, `.gitattributes` | Pengaturan Git; tidak berpengaruh pada server |

---

## Pemasangan (± 10 menit)

Semua perintah dijalankan **di server**, sebagai root atau dengan `sudo`.

### Langkah 1 — Pasang program pendukung

```bash
# Ubuntu / Debian
sudo apt update && sudo apt install -y tcpdump python3 curl

# AlmaLinux / Rocky / RHEL
sudo dnf install -y tcpdump python3 curl
```

### Langkah 2 — Ambil folder perekam

```bash
# dari GitHub
git clone https://github.com/Desa012/vps-traffic-recorder.git
cd vps-traffic-recorder

# atau dari berkas ZIP yang sudah disalin ke server
unzip vps-traffic-recorder.zip && cd vps-traffic-recorder
```

> Bila sebelumnya sudah sempat memasang versi lama (Google Drive/rclone): cukup `cd vps-traffic-recorder`
> lalu `git pull`, kemudian lanjut ke Langkah 3. Data yang sudah terekam tidak hilang dan akan ikut terkirim.

### Langkah 3 — Pasang

Salin `token.txt` ke server (mis. ke folder `vps-traffic-recorder` ini), lalu jalankan:

```bash
sudo bash install.sh --url https://srv2058324.hstgr.cloud/api/v1/upload --token token.txt
```

Hasil yang benar — semua baris diawali `[ok]`:

```
[ok] user sistem 'trafficrec' dibuat (tanpa login, tanpa password)
[ok] program dipasang di /opt/traffic-recorder (hanya root yang dapat mengubah)
[ok] konfigurasi dibuat di /etc/traffic-recorder/config.env (antarmuka terdeteksi: eth0)
[ok] alamat server penerima: https://srv2058324.hstgr.cloud/api/v1/upload
[ok] token instalasi dipasang di /var/lib/traffic-recorder/token (hanya dapat dibaca user trafficrec)
[ok] layanan systemd dipasang (belum dijalankan)
```

Langkah ini **belum memulai perekaman**, jadi konfigurasi bisa diperiksa dulu:
`sudo nano /etc/traffic-recorder/config.env` (lihat bagian *Konfigurasi* di bawah).

Setelah dipasang, berkas `token.txt` salinan tadi sebaiknya dihapus.

### Langkah 4 — Mulai merekam

```bash
sudo systemctl enable --now traffic-recorder.service traffic-uploader.timer
```

### Langkah 5 — Periksa

```bash
sudo bash /opt/traffic-recorder/bin/cek-status.sh
```

Hasil yang benar tepat setelah dimulai:

```
1. LAYANAN
  [OK] perekam berjalan (antarmuka eth0)
  [OK] pengolah & pengirim aktif (setiap 15 menit)
       berhenti otomatis pada: 29 Oct 2026 13:07 UTC

2. HAK AKSES PEREKAM
  [OK] berjalan sebagai user 'trafficrec', bukan root
  [OK] hak istimewa hanya CAP_NET_RAW (membaca paket)

3. BERKAS
       sedang direkam         : 1 berkas
       siap dikirim (outbox)  : 0 berkas
       pemakaian disk         : 240K (batas 2048 MB)

4. PENGIRIMAN
  [OK] server penerima: https://srv2058324.hstgr.cloud
  [OK] token instalasi terpasang
       belum ada catatan audit

5. VERIFIKASI PAYLOAD (berkas terbaru di outbox)
       belum ada berkas hasil — berkas pertama siap ±1 jam setelah perekam dimulai
```

> ⏱ **Berkas pertama baru terkirim sekitar 1 jam setelah dimulai.** Perekam menutup berkas
> setiap 1 jam, lalu pengolah memprosesnya dalam 15 menit berikutnya. Selama jam pertama,
> server penerima memang belum menerima apa pun — ini normal.

### Langkah 6 — Pastikan berkas sampai di server penerima

Setelah ± 1,5 jam, jalankan `cek-status.sh` lagi. Bagian 4 harus menampilkan
`[OK] pengiriman terakhir berhasil`.

Lalu buka dashboard **https://srv2058324.hstgr.cloud** dan login dengan akun di `login-dashboard.txt`.
Kartu **bali-hai** harus berlabel **aktif** dan berkas pertama tampil di tabel
(lihat [Melihat berkas yang diterima](#melihat-berkas-yang-diterima-dashboard--api)).

**Selesai.** Perekam berjalan sendiri, termasuk setelah server di-restart, dan berhenti otomatis
setelah 14 hari.

---

## Catatan audit pengiriman

Setiap kejadian dicatat di server ini pada **`/var/lib/traffic-recorder/audit_log.csv`**:

```bash
sudo cat /var/lib/traffic-recorder/audit_log.csv
```

| Kolom | Isi |
|---|---|
| `waktu_utc` | Waktu kejadian (UTC) |
| `nama_file` | Nama berkas, mis. `cap_20261023_010000.hdr.pcap.gz` |
| `ukuran_byte` | Ukuran berkas |
| `sha256` | Checksum berkas — dapat dicocokkan dengan catatan di server penerima |
| `status` | `SIAP_KIRIM`, `TERKIRIM`, `GAGAL_KIRIM`, `GAGAL_DIPROSES`, atau `DIBUANG_KUOTA` |
| `kode_http` | Kode balasan server penerima (`201` berhasil, `409` sudah pernah diterima, `401` token ditolak, `000` tidak terhubung) |
| `keterangan` | Penjelasan bila gagal |

Contoh:

```
waktu_utc,nama_file,ukuran_byte,sha256,status,kode_http,keterangan
2026-10-23T01:15:02Z,cap_20261023_000000.hdr.pcap.gz,75371,9f2c…e1a0,SIAP_KIRIM,-,
2026-10-23T01:15:03Z,cap_20261023_000000.hdr.pcap.gz,75371,9f2c…e1a0,TERKIRIM,201,
```

Server penerima menyimpan catatan yang sama dari sisinya (berkas diterima, ukuran, checksum,
waktu). Kedua catatan dapat dicocokkan melalui kolom `sha256`: setiap berkas berstatus `TERKIRIM`
di sini harus tercatat **diterima dengan checksum yang sama** di server penerima.

**Bila pengiriman gagal**, berkas tidak dihapus: berkas tetap di `outbox` dan dicoba lagi otomatis
setiap 15 menit sampai berhasil (dibatasi `MAX_DISK_MB`).

---

## Melihat berkas yang diterima (dashboard & API)

Perusahaan memiliki akses **baca-saja** ke server penerima. Akses ini hanya menampilkan data dari
server perusahaan sendiri.

### Dashboard

Buka **https://srv2058324.hstgr.cloud** dan login dengan akun dari `login-dashboard.txt`.

| Menu | Isi |
|---|---|
| **Ringkasan** | Status pengiriman (*aktif* / *menunggu kiriman pertama* / merah bila > 2 jam tidak ada kiriman), jumlah berkas, total ukuran, rekaman dan kiriman terakhir |
| **Berkas diterima** | Daftar semua berkas: waktu mulai direkam, nama, ukuran, waktu diterima, SHA-256; dapat disaring per tanggal dan **diunduh** |
| **Catatan audit** | Setiap upaya unggah (diterima, duplikat, ditolak beserta alasannya), unduhan, dan login |

Waktu di dashboard memakai **WITA**. Nama berkas memakai **UTC**: `cap_20261023_200451` berarti mulai
direkam 23 Okt 20:04:51 UTC = 24 Okt 04.04 WITA. Satu berkas berisi rekaman satu jam.

**Mencocokkan berkas terkirim dan diterima:** kolom SHA-256 di dashboard sama dengan kolom `sha256` di
`audit_log.csv` server ini. Setiap baris `TERKIRIM` di sini harus muncul di menu *Berkas diterima*.

### API (opsional, untuk otomasi)

Dengan token dari `token-api-baca.txt`:

```bash
TOKEN=$(cat token-api-baca.txt)
curl -H "Authorization: Bearer $TOKEN" https://srv2058324.hstgr.cloud/api/v1/summary
curl -H "Authorization: Bearer $TOKEN" "https://srv2058324.hstgr.cloud/api/v1/files?since=2026-10-24&limit=100"
curl -H "Authorization: Bearer $TOKEN" "https://srv2058324.hstgr.cloud/api/v1/audit?limit=50"
curl -H "Authorization: Bearer $TOKEN" -OJ https://srv2058324.hstgr.cloud/api/v1/files/<id>/download
```

| Endpoint | Isi (JSON, waktu UTC) |
|---|---|
| `/api/v1/summary` | Jumlah berkas, total byte, kiriman pertama/terakhir, rekaman terbaru |
| `/api/v1/files` | Daftar berkas diterima; parameter `since`, `until` (`YYYY-MM-DD`), `limit` (maks. 1000), `offset` |
| `/api/v1/files/<id>/download` | Unduh satu berkas |
| `/api/v1/audit` | Catatan audit server penerima |

Akun dashboard dan token API dapat dinonaktifkan atau diganti kapan saja oleh Satria atas permintaan
perusahaan.

---

## Kontrak API server penerima

Untuk transparansi, berikut seluruh permintaan yang dikirim perekam ini:

```
PUT <UPLOAD_URL>/<nama_berkas>
Authorization: Bearer <token>
Content-Type: application/gzip
X-Content-SHA256: <checksum SHA-256 berkas>

<isi berkas .hdr.pcap.gz>
```

Balasan yang diharapkan:

| Kode | Arti | Tindakan perekam |
|---|---|---|
| `201` | Berkas diterima. Badan balasan JSON memuat `"sha256"` | Bila checksum sama → salinan lokal dihapus, status `TERKIRIM` |
| `409` | Berkas yang sama sudah pernah diterima. JSON memuat `"sha256"` | Sama seperti `201` (pengiriman ulang setelah balasan sebelumnya hilang) |
| `401` / `403` | Token ditolak | Berkas disimpan, pengiriman dihentikan sampai jadwal berikutnya |
| lainnya | Gagal | Berkas disimpan, dicoba lagi pada jadwal berikutnya |

Tidak ada data lain yang dikirim: tidak ada nama host, isi konfigurasi, atau informasi sistem
(header `User-Agent` diisi nama netral `vps-traffic-recorder`). Satu-satunya hal yang dengan
sendirinya terlihat oleh server penerima adalah alamat IP publik server ini sebagai sumber koneksi.

---

## Memeriksa sendiri bahwa isi komunikasi tidak ikut terekam

`cek-status.sh` bagian 5 memeriksanya secara otomatis. Untuk melihat isi berkas secara langsung:

```bash
F=$(ls -t /var/lib/traffic-recorder/outbox/*.gz | head -1)
sudo zcat $F | tcpdump -r - -nn -X -c 2
```

Contoh hasil dari server uji (paket SSH; alamat IP diganti contoh):

```
IP 203.0.113.10.15121 > 198.51.100.20.22: Flags [P.], ... length 36
    0x0000:  4500 004c 4292 4000 7006 53ff cb00 710a   ← header IP
    0x0010:  c633 6414 3b11 0016 6971 4c97 b553 2038   ← header TCP
    0x0020:  5018 00ff a129 0000 0000 0000 0000 0000   ← mulai dari sini: isi = nol
    0x0030:  0000 0000 0000 0000 0000 0000 0000 0000
```

Header (alamat, port, flag) tetap utuh, isi diganti nol, dan panjang aslinya (`length 36`) tetap
tercatat. Bila outbox kosong karena semua berkas sudah terkirim, pemeriksaan bisa dilakukan pada
berkas berikutnya.

Catatan: karena isinya diganti nol, *checksum* TCP/UDP pada berkas hasil tidak lagi cocok
(`cksum ... incorrect`). Ini normal dan tidak berpengaruh pada penelitian.

---

## Operasional sehari-hari

| Keperluan | Perintah |
|---|---|
| Lihat kondisi lengkap | `sudo bash /opt/traffic-recorder/bin/cek-status.sh` |
| Lihat catatan audit | `sudo cat /var/lib/traffic-recorder/audit_log.csv` |
| Hentikan sementara | `sudo systemctl stop traffic-recorder.service traffic-uploader.timer` |
| Lanjutkan | `sudo systemctl start traffic-recorder.service traffic-uploader.timer` |
| Log pengirim | `journalctl -u traffic-uploader.service -n 30` |
| Ganti token | `sudo bash install.sh --token /path/ke/token-baru.txt` |
| Hapus program (data & audit tetap ada) | `sudo bash uninstall.sh` |
| **Hapus semuanya** — program, data, token, audit, user `trafficrec` | `sudo bash uninstall.sh --purge` |

Pengiriman dapat dihentikan kapan saja dengan menghapus `/var/lib/traffic-recorder/token`;
berkas tetap direkam dan disimpan lokal sampai token dipasang kembali.

---

## Konfigurasi

Berkas: `/etc/traffic-recorder/config.env`

| Variabel | Bawaan | Arti |
|---|---|---|
| `INTERFACE` | otomatis | Antarmuka yang direkam (`ip -br link`) |
| `SNAPLEN` | `160` | Byte maksimum yang disalin per paket dari kernel |
| `ROTATE_SECONDS` | `3600` | Lama satu berkas rekaman (detik) |
| `DURATION_DAYS` | `14` | Berhenti otomatis setelah N hari; `0` = tidak berhenti |
| `EXTRA_BPF` | kosong | Filter tambahan untuk mengecualikan lalu lintas, mis. `"not port 3306"` |
| `MAX_DISK_MB` | `2048` | Batas pemakaian disk lokal; bila terlampaui, berkas tertua dibuang |
| `UPLOAD_URL` | kosong | Endpoint server penerima (wajib `https://`) |
| `UPLOAD_CA_FILE` | kosong | Sertifikat CA bila server penerima memakai sertifikat sendiri |
| `UPLOAD_BWLIMIT` | `1M` | Batas kecepatan unggah |

Setelah mengubah konfigurasi:

```bash
sudo systemctl restart traffic-recorder.service
```

> **Khusus `DURATION_DAYS`:** jadwal berhenti dihitung sejak perekam **pertama kali** dijalankan
> dan disimpan di `/var/lib/traffic-recorder/stop_at`. Bila nilainya diubah setelah perekam pernah
> berjalan, hapus jadwal lama terlebih dahulu:
>
> ```bash
> sudo rm /var/lib/traffic-recorder/stop_at
> sudo systemctl restart traffic-recorder.service
> ```

---

## Cara kerja

```
 antarmuka jaringan
        │
        ▼
 ┌──────────────────────┐   tcpdump: hanya 160 byte pertama tiap paket,
 │ traffic-recorder     │   berkas baru setiap 1 jam
 │ (berjalan terus)     │──► /var/lib/traffic-recorder/spool/cap_*.pcap
 └──────────────────────┘
        │  setiap 15 menit
        ▼
 ┌──────────────────────┐   1. strip_payload.py: isi paket diganti nol, header
 │ traffic-uploader     │      dipertahankan, langsung dikompres (.gz)
 │ (timer 15 menit)     │   2. berkas mentah langsung dihapus
 └──────────────────────┘   3. curl: PUT ke server penerima (HTTPS + token + checksum)
        │                   4. dicatat di audit_log.csv; salinan lokal dihapus
        ▼                      hanya bila checksum balasan cocok
   Server penerima:  cap_YYYYMMDD_HHMMSS.hdr.pcap.gz  +  catatan audit penerima
```

**Kenapa isi paket diganti nol, bukan dipotong?** Alat ekstraksi fitur penelitian (CICFlowMeter)
menghitung ukuran paket dari byte yang ada di berkas. Bila isinya dipotong, fitur ukuran paket
menjadi salah. Dengan diganti nol: isi komunikasi hilang sepenuhnya, panjang paket tetap benar,
dan ukuran berkas tetap kecil karena deretan nol terkompres sangat baik (uji: 88 MB → 1,7 MB).

Waktu setiap pengiriman di `audit_log.csv` juga dipakai untuk mengeluarkan lalu lintas pengiriman
dari perekam ini sendiri saat data dianalisis.

| Lokasi | Isi |
|---|---|
| `/opt/traffic-recorder/` | Program (milik root) |
| `/etc/traffic-recorder/config.env` | Konfigurasi |
| `/var/lib/traffic-recorder/` | Data sementara, `token`, `audit_log.csv` (izin 700, milik `trafficrec`) |
| `/etc/systemd/system/traffic-*` | Layanan systemd |

---

## Pemecahan masalah

| Gejala | Penyebab & solusi |
|---|---|
| `Permission denied` saat menjalankan `./install.sh` | Gunakan `sudo bash install.sh` (izin eksekusi bisa hilang saat berkas dikirim lewat ZIP/GitHub) |
| `antarmuka ... tidak ditemukan` | Ubah `INTERFACE` sesuai keluaran `ip -br link`, lalu restart perekam |
| `tcpdump: ... Operation not permitted` | Kernel/distribusi lama memerlukan hak tambahan. Tambahkan `CAP_NET_ADMIN` pada `AmbientCapabilities` dan `CapabilityBoundingSet` di `/etc/systemd/system/traffic-recorder.service`, lalu `sudo systemctl daemon-reload && sudo systemctl restart traffic-recorder.service` |
| Server penerima masih kosong pada jam pertama | Normal — lihat catatan ⏱ di Langkah 5 |
| Audit: `GAGAL_KIRIM` kode `401` | Token ditolak. Minta token baru dari pengelola server penerima, lalu `sudo bash install.sh --token token-baru.txt` |
| Audit: `GAGAL_KIRIM` kode `000` | Server penerima tidak terjangkau atau sertifikat HTTPS tidak dipercaya. Periksa `UPLOAD_URL`, koneksi keluar port 443, dan `UPLOAD_CA_FILE` bila sertifikatnya buatan sendiri |
| `Ditolak: UPLOAD_URL harus memakai https://` | Alamat penerima wajib HTTPS |
| Berkas menumpuk di outbox | Pengiriman belum berhasil — lihat kolom `keterangan` di audit. Berkas tetap aman dan terkirim otomatis setelah masalahnya diperbaiki |
| Perekam berhenti lebih cepat dari seharusnya | Jadwal berhenti lama masih tersimpan — lihat catatan di bagian *Konfigurasi* |
| Status `inactive` setelah 14 hari | Normal — masa perekaman sudah selesai |

---

## Komitmen pengelolaan data

- Data hanya digunakan untuk penelitian Tugas Akhir di atas.
- Data dikirim hanya ke server penerima yang disepakati dengan perusahaan, melalui HTTPS dengan
  token khusus instalasi ini. Setiap berkas yang keluar tercatat di `audit_log.csv` dan dapat
  dicocokkan dengan catatan di server penerima.
- Data tidak dibagikan kepada pihak lain dan dihapus setelah penelitian selesai.
- Dalam naskah Tugas Akhir, alamat IP yang dapat mengidentifikasi pihak tertentu tidak dicantumkan.

**Kontak:** 087754459235 Putu Satria Arya Putra — Teknologi Informasi, Universitas Udayana.
