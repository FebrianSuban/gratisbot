# GRATISBOT

Wizard satu perintah untuk mendeploy project Laravel ke server Ubuntu/Debian. GRATISBOT menyiapkan web server, mengambil source project, membaca kebutuhan project, memasang dependency, menjalankan Laravel, dan menyimpan progress agar deployment dapat dilanjutkan setelah error.

## Fitur

- Pilihan web server: Apache atau Nginx.
- Pilihan source: GitHub public, GitLab public, atau folder local di server.
- Deteksi kebutuhan Composer/PHP, asset NPM, SQLite, dan MySQL/MariaDB.
- Clone tanpa prompt username/password untuk repository public.
- Konfigurasi web server otomatis dengan document root Laravel `public/`.
- Deployment berbasis release dan symlink `current`.
- Pilihan menghentikan atau melanjutkan proses ketika sebuah langkah gagal.
- Resume dari fase terakhir melalui state deployment.

## Persyaratan

- Server Ubuntu/Debian dengan akses `root` atau `sudo`.
- Server memiliki koneksi internet untuk memasang paket dan mengambil source.
- Repository Laravel harus memiliki `artisan`, `composer.json`, dan `public/index.php`.
- Repository GitHub/GitLab yang dipilih harus public. Autentikasi Git tidak digunakan.
- DNS domain sebaiknya sudah mengarah ke IP server sebelum konfigurasi web server dibuat.

## Instalasi Dan Menjalankan

Jalankan satu perintah berikut di server:

```bash
curl -fsSL https://github.com/FebrianSuban/gratisbot/raw/refs/heads/main/gratisbot.sh | sudo bash
```

Perintah tersebut hanya mengambil wizard lalu menjalankannya. URL project tidak ditulis di command karena akan diminta oleh wizard setelah server selesai disiapkan.

Untuk melihat bantuan tanpa menjalankan deployment:

```bash
curl -fsSL https://github.com/FebrianSuban/gratisbot/raw/refs/heads/main/gratisbot.sh | sudo bash -s -- --help
```

## Alur Wizard

### 1. Pilih Web Server

Wizard menampilkan:

```text
Pilih web server:
	1) Apache
	2) Nginx
```

Pilih `1` untuk Apache atau `2` untuk Nginx. Wizard kemudian memasang web server, PHP, ekstensi PHP, Composer, dan PHP-FPM jika Nginx dipilih.

### 2. Pilih Sumber Project

Setelah web server selesai disiapkan, wizard menampilkan:

```text
Pilih sumber project:
	1) GitHub public
	2) GitLab public
	3) Folder local di server
```

Untuk GitHub atau GitLab, masukkan URL HTTPS repository, misalnya:

```text
https://github.com/FebrianSuban/SISTEM_INFORMASI_MAHASISWA.git
```

Untuk local, masukkan path folder yang sudah ada di server, misalnya:

```text
/home/ubuntu/SISTEM_INFORMASI_MAHASISWA
```

Folder local tidak di-upload dari laptop. Folder tersebut harus sudah tersedia di server tempat wizard dijalankan.

### 3. Isi Branch, Domain, Dan Target

Untuk source GitHub/GitLab, masukkan nama branch. Tekan Enter untuk memakai `main`.

Contoh pertanyaan berikutnya:

```text
Branch [main]: main
Domain [nama-project.local]: example.com
Direktori deploy [/var/www/nama-project]: /var/www/nama-project
```

Direktori deploy wajib berada di bawah `/var/www`. Jika domain belum tersedia, gunakan hostname atau alamat domain yang akan diarahkan ke server.

### 4. Project Dianalisis

Setelah source masuk, wizard memeriksa struktur Laravel dan menampilkan kebutuhan yang ditemukan, misalnya:

```text
Kebutuhan project terdeteksi:
	- Composer/PHP
	- Node.js/NPM asset build
	- SQLite
```

Deployment dihentikan jika file penting Laravel tidak ditemukan.

### 5. Environment Dan Database

Wizard menggunakan file production berikut jika sudah dibuat:

```text
/var/www/nama-project/shared/.env
```

Siapkan file tersebut sebelum deployment jika project membutuhkan kredensial production:

```bash
sudo mkdir -p /var/www/nama-project/shared
sudo nano /var/www/nama-project/shared/.env
```

Minimal periksa nilai berikut:

```dotenv
APP_ENV=production
APP_DEBUG=false
APP_URL=https://example.com
APP_KEY=base64:isi-dengan-key-laravel
DB_CONNECTION=sqlite
```

Untuk MySQL/MariaDB, gunakan contoh seperti ini:

```dotenv
DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=nama_database
DB_USERNAME=nama_user
DB_PASSWORD=password_database
```

Jika `shared/.env` belum ada, wizard memakai `.env.example` sebagai fallback dan menampilkan peringatan. Untuk production, sebaiknya isi `shared/.env` sendiri agar secret tidak dibuat secara tidak sengaja dari konfigurasi contoh.

Jika `DB_CONNECTION=sqlite`, wizard memasang driver SQLite dan membuat:

```text
database/database.sqlite
```

Jika `DB_CONNECTION=mysql` atau `mariadb`, wizard memasang dan menyalakan MariaDB. Database dan user harus sudah sesuai dengan isi `.env` agar migrasi berhasil.

### 6. Instalasi Dan Aktivasi

Wizard menjalankan tahapan berikut secara berurutan:

1. `composer install --no-dev`.
2. `npm install` dan `npm run build` jika `package.json` ditemukan.
3. Membersihkan cache konfigurasi, route, dan view Laravel.
4. Membuat link storage.
5. Menjalankan `php artisan migrate --force`.
6. Menjalankan `php artisan optimize`.
7. Mengatur permission `storage` dan `bootstrap/cache`.
8. Mengaktifkan release baru melalui web server.

Wizard tidak menjalankan `migrate:fresh` karena perintah tersebut dapat menghapus seluruh data production.

## Penanganan Error Dan Resume

Jika sebuah tahapan gagal, wizard menampilkan:

```text
Error pada: Menjalankan konfigurasi Laravel
	1) Hentikan dan perbaiki manual
	2) Lanjutkan meskipun gagal
Pilihan [1-2]:
```

Pilih `1` jika error harus diperbaiki sebelum langkah berikutnya. Wizard menyimpan state di:

```text
/var/lib/gratisbot/deploy.state
```

Setelah memperbaiki masalah, jalankan command wizard yang sama. Wizard akan menampilkan state terakhir dan menawarkan melanjutkan. Project staging dan release yang sudah selesai dipakai kembali sehingga proses tidak harus dimulai dari clone dan instalasi awal.

Pilih `2` hanya jika memahami dampaknya. Deployment akan meneruskan proses, tetapi error tersebut tetap harus diperbaiki manual setelah aplikasi aktif.

Jika ingin membatalkan state dan memulai dari awal, jawab `n` ketika wizard bertanya apakah state ingin dilanjutkan. State lama akan dihapus.

## Struktur Direktori Deployment

Contoh struktur setelah berhasil:

```text
/var/www/nama-project/
├── current -> releases/20260909123000
├── releases/
│   ├── 20260909123000/
│   └── 20260909124500/
├── shared/
│   └── .env
└── .gratisbot-staging/
```

Web server selalu diarahkan ke:

```text
/var/www/nama-project/current/public
```

Kode aplikasi tidak diarahkan langsung ke root repository agar folder sensitif seperti `.env` tidak menjadi document root.

## Troubleshooting

### Repository tidak dapat di-clone

Pastikan URL benar dan repository public:

```bash
git ls-remote https://github.com/user/project.git
```

Repository private membutuhkan mekanisme credential yang belum didukung wizard ini.

### `could not find driver`

Periksa `DB_CONNECTION` di `shared/.env`. Wizard memasang SQLite atau MariaDB berdasarkan nilai tersebut. Jika masih gagal, periksa modul PHP:

```bash
php -m | grep -Ei 'pdo|sqlite|mysql'
```

### Migrasi database gagal

Pastikan database, username, password, dan host pada `shared/.env` benar. Untuk SQLite, pastikan file database dapat ditulis oleh `www-data`.

### Domain tidak bisa dibuka

Periksa DNS, port firewall, dan status web server:

```bash
sudo systemctl status apache2
sudo systemctl status nginx
sudo ss -tulpn | grep ':80'
```

Untuk membaca log:

```bash
sudo tail -f /var/log/apache2/nama-project-error.log
sudo journalctl -u nginx -f
```

### Membutuhkan HTTPS

HTTPS belum dibuat otomatis. Setelah domain sudah mengarah ke server dan HTTP berhasil, pasang Certbot sesuai web server yang dipilih.

## Keamanan Production

- Jangan menaruh password database di URL Git atau commit `.env` ke repository.
- Gunakan `APP_DEBUG=false` di production.
- Pastikan `APP_KEY` sudah diisi sebelum aplikasi dipakai.
- Review `.env.example` sebelum menjadikannya `.env`.
- Jangan memakai `migrate:fresh` pada server production.
- Uji deployment di staging sebelum mengarahkannya ke domain utama.

## Batasan Saat Ini

- Sistem operasi yang didukung adalah Ubuntu/Debian dengan `apt-get`.
- GitHub dan GitLab yang digunakan harus public.
- Hanya project Laravel yang didukung.
- HTTPS/Certbot belum otomatis.
- Setup database MySQL otomatis memasang MariaDB, tetapi tidak membuat database dan user berdasarkan kredensial `.env`.
