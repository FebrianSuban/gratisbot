# GRATISBOT

GRATISBOT adalah wizard interaktif untuk mendeploy project Laravel ke Ubuntu/Debian dengan satu perintah.

## Menjalankan

```bash
curl -fsSL https://github.com/FebrianSuban/gratisbot/raw/refs/heads/main/gratisbot.sh | sudo bash
```

Wizard kemudian akan meminta:

1. Web server: Apache atau Nginx.
2. Sumber project: GitHub public, GitLab public, atau folder local di server.
3. URL/path project, branch, domain, dan direktori deploy.
4. Konfirmasi setiap langkah deployment yang gagal.

Setelah source masuk ke server, wizard membaca project untuk mendeteksi Composer/PHP, asset NPM, dan database SQLite/MySQL. Wizard kemudian memasang dependency, menyiapkan `.env`, menjalankan migrasi Laravel, mengatur permission, dan mengaktifkan web server.

## Resume setelah error

Progress disimpan di `/var/lib/gratisbot/deploy.state`. Jika user memilih berhenti saat error, perbaiki masalahnya lalu jalankan perintah yang sama. Wizard akan menawarkan melanjutkan dari fase terakhir, bukan mengulang seluruh proses dari awal.

Jika user memilih lanjut saat error, proses deploy diteruskan dan error dicatat sebagai peringatan agar dapat diperbaiki manual setelah deploy.

## Environment Laravel

Sebelum deploy production, siapkan `.env` di:

```bash
sudo mkdir -p /var/www/NAMA_PROJECT/shared
sudo nano /var/www/NAMA_PROJECT/shared/.env
```

Jika `shared/.env` belum ada, wizard memakai `.env.example` sebagai fallback dan memberi peringatan. Pastikan `APP_KEY`, `APP_URL`, koneksi database, dan kredensial production sudah benar.

## Catatan

- Repository GitHub/GitLab yang digunakan harus public; autentikasi Git sengaja tidak digunakan.
- Target sistem saat ini Ubuntu/Debian dengan `apt-get`.
- HTTPS belum otomatis dibuat. Setelah HTTP berhasil, gunakan Certbot.
- Jangan gunakan `migrate:fresh` pada production karena dapat menghapus data.
