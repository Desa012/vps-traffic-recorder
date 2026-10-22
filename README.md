# Perekam Header Lalu Lintas Jaringan

Perangkat ini merekam **header paket** lalu lintas jaringan server untuk penelitian Tugas Akhir
*"Rancang Bangun NIDS Berbasis Machine Learning untuk Deteksi Anomali, Monitoring, dan Notifikasi
pada Server VPS"* — Putu Satria Arya Putra, Teknologi Informasi, Universitas Udayana.

Hasil rekaman dikirim otomatis ke Google Drive peneliti, tanpa perlu dikirim manual.

**Sudah diuji pada:** Ubuntu 24.04 LTS dan Ubuntu 26.04 LTS.

---

## Ringkasan untuk peninjauan keamanan

| Aspek | Penjelasan |
|---|---|
| **Yang dikirim keluar** | Header paket saja: alamat IP, port, protokol, flag TCP, ukuran paket, dan waktu |
| **Yang TIDAK dikirim** | Isi komunikasi (payload) — HTTP, DNS, email, isi TLS/SSH, dll. **diganti nol** sebelum berkas meninggalkan server |
| **Hak akses** | Berjalan sebagai user khusus `trafficrec` (tanpa login, tanpa password). Satu-satunya hak istimewa: `CAP_NET_RAW` untuk membaca paket. **Tidak berjalan sebagai root** |
| **Port masuk** | Tidak membuka port apa pun. Hanya koneksi keluar HTTPS ke Google Drive |
| **Sandbox** | Sistem berkas hanya-baca kecuali `/var/lib/traffic-recorder`; folder `/home` tidak dapat diakses |
| **Batas sumber daya** | CPU maks. 25–30%, memori maks. 256–512 MB, prioritas I/O terendah, disk maks. 2 GB, unggah maks. 1 MB/detik |
| **Batas waktu** | Berhenti otomatis setelah 14 hari |
| **Akses Google Drive** | Kunci di server hanya dapat mengakses berkas yang dibuat perekam ini (izin `drive.file`) |
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
| `bin/process_and_upload.sh` | Mengosongkan isi paket lalu mengunggah ke Google Drive |
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
sudo apt update && sudo apt install -y tcpdump python3 rclone

# AlmaLinux / Rocky / RHEL
sudo dnf install -y epel-release && sudo dnf install -y tcpdump python3 rclone
```

### Langkah 2 — Ambil folder perekam

Pilih salah satu, sesuai cara peneliti mengirimkan:

```bash
# dari GitHub
git clone https://github.com/Desa012/vps-traffic-recorder.git
cd vps-traffic-recorder

# atau dari berkas ZIP yang sudah disalin ke server
unzip vps-traffic-recorder.zip && cd vps-traffic-recorder
```

### Langkah 3 — Pasang

Berkas `rclone.conf` dikirim peneliti **secara terpisah** (tidak lewat GitHub). Salin ke server, lalu:

```bash
sudo bash install.sh /path/ke/rclone.conf
```

Hasil yang benar — semua baris diawali `[ok]`:

```
[ok] user sistem 'trafficrec' dibuat (tanpa login, tanpa password)
[ok] program dipasang di /opt/traffic-recorder (hanya root yang dapat mengubah)
[ok] konfigurasi dibuat di /etc/traffic-recorder/config.env (antarmuka terdeteksi: eth0)
[ok] rclone.conf dipasang di /var/lib/traffic-recorder/rclone.conf (hanya dapat dibaca user trafficrec)
[ok] layanan systemd dipasang (belum dijalankan)
```

Langkah ini **belum memulai perekaman**, jadi konfigurasi bisa diperiksa dulu:
`sudo nano /etc/traffic-recorder/config.env` (lihat bagian *Konfigurasi* di bawah).

Setelah dipasang, berkas `rclone.conf` salinan tadi boleh dihapus.

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
  [OK] pengolah & pengunggah aktif (setiap 15 menit)
       berhenti otomatis pada: 29 Oct 2026 13:07 UTC

2. HAK AKSES PEREKAM
  [OK] berjalan sebagai user 'trafficrec', bukan root
  [OK] hak istimewa hanya CAP_NET_RAW (membaca paket)

3. BERKAS
       sedang direkam         : 1 berkas
       siap dikirim (outbox)  : 0 berkas
       pemakaian disk         : 240K (batas 2048 MB)
  ...
5. VERIFIKASI PAYLOAD (berkas terbaru di outbox)
       belum ada berkas hasil — berkas pertama siap ±1 jam setelah perekam dimulai
```

> ⏱ **Berkas pertama baru terkirim sekitar 1 jam setelah dimulai.** Perekam menutup berkas
> setiap 1 jam, lalu pengolah memprosesnya dalam 15 menit berikutnya. Selama jam pertama,
> folder Google Drive memang masih kosong — ini normal.

Setelah ± 1,5 jam, jalankan `cek-status.sh` lagi. Bagian 4 harus menampilkan
`[OK] unggahan terakhir berhasil`.

**Selesai.** Perekam berjalan sendiri, termasuk setelah server di-restart, dan berhenti otomatis
setelah 14 hari.

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
tercatat. Bila sebuah berkas sudah terkirim (outbox kosong), pemeriksaan bisa dilakukan pada
berkas berikutnya.

Catatan: karena isinya diganti nol, *checksum* TCP/UDP pada berkas hasil tidak lagi cocok
(`cksum ... incorrect`). Ini normal dan tidak berpengaruh pada penelitian.

---

## Operasional sehari-hari

| Keperluan | Perintah |
|---|---|
| Lihat kondisi lengkap | `sudo bash /opt/traffic-recorder/bin/cek-status.sh` |
| Hentikan sementara | `sudo systemctl stop traffic-recorder.service traffic-uploader.timer` |
| Lanjutkan | `sudo systemctl start traffic-recorder.service traffic-uploader.timer` |
| Riwayat unggahan | `sudo cat /var/lib/traffic-recorder/upload_log.csv` |
| Log pengunggah | `journalctl -u traffic-uploader.service -n 30` |
| Hapus program (data tetap ada) | `sudo bash uninstall.sh` |
| **Hapus semuanya** — program, data, konfigurasi, user `trafficrec` | `sudo bash uninstall.sh --purge` |

Akses ke Google Drive peneliti dapat dicabut kapan saja dengan menghapus
`/var/lib/traffic-recorder/rclone.conf` atau menjalankan `uninstall.sh --purge`.

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
| `RCLONE_REMOTE` | `tadrive:vps-traffic` | Tujuan unggah |
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
 └──────────────────────┘   3. rclone: unggah ke Google Drive, salinan lokal dihapus
        │
        ▼
   Google Drive peneliti:  vps-traffic/cap_YYYYMMDD_HHMMSS.hdr.pcap.gz
```

**Kenapa isi paket diganti nol, bukan dipotong?** Alat ekstraksi fitur penelitian (CICFlowMeter)
menghitung ukuran paket dari byte yang ada di berkas. Bila isinya dipotong, fitur ukuran paket
menjadi salah. Dengan diganti nol: isi komunikasi hilang sepenuhnya, panjang paket tetap benar,
dan ukuran berkas tetap kecil karena deretan nol terkompres sangat baik (uji: 88 MB → 1,7 MB).

`upload_log.csv` mencatat waktu setiap unggahan dan ikut dikirim, agar lalu lintas unggahan dari
perekam ini sendiri dapat dikeluarkan dari data saat dianalisis.

| Lokasi | Isi |
|---|---|
| `/opt/traffic-recorder/` | Program (milik root) |
| `/etc/traffic-recorder/config.env` | Konfigurasi |
| `/var/lib/traffic-recorder/` | Data sementara, `rclone.conf`, catatan unggahan (izin 700, milik `trafficrec`) |
| `/etc/systemd/system/traffic-*` | Layanan systemd |

---

## Pemecahan masalah

| Gejala | Penyebab & solusi |
|---|---|
| `Permission denied` saat menjalankan `./install.sh` | Gunakan `sudo bash install.sh` (izin eksekusi bisa hilang saat berkas dikirim lewat ZIP/GitHub) |
| `antarmuka ... tidak ditemukan` | Ubah `INTERFACE` sesuai keluaran `ip -br link`, lalu restart perekam |
| `tcpdump: ... Operation not permitted` | Kernel/distribusi lama memerlukan hak tambahan. Tambahkan `CAP_NET_ADMIN` pada `AmbientCapabilities` dan `CapabilityBoundingSet` di `/etc/systemd/system/traffic-recorder.service`, lalu `sudo systemctl daemon-reload && sudo systemctl restart traffic-recorder.service` |
| Google Drive masih kosong pada jam pertama | Normal — lihat catatan ⏱ di Langkah 5 |
| Berkas menumpuk di outbox | `rclone.conf` belum dipasang atau kunci kedaluwarsa. Lihat `journalctl -u traffic-uploader.service -n 30` dan hubungi peneliti. Berkas tetap aman dan terkirim otomatis setelah diperbaiki |
| `rateLimitExceeded` di log unggah | `rclone.conf` memakai client ID bawaan rclone. Peneliti perlu membuat ulang `rclone.conf` |
| Perekam berhenti lebih cepat dari seharusnya | Jadwal berhenti lama masih tersimpan — lihat catatan di bagian *Konfigurasi* |
| Status `inactive` setelah 14 hari | Normal — masa perekaman sudah selesai |

---

## Komitmen pengelolaan data

- Data hanya digunakan untuk penelitian Tugas Akhir di atas.
- Data disimpan di Google Drive peneliti. Kunci akses yang dipasang di server memakai izin
  terbatas `drive.file`: kunci tersebut **hanya dapat mengakses berkas yang dibuat oleh perekam
  ini**, tidak dapat membuka isi Google Drive lainnya. Folder tujuan bersifat privat (tidak dibagikan).
- Data tidak dibagikan kepada pihak lain dan dihapus setelah penelitian selesai.
- Dalam naskah Tugas Akhir, alamat IP yang dapat mengidentifikasi pihak tertentu tidak dicantumkan.

**Kontak:** 087754459235 Putu Satria Arya Putra — Teknologi Informasi, Universitas Udayana.
