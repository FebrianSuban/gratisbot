# GRATISBOT

GRATISBOT adalah deployer satu perintah untuk aplikasi Laravel dari repository GitHub ke Ubuntu/Debian dengan Apache dan PHP production.

## Penggunaan

```bash
curl -fsSL https://raw.githubusercontent.com/FebrianSuban/gratisbot/main/gratisbot.sh | sudo bash -s -- https://github.com/FebrianSuban/SISTEM_INFORMASI_MAHASISWA.git example.com /var/www/SISTEM_INFORMASI_MAHASISWA
```

Skrip akan:

- memvalidasi URL, branch, hak akses, dan struktur Laravel sebelum deploy;
- melakukan clone GitHub public tanpa meminta username atau password;
- memeriksa atau memasang Git, PHP, Composer, Apache, dan ekstensi PHP;
- meng-clone repository GitHub ke release baru;
- memakai `.env` dari `/var/www/REPOSITORY/shared/.env` jika tersedia;
- menjalankan `composer install`, cache Laravel, `migrate --force`, dan `optimize`;
- mengaktifkan Apache ke `public/` melalui symlink `current`;
- mempertahankan release lama sehingga kegagalan tidak mengganti release aktif.

Skrip selalu meminta konfirmasi `DEPLOY` sebelum mengubah production. Untuk otomatisasi terkontrol, gunakan `AUTO_APPROVE=1`.

## Konfigurasi production

Sebelum menjalankan deploy pertama, siapkan file environment:

```bash
sudo mkdir -p /var/www/REPOSITORY/shared
sudo nano /var/www/REPOSITORY/shared/.env
```

Isi minimalnya dari `.env.example`, termasuk `APP_KEY`, `APP_URL`, dan kredensial database. Jangan commit `.env` atau menaruh password database di command line.

Branch, versi PHP, dan mode konfirmasi dapat diatur melalui environment. Kredensial
database serta `APP_KEY` tetap dibaca dari `shared/.env`:

```bash
sudo DEPLOY_BRANCH=main PHP_VERSION=8.2 AUTO_APPROVE=1 bash /tmp/gratisbot.sh https://github.com/FebrianSuban/SISTEM_INFORMASI_MAHASISWA.git example.com /var/www/SISTEM_INFORMASI_MAHASISWA
```

## Catatan

- Target saat ini Ubuntu/Debian dengan `apt-get`, Apache, dan PHP.
- DNS domain harus sudah menunjuk ke server. HTTPS belum otomatis dibuat; gunakan Certbot setelah HTTP berhasil.
- Perintah `migrate:fresh` sengaja tidak digunakan karena dapat menghapus seluruh data production.
