#!/usr/bin/env bash

# GRATISBOT - Laravel production deployer
# Usage: sudo ./gratisbot.sh [GitHub URL] [domain] [deploy directory]

set -Eeuo pipefail
IFS=$'\n\t'
export COMPOSER_ALLOW_SUPERUSER=1

readonly SCRIPT_NAME="GRATISBOT Laravel Deployer"
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

log() { printf '%b\n' "${CYAN}[gratisbot]${NC} $*"; }
ok() { printf '%b\n' "${GREEN}[ok]${NC} $*"; }
warn() { printf '%b\n' "${YELLOW}[peringatan]${NC} $*" >&2; }
die() { printf '%b\n' "${RED}[gagal]${NC} $*" >&2; exit 1; }

on_error() {
    local exit_code=$?
    printf '%b\n' "${RED}[gagal]${NC} Perintah gagal pada baris ${BASH_LINENO[0]}: ${BASH_COMMAND}" >&2
    printf '%b\n' "${YELLOW}[tindakan]${NC} Deployment dibatalkan. Perbaiki masalah lalu jalankan ulang; release aktif sebelumnya tidak diubah." >&2
    exit "$exit_code"
}
trap on_error ERR

usage() {
    cat <<'EOF'
Deploy Laravel dari GitHub ke Apache.

Penggunaan:
  sudo ./gratisbot.sh <github-url> [domain] [deploy-directory]

Contoh:
  sudo ./gratisbot.sh https://github.com/user/app.git example.com /var/www/app

Variabel yang dapat diatur:
    APP_ENV, AUTO_APPROVE, DEPLOY_BRANCH, PHP_VERSION

Kredensial database dan APP_KEY dibaca dari shared/.env, bukan dari argumen shell.
EOF
}

require_command() { command -v "$1" >/dev/null 2>&1 || die "Perintah '$1' tidak ditemukan."; }

clone_public_repository() {
    GIT_TERMINAL_PROMPT=0 git -c credential.helper= -c core.askPass= clone \
        --depth 1 --branch "$DEPLOY_BRANCH" "$REPO_URL" "$1" || \
        die "Repository tidak dapat diakses secara public. Pastikan URL benar dan repository GitHub bersifat public; autentikasi sengaja tidak digunakan."
}

install_host_packages() {
    local php_runtime_version
    if ! command -v apt-get >/dev/null 2>&1; then
        die "Sistem operasi ini tidak didukung. Skrip membutuhkan Ubuntu/Debian (apt-get)."
    fi
    log "Memeriksa dependensi host..."
    apt-get update -y
    apt-get install -y ca-certificates curl git unzip apache2

    if command -v php >/dev/null 2>&1; then
        php_runtime_version="$(php -r 'printf("%d.%d", PHP_MAJOR_VERSION, PHP_MINOR_VERSION);')"
    else
        php_runtime_version="$PHP_VERSION"
    fi
    log "Memasang ekstensi untuk PHP $php_runtime_version..."
    apt-get install -y "php${php_runtime_version}-cli" "php${php_runtime_version}-common" \
        "php${php_runtime_version}-mysql" "php${php_runtime_version}-xml" \
        "php${php_runtime_version}-curl" "php${php_runtime_version}-mbstring" \
        "php${php_runtime_version}-zip" "php${php_runtime_version}-bcmath" \
        "php${php_runtime_version}-intl" "php${php_runtime_version}-gd" \
        "php${php_runtime_version}-sqlite3" \
        "libapache2-mod-php${php_runtime_version}"

    if command -v phpenmod >/dev/null 2>&1; then
        phpenmod -v "$php_runtime_version" -s cli dom || true
        phpenmod -v "$php_runtime_version" -s cli xml || true
    fi
    php -r 'exit(extension_loaded("dom") ? 0 : 1);' || \
        die "Ekstensi PHP DOM belum aktif untuk PHP $php_runtime_version."
    php -r 'exit(extension_loaded("pdo_sqlite") ? 0 : 1);' || \
        die "Driver PHP PDO SQLite belum aktif untuk PHP $php_runtime_version."

    if ! command -v composer >/dev/null 2>&1; then
        curl -fsSL https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
    fi
}

validate_inputs() {
    [[ "$REPO_URL" =~ ^https://github\.com/[^/]+/[^/]+([.]git)?/?$ ]] || \
        die "URL harus berupa repository GitHub HTTPS, contoh: https://github.com/user/app.git"
    [[ "$REPO_URL" != *"/USER/REPOSITORY"* ]] || \
        die "Ganti USER/REPOSITORY dengan URL repository GitHub public yang sebenarnya."
    [[ "$DEPLOY_DIR" == /var/www/* ]] || die "Direktori deploy harus berada di bawah /var/www."
    [[ "$DEPLOY_DIR" != */ && "$DEPLOY_DIR" != /var/www ]] || die "Direktori deploy tidak valid."
    [[ "$DOMAIN" =~ ^[A-Za-z0-9.-]+$ ]] || die "Domain hanya boleh berisi huruf, angka, titik, dan tanda hubung."
}

preflight_repository() {
    log "Menjalankan preflight repository..."
    local probe_dir
    probe_dir="$(mktemp -d)"
    trap 'rm -rf "$probe_dir"' EXIT
    clone_public_repository "$probe_dir/source"
    [[ -f "$probe_dir/source/artisan" ]] || die "Repository bukan aplikasi Laravel: file artisan tidak ditemukan."
    [[ -f "$probe_dir/source/composer.json" ]] || die "composer.json tidak ditemukan."
    [[ -f "$probe_dir/source/public/index.php" ]] || die "public/index.php tidak ditemukan."
    [[ -f "$probe_dir/source/.env.example" || -f "$probe_dir/source/.env" ]] || \
        die "Repository tidak memiliki .env.example atau .env."
    composer validate --no-check-publish --working-dir="$probe_dir/source"
    composer install --no-dev --prefer-dist --no-interaction --no-progress --no-scripts \
        --working-dir="$probe_dir/source"
    php -v | head -n 1
    composer --version
    ok "Repository terdeteksi sebagai aplikasi Laravel."
    rm -rf "$probe_dir"
    trap - EXIT
}

confirm_deploy() {
    cat <<EOF

Repository : $REPO_URL
Branch     : $DEPLOY_BRANCH
Domain     : $DOMAIN
Target     : $DEPLOY_DIR
Environment: $APP_ENV

Preflight selesai. Proses berikutnya akan menginstal dependensi, mengubah konfigurasi
Apache, menjalankan migrasi database, dan mengaktifkan release baru.

Perintah utama yang akan dijalankan:
    git clone -> composer install --no-dev -> artisan config/route/view clear
    artisan storage:link -> artisan migrate --force -> artisan optimize
    chown/chmod -> konfigurasi VirtualHost -> systemctl reload apache2
EOF
    [[ "${AUTO_APPROVE:-}" == "1" ]] || {
        read -r -p "Ketik DEPLOY untuk melanjutkan: " approval < /dev/tty
        [[ "$approval" == "DEPLOY" ]] || die "Deployment dibatalkan sebelum perubahan production."
    }
}

deploy() {
    local release_dir="$DEPLOY_DIR/releases/$(date +%Y%m%d%H%M%S)"
    local current_link="$DEPLOY_DIR/current"
    local previous_target=""
    mkdir -p "$DEPLOY_DIR/releases"
    [[ -L "$current_link" ]] && previous_target="$(readlink -f "$current_link")"

    log "Meng-clone release baru..."
    clone_public_repository "$release_dir"
    cd "$release_dir"

    if [[ -f "$DEPLOY_DIR/shared/.env" ]]; then
        cp "$DEPLOY_DIR/shared/.env" .env
    elif [[ -f ".env.example" ]]; then
        cp .env.example .env
        warn "File .env baru dibuat dari .env.example. Pastikan kredensial production benar."
    else
        die "Konfigurasi .env tidak tersedia. Buat $DEPLOY_DIR/shared/.env lalu jalankan ulang."
    fi

    local db_connection
    db_connection="$(sed -n 's/^DB_CONNECTION=//p' .env | head -n 1 | tr -d '\"' | tr -d "'")"
    if [[ "$db_connection" == "sqlite" ]]; then
        mkdir -p database
        touch database/database.sqlite
        log "Database SQLite disiapkan di database/database.sqlite."
    fi

    composer install --no-dev --prefer-dist --no-interaction --optimize-autoloader
    php artisan config:clear
    php artisan route:clear
    php artisan view:clear
    php artisan storage:link 2>/dev/null || true
    php artisan migrate --force
    php artisan optimize

    chown -R www-data:www-data "$release_dir"
    chmod -R u=rwX,g=rX,o=rX "$release_dir"
    chmod -R ug+rwX "$release_dir/storage" "$release_dir/bootstrap/cache"

    ln -sfn "$release_dir" "$current_link"
    configure_apache
    systemctl reload apache2
    ok "Release baru aktif: $release_dir"

    find "$DEPLOY_DIR/releases" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' \
        | sort -nr | tail -n +4 | cut -d' ' -f2- | xargs -r rm -rf
    [[ -z "$previous_target" ]] || log "Release sebelumnya tetap tersedia untuk rollback: $previous_target"
}

configure_apache() {
    local vhost="/etc/apache2/sites-available/${APP_SLUG}.conf"
    cat > "$vhost" <<EOF
<VirtualHost *:80>
    ServerName $DOMAIN
    DocumentRoot $DEPLOY_DIR/current/public

    <Directory $DEPLOY_DIR/current/public>
        AllowOverride All
        Require all granted
        Options -Indexes +FollowSymLinks
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/${APP_SLUG}-error.log
    CustomLog \${APACHE_LOG_DIR}/${APP_SLUG}-access.log combined
</VirtualHost>
EOF
    a2enmod rewrite headers >/dev/null
    a2ensite "${APP_SLUG}.conf" >/dev/null
}

[[ "${1:-}" == "--help" ]] && { usage; exit 0; }
[[ $EUID -eq 0 ]] || die "Jalankan dengan sudo: sudo $0 <github-url> [domain] [deploy-directory]"

REPO_URL="${1:-}"
[[ -n "$REPO_URL" ]] || { usage; exit 1; }
REPO_NAME="$(basename "${REPO_URL%/}" .git)"
DOMAIN="${2:-$REPO_NAME.local}"
DEPLOY_DIR="${3:-/var/www/$REPO_NAME}"
APP_SLUG="$(printf '%s' "$REPO_NAME" | tr -cd 'A-Za-z0-9_-')"
DEPLOY_BRANCH="${DEPLOY_BRANCH:-main}"
PHP_VERSION="${PHP_VERSION:-8.2}"
APP_ENV="${APP_ENV:-production}"

printf '%b\n' "${CYAN}=== $SCRIPT_NAME ===${NC}"
validate_inputs
install_host_packages
require_command php
require_command composer
    php -m | grep -qx 'dom' || die "Ekstensi PHP DOM belum aktif setelah instalasi php-xml."
preflight_repository
confirm_deploy
deploy

printf '%b\n' "${GREEN}Deployment Laravel selesai.${NC}"
printf 'URL: http://%s\n' "$DOMAIN"
