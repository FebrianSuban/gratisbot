#!/usr/bin/env bash

# GRATISBOT - interactive Laravel deployment wizard
set -Eeuo pipefail
IFS=$'\n\t'
export COMPOSER_ALLOW_SUPERUSER=1

readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'
readonly STATE_DIR=/var/lib/gratisbot
readonly STATE_FILE=$STATE_DIR/deploy.state

log() { printf '%b\n' "${CYAN}[gratisbot]${NC} $*"; }
ok() { printf '%b\n' "${GREEN}[ok]${NC} $*"; }
warn() { printf '%b\n' "${YELLOW}[peringatan]${NC} $*" >&2; }
die() { printf '%b\n' "${RED}[gagal]${NC} $*" >&2; exit 1; }
require_command() { command -v "$1" >/dev/null 2>&1 || die "Perintah '$1' tidak ditemukan."; }

usage() {
    cat <<'EOF'
Wizard deploy Laravel ke Apache atau Nginx.

Jalankan:
  sudo bash gratisbot.sh

Sumber project yang tersedia: GitHub public, GitLab public, atau folder local.
State deploy disimpan di /var/lib/gratisbot/deploy.state agar proses dapat dilanjutkan.
EOF
}

save_state() {
    mkdir -p "$STATE_DIR"
    umask 077
    cat > "$STATE_FILE" <<EOF
WEB_SERVER=$(printf '%q' "$WEB_SERVER")
SOURCE_TYPE=$(printf '%q' "$SOURCE_TYPE")
SOURCE_VALUE=$(printf '%q' "$SOURCE_VALUE")
DEPLOY_BRANCH=$(printf '%q' "$DEPLOY_BRANCH")
DOMAIN=$(printf '%q' "$DOMAIN")
DEPLOY_DIR=$(printf '%q' "$DEPLOY_DIR")
APP_SLUG=$(printf '%q' "$APP_SLUG")
STAGING_DIR=$(printf '%q' "$STAGING_DIR")
RELEASE_DIR=$(printf '%q' "$RELEASE_DIR")
PHASE=$(printf '%q' "$PHASE")
EOF
}

load_state() {
    [[ -f "$STATE_FILE" ]] || return 1
    # State hanya dibuat sendiri oleh save_state dan berisi nilai shell-quoted.
    # shellcheck disable=SC1090
    source "$STATE_FILE"
}

ask() {
    local answer
    read -r -p "$1" answer < /dev/tty
    printf '%s' "$answer"
}

choose_server() {
    local choice
    printf '\nPilih web server:\n  1) Apache\n  2) Nginx\n'
    choice="$(ask 'Pilihan [1-2]: ')"
    case "$choice" in
        1) WEB_SERVER=apache ;;
        2) WEB_SERVER=nginx ;;
        *) warn 'Pilihan tidak dikenal.'; choose_server ;;
    esac
}

choose_source() {
    local choice
    printf '\nPilih sumber project:\n  1) GitHub public\n  2) GitLab public\n  3) Folder local di server\n'
    choice="$(ask 'Pilihan [1-3]: ')"
    case "$choice" in
        1) SOURCE_TYPE=github; SOURCE_VALUE="$(ask 'URL GitHub public: ')" ;;
        2) SOURCE_TYPE=gitlab; SOURCE_VALUE="$(ask 'URL GitLab public: ')" ;;
        3) SOURCE_TYPE=local; SOURCE_VALUE="$(ask 'Path folder project di server: ')" ;;
        *) warn 'Pilihan tidak dikenal.'; choose_source ;;
    esac
}

configure_project_target() {
    local default_name
    default_name="$(basename "${SOURCE_VALUE%/}" .git | tr -cd 'A-Za-z0-9_-')"
    [[ -n "$default_name" ]] || default_name=laravel-app
    DEPLOY_BRANCH=main
    if [[ "$SOURCE_TYPE" != local ]]; then
        DEPLOY_BRANCH="$(ask "Branch [main]: ")"
        [[ -n "$DEPLOY_BRANCH" ]] || DEPLOY_BRANCH=main
    fi
    DOMAIN="$(ask "Domain [${default_name}.local]: ")"
    [[ -n "$DOMAIN" ]] || DOMAIN="${default_name}.local"
    DEPLOY_DIR="$(ask "Direktori deploy [/var/www/$default_name]: ")"
    [[ -n "$DEPLOY_DIR" ]] || DEPLOY_DIR="/var/www/$default_name"
    APP_SLUG="$default_name"
}

validate_choices() {
    [[ "$WEB_SERVER" == apache || "$WEB_SERVER" == nginx ]] || die 'Web server tidak valid.'
    [[ "$DEPLOY_DIR" == /var/www/* && "$DEPLOY_DIR" != */ ]] || die 'Direktori deploy harus berada di bawah /var/www.'
    [[ "$DOMAIN" =~ ^[A-Za-z0-9.-]+$ ]] || die 'Domain tidak valid.'
    if [[ "$SOURCE_TYPE" == github ]]; then
        [[ "$SOURCE_VALUE" =~ ^https://github\.com/[^/]+/[^/]+([.]git)?/?$ ]] || die 'URL GitHub public tidak valid.'
    elif [[ "$SOURCE_TYPE" == gitlab ]]; then
        [[ "$SOURCE_VALUE" =~ ^https://gitlab\.com/[^/]+/[^/]+([.]git)?/?$ ]] || die 'URL GitLab public tidak valid.'
    else
        [[ -d "$SOURCE_VALUE" ]] || die "Folder local tidak ditemukan: $SOURCE_VALUE"
    fi
}

install_php_stack() {
    local php_version
    if command -v php >/dev/null 2>&1; then
        php_version="$(php -r 'printf("%d.%d", PHP_MAJOR_VERSION, PHP_MINOR_VERSION);')"
    else
        php_version=8.3
    fi
    log "Memasang PHP $php_version dan ekstensi project..."
    apt-get install -y "php${php_version}-cli" "php${php_version}-common" \
        "php${php_version}-mysql" "php${php_version}-sqlite3" \
        "php${php_version}-xml" "php${php_version}-curl" \
        "php${php_version}-mbstring" "php${php_version}-zip" \
        "php${php_version}-bcmath" "php${php_version}-intl" \
        "php${php_version}-gd" "libapache2-mod-php${php_version}"
    phpenmod -v "$php_version" -s cli dom xml sqlite3 pdo_sqlite 2>/dev/null || true
    php -r 'exit(extension_loaded("dom") && extension_loaded("pdo_sqlite") ? 0 : 1);' || \
        die "Ekstensi DOM atau PDO SQLite PHP belum aktif."
    if ! command -v composer >/dev/null 2>&1; then
        curl -fsSL https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
    fi
    require_command composer
}

setup_server() {
    log "Menyiapkan $WEB_SERVER..."
    apt-get update -y
    apt-get install -y ca-certificates curl git unzip "$WEB_SERVER"
    install_php_stack
    if [[ "$WEB_SERVER" == nginx ]]; then
        local php_version
        php_version="$(php -r 'printf("%d.%d", PHP_MAJOR_VERSION, PHP_MINOR_VERSION);')"
        apt-get install -y "php${php_version}-fpm"
        systemctl enable --now "php${php_version}-fpm"
    else
        a2enmod rewrite headers >/dev/null
    fi
}

clone_public() {
    local url="$1" target="$2"
    GIT_TERMINAL_PROMPT=0 git -c credential.helper= -c core.askPass= clone \
        --depth 1 --branch "$DEPLOY_BRANCH" "$url" "$target"
}

prepare_project() {
    rm -rf "$STAGING_DIR"
    mkdir -p "$(dirname "$STAGING_DIR")"
    if [[ "$SOURCE_TYPE" == local ]]; then
        cp -a "$SOURCE_VALUE/." "$STAGING_DIR/"
    else
        clone_public "$SOURCE_VALUE" "$STAGING_DIR"
    fi
    [[ -f "$STAGING_DIR/artisan" && -f "$STAGING_DIR/composer.json" && -f "$STAGING_DIR/public/index.php" ]] || \
        die 'Project bukan aplikasi Laravel lengkap: artisan, composer.json, atau public/index.php tidak ditemukan.'
    ok 'Project berhasil dimasukkan ke server.'
}

analyze_project() {
    local requirements=()
    [[ -f "$STAGING_DIR/composer.json" ]] && requirements+=("Composer/PHP")
    [[ -f "$STAGING_DIR/package.json" ]] && requirements+=("Node.js/NPM asset build")
    grep -qE '^DB_CONNECTION=(mysql|mariadb)' "$STAGING_DIR/.env.example" 2>/dev/null && requirements+=("MySQL/MariaDB")
    grep -qE '^DB_CONNECTION=sqlite' "$STAGING_DIR/.env.example" 2>/dev/null && requirements+=("SQLite")
    [[ -f "$STAGING_DIR/.env.example" ]] || requirements+=(".env manual")
    printf '\nKebutuhan project terdeteksi:\n'
    printf '  - %s\n' "${requirements[@]:-Laravel/PHP}"
    printf '\n'
}

copy_environment() {
    mkdir -p "$DEPLOY_DIR/shared"
    if [[ -f "$DEPLOY_DIR/shared/.env" ]]; then
        cp "$DEPLOY_DIR/shared/.env" "$RELEASE_DIR/.env"
    elif [[ -f "$RELEASE_DIR/.env.example" ]]; then
        cp "$RELEASE_DIR/.env.example" "$RELEASE_DIR/.env"
        warn 'shared/.env belum ada; .env dibuat dari .env.example. Isi kredensial production sebelum lanjut.'
    else
        die 'File environment tidak ditemukan.'
    fi
    local db_connection
    db_connection="$(sed -n 's/^DB_CONNECTION=//p' "$RELEASE_DIR/.env" | head -n 1 | tr -d '\"' | tr -d "'")"
    if [[ "$db_connection" == sqlite ]]; then
        mkdir -p "$RELEASE_DIR/database"
        touch "$RELEASE_DIR/database/database.sqlite"
    elif [[ "$db_connection" == mysql || "$db_connection" == mariadb ]]; then
        log 'Project memakai MySQL/MariaDB; memasang database server...'
        apt-get install -y mariadb-server mariadb-client
        systemctl enable --now mariadb
    fi
}

configure_apache() {
    cat > "/etc/apache2/sites-available/$APP_SLUG.conf" <<EOF
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
    a2ensite "$APP_SLUG.conf" >/dev/null
    a2dissite 000-default.conf >/dev/null 2>&1 || true
    systemctl reload apache2
}

configure_nginx() {
    local php_version socket
    php_version="$(php -r 'printf("%d.%d", PHP_MAJOR_VERSION, PHP_MINOR_VERSION);')"
    socket="/run/php/php${php_version}-fpm.sock"
    cat > "/etc/nginx/sites-available/$APP_SLUG" <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    root $DEPLOY_DIR/current/public;
    index index.php index.html;
    location / { try_files \$uri \$uri/ /index.php?\$query_string; }
    location ~ \\.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:$socket;
    }
    location ~ /\\. { deny all; }
}
EOF
    ln -sfn "/etc/nginx/sites-available/$APP_SLUG" "/etc/nginx/sites-enabled/$APP_SLUG"
    rm -f /etc/nginx/sites-enabled/default
    nginx -t
    systemctl reload nginx
}

install_composer_dependencies() {
    local project_dir="$1"
    if composer install --no-dev --prefer-dist --no-interaction --optimize-autoloader \
        --working-dir="$project_dir"; then
        return 0
    fi

    warn 'composer.lock tidak kompatibel dengan PHP atau dependency server saat ini.'
    warn 'Mencari versi dependency terbaru yang kompatibel dan memperbarui composer.lock.'
    composer update --no-dev --with-all-dependencies --prefer-dist --no-interaction \
        --working-dir="$project_dir"
    composer install --no-dev --prefer-dist --no-interaction --optimize-autoloader \
        --working-dir="$project_dir"
}

run_step() {
    local label="$1"; shift
    while true; do
        log "$label"
        if "$@"; then
            ok "$label selesai."
            return 0
        fi
        warn "Error pada: $label"
        printf '  1) Hentikan dan perbaiki manual\n  2) Lanjutkan meskipun gagal\n'
        case "$(ask 'Pilihan [1-2]: ')" in
            1) save_state; die 'Deployment dihentikan. Jalankan ulang untuk melanjutkan dari state terakhir.' ;;
            2) warn "Melanjutkan setelah error pada $label."; return 0 ;;
            *) warn 'Pilihan tidak valid.' ;;
        esac
    done
}

deploy_steps() {
    mkdir -p "$DEPLOY_DIR/releases"
    if [[ "$PHASE" == source || ! -d "$STAGING_DIR" ]]; then
        run_step 'Memasukkan project ke server' prepare_project
        PHASE=analyze; save_state
    fi
    if [[ "$PHASE" == analyze ]]; then
        run_step 'Menganalisis project' analyze_project
        RELEASE_DIR="$DEPLOY_DIR/releases/$(date +%Y%m%d%H%M%S)"
        mkdir -p "$RELEASE_DIR"
        cp -a "$STAGING_DIR/." "$RELEASE_DIR/"
        PHASE=environment; save_state
    fi
    if [[ "$PHASE" == environment ]]; then
        run_step 'Menyiapkan environment dan database' copy_environment
        PHASE=dependencies; save_state
    fi
    if [[ "$PHASE" == dependencies ]]; then
        run_step 'Menginstal dependency Composer' install_composer_dependencies "$RELEASE_DIR"
        if [[ -f "$RELEASE_DIR/package.json" ]]; then
            apt-get install -y nodejs npm
            run_step 'Membangun asset frontend' bash -c 'cd "$1" && npm install && npm run build' _ "$RELEASE_DIR"
        fi
        PHASE=artisan; save_state
    fi
    if [[ "$PHASE" == artisan ]]; then
        run_step 'Menjalankan konfigurasi Laravel' bash -c 'cd "$1" && php artisan config:clear && php artisan route:clear && php artisan view:clear && php artisan storage:link && php artisan migrate --force && php artisan optimize' _ "$RELEASE_DIR"
        PHASE=permissions; save_state
    fi
    if [[ "$PHASE" == permissions ]]; then
        run_step 'Mengatur permission release' bash -c 'chown -R www-data:www-data "$1" && chmod -R u=rwX,g=rX,o=rX "$1" && chmod -R ug+rwX "$1/storage" "$1/bootstrap/cache"' _ "$RELEASE_DIR"
        PHASE=server; save_state
    fi
    if [[ "$PHASE" == server ]]; then
        ln -sfn "$RELEASE_DIR" "$DEPLOY_DIR/current"
        if [[ "$WEB_SERVER" == apache ]]; then run_step 'Mengaktifkan konfigurasi Apache' configure_apache; else run_step 'Mengaktifkan konfigurasi Nginx' configure_nginx; fi
        PHASE=done; save_state
    fi
}

resume_or_start() {
    if [[ -f "$STATE_FILE" ]]; then
        load_state
        printf '\nState deployment ditemukan:\n  Project: %s\n  Server : %s\n  Fase   : %s\n' "$SOURCE_VALUE" "$WEB_SERVER" "$PHASE"
        case "$(ask 'Lanjutkan state ini? [y/n]: ')" in
            y|Y) return 0 ;;
            *) rm -f "$STATE_FILE" ;;
        esac
    fi
    choose_server
    SOURCE_TYPE=unset
    SOURCE_VALUE=unset
    DEPLOY_BRANCH=main
    DOMAIN=unset
    DEPLOY_DIR=unset
    APP_SLUG=unset
    STAGING_DIR=unset
    RELEASE_DIR=''
    PHASE=server
    save_state
}

select_source_after_server() {
    choose_source
    configure_project_target
    validate_choices
    STAGING_DIR="$DEPLOY_DIR/.gratisbot-staging"
    PHASE=source
    save_state
}

[[ "${1:-}" == --help ]] && { usage; exit 0; }
[[ $EUID -eq 0 ]] || die 'Jalankan dengan sudo.'

printf '%b\n' "${CYAN}=== GRATISBOT Laravel Deployment Wizard ===${NC}"
resume_or_start
if [[ "$PHASE" == server ]]; then
    run_step 'Menyiapkan web server dan PHP' setup_server
    select_source_after_server
fi
printf '\nServer: %s | Sumber: %s | Target: %s\n' "$WEB_SERVER" "$SOURCE_TYPE" "$DEPLOY_DIR"
deploy_steps
rm -f "$STATE_FILE"
ok "Deployment Laravel selesai: http://$DOMAIN"
