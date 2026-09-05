#!/bin/bash

# ==============================================================================
# GRATISBOT v2.0 - Universal Automated Deployment for Killercoda / Ubuntu
# Supports: Laravel, Standard PHP, Node.js (Express/Nest), Python, Static HTML
# ==============================================================================

set -e # Hentikan eksekusi jika terjadi error fatal

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}====================================================${NC}"
echo -e "${CYAN}     GRATISBOT: UNIVERSAL ONE-CLICK DEPLOYMENT      ${NC}"
echo -e "${CYAN}====================================================${NC}"

# ------------------------------------------------------------------------------
# 1. SETUP LINGKUNGAN SERVER DASAR (SYSTEM PREPARATION)
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}[1/6] Menyiapkan Paket Dasar Sistem & Web Server...${NC}"

# Hindari interaksi prompt saat instalasi paket sistem
export DEBIAN_FRONTEND=noninteractive

sudo apt-get update -y
sudo apt-get install -y curl wget git unzip software-properties-common ufw \
                        apache2 libapache2-mod-fcgid mariadb-server mariadb-client

# Konfigurasi Git Safe Directory untuk mencegah error 'dubious ownership'
git config --global --add safe.directory "*"

# Enable modul Apache dasar
sudo a2enmod rewrite headers proxy proxy_http

# ------------------------------------------------------------------------------
# 2. INPUT & KLONING REPOSITORI
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}[2/6] Mengambil Repositori GitHub...${NC}"
read -p "Masukkan URL Repository GitHub: " REPO_URL < /dev/tty

if [ -z "$REPO_URL" ]; then
    echo -e "${RED}Error: URL Repository tidak boleh kosong!${NC}"
    exit 1
fi

REPO_NAME=$(basename "$REPO_URL" .git)
TARGET_DIR="/var/www/$REPO_NAME"

# Bersihkan direktori jika sudah pernah di-deploy sebelumnya
if [ -d "$TARGET_DIR" ]; then
    echo -e "${YELLOW}Membersihkan direktori lama di $TARGET_DIR...${NC}"
    sudo rm -rf "$TARGET_DIR"
fi

echo -e "${GREEN}Kloning repositori ke $TARGET_DIR...${NC}"
sudo git clone "$REPO_URL" "$TARGET_DIR"
cd "$TARGET_DIR"

# ------------------------------------------------------------------------------
# 3. DETEKSI OTOMATIS TEKNOLOGI PROYEK
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}[3/6] Menganalisis Struktur Proyek...${NC}"

PROJECT_TYPE="UNKNOWN"

if [ -f "artisan" ]; then
    PROJECT_TYPE="LARAVEL"
elif [ -f "composer.json" ] || [ -f "index.php" ]; then
    PROJECT_TYPE="PHP"
elif [ -f "package.json" ]; then
    PROJECT_TYPE="NODE"
elif [ -f "requirements.txt" ] || [ -f "manage.py" ] || [ -f "app.py" ]; then
    PROJECT_TYPE="PYTHON"
elif [ -f "index.html" ]; then
    PROJECT_TYPE="STATIC"
fi

echo -e "${CYAN}Tipe Proyek Terdeteksi: [ $PROJECT_TYPE ]${NC}"

# ------------------------------------------------------------------------------
# 4. INSTALASI RUNTIME BERDASARKAN DETEKSI
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}[4/6] Menginstal Runtime & Dependency yang Sesuai...${NC}"

case $PROJECT_TYPE in
    LARAVEL)
        echo -e "${YELLOW}Menyiapkan PPA Ondrej & PHP 7.4 (Kompatibilitas Laravel 8/9)...${NC}"
        sudo add-apt-repository -y ppa:ondrej/php
        sudo apt-get update -y
        sudo apt-get install -y php7.4 php7.4-cli php7.4-common php7.4-mysql php7.4-xml \
                                php7.4-curl php7.4-mbstring php7.4-zip php7.4-gd \
                                libapache2-mod-php7.4 composer
        
        sudo a2dismod php8.* 2>/dev/null || true
        sudo a2enmod php7.4
        
        # Install Node.js untuk kompilasi Mix/Vite jika ada
        if [ -f "package.json" ]; then
            sudo apt-get install -y nodejs npm
        fi
        ;;

    PHP)
        echo -e "${YELLOW}Menginstal PHP Native & Composer...${NC}"
        sudo apt-get install -y php php-cli php-mysql php-xml php-curl php-mbstring php-zip composer libapache2-mod-php
        ;;

    NODE)
        echo -e "${YELLOW}Menginstal Node.js Runtime & PM2 Process Manager...${NC}"
        sudo apt-get install -y nodejs npm
        sudo npm install -g pm2
        ;;

    PYTHON)
        echo -e "${YELLOW}Menginstal Python3, Pip, dan Virtual environment...${NC}"
        sudo apt-get install -y python3 python3-pip python3-venv
        ;;

    STATIC)
        echo -e "${GREEN}Tidak memerlukan runtime tambahan untuk file statis.${NC}"
        ;;
esac

# ------------------------------------------------------------------------------
# 5. OTOMATISASI DATABASE (MARIADB)
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}[5/6] Mengonfigurasi Layanan Database...${NC}"

sudo systemctl start mariadb

# Buat User Dedicated untuk mengatasi hambatan unix_socket root
sudo mysql -e "CREATE USER IF NOT EXISTS 'gratisbot'@'localhost' IDENTIFIED BY 'gratisbot123';"
sudo mysql -e "GRANT ALL PRIVILEGES ON *.* TO 'gratisbot'@'localhost' WITH GRANT OPTION;"
sudo mysql -e "FLUSH PRIVILEGES;"

# Cari apakah ada file .sql bawaan di dalam repositori
SQL_FILE=$(find . -maxdepth 2 -name "*.sql" | head -n 1)

read -p "Apakah proyek ini membutuhkan Database MySQL/MariaDB? (y/n): " NEED_DB < /dev/tty

if [[ "$NEED_DB" =~ ^[Yy]$ ]]; then
    read -p "Masukkan Nama Database: " DB_NAME < /dev/tty
    if [ -z "$DB_NAME" ]; then DB_NAME="$REPO_NAME"; fi

    sudo mysql -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;"
    echo -e "${GREEN}Database '$DB_NAME' siap digunakan!${NC}"

    # Impor otomatis file .sql jika ditemukan
    if [ -n "$SQL_FILE" ]; then
        echo -e "${YELLOW}Mengimpor file database bawaan ($SQL_FILE)...${NC}"
        sudo mysql "$DB_NAME" < "$SQL_FILE"
        echo -e "${GREEN}Impor database selesai!${NC}"
    fi
fi

# ------------------------------------------------------------------------------
# 6. SETUP SPESIFIK FRAMEWORK & RUNTIME
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}[6/6] Menjalankan Build & Finalisasi Konfigurasi...${NC}"

case $PROJECT_TYPE in
    LARAVEL)
        # 1. Handling .env
        [ ! -f ".env" ] && ([ -f ".env.example" ] && cp .env.example .env || touch .env)

        # 2. Fix HTTPS Mixed Content (Reverse Proxy Killercoda) & DB Connection
        sed -i 's|APP_URL=.*|APP_URL=|' .env
        grep -q "^ASSET_URL=" .env && sed -i 's|ASSET_URL=.*|ASSET_URL=.|' .env || echo "ASSET_URL=." >> .env
        
        if [ -n "$DB_NAME" ]; then
            sed -i "s/DB_HOST=.*/DB_HOST=127.0.0.1/" .env
            sed -i "s/DB_DATABASE=.*/DB_DATABASE=$DB_NAME/" .env
            sed -i "s/DB_USERNAME=.*/DB_USERNAME=gratisbot/" .env
            sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=gratisbot123/" .env
        fi

        # 3. Dependencies, Encryption Key, & Permissions
        composer install --no-interaction --prefer-dist --optimize-autoloader
        php7.4 artisan key:generate --force
        php7.4 artisan storage:link --force 2>/dev/null || true
        sudo chmod -R 777 storage bootstrap/cache

        # 4. Run Migration jika tidak ada file SQL
        if [ -z "$SQL_FILE" ] && [ -n "$DB_NAME" ]; then
            php7.4 artisan migrate:fresh --seed --force
        fi

        # 5. Build Assets (JS/CSS)
        if [ -f "package.json" ]; then
            npm install
            npm run prod 2>/dev/null || npm run build 2>/dev/null || npm run dev 2>/dev/null || true
        fi

        php7.4 artisan config:clear
        php7.4 artisan view:clear
        
        DOC_ROOT="$TARGET_DIR/public"
        ;;

    PHP)
        if [ -f "composer.json" ]; then
            composer install --no-interaction
        fi
        
        # Konfigurasi database umum jika file .env ada
        if [ -f ".env" ] && [ -n "$DB_NAME" ]; then
            sed -i "s/DB_HOST=.*/DB_HOST=127.0.0.1/" .env
            sed -i "s/DB_NAME=.*/DB_NAME=$DB_NAME/" .env
            sed -i "s/DB_USER=.*/DB_USER=gratisbot/" .env
            sed -i "s/DB_PASS=.*/DB_PASS=gratisbot123/" .env
        fi
        
        DOC_ROOT="$TARGET_DIR"
        ;;

    NODE)
        npm install
        
        # Jalankan aplikasi menggunakan PM2 di background pada port 3000
        pm2 stop "$REPO_NAME" 2>/dev/null || true
        pm2 start npm --name "$REPO_NAME" -- start || pm2 start index.js --name "$REPO_NAME"
        pm2 save
        
        DOC_ROOT="$TARGET_DIR"
        ;;

    PYTHON)
        python3 -m venv venv
        source venv/bin/activate
        if [ -f "requirements.txt" ]; then
            pip install -r requirements.txt
        fi
        
        DOC_ROOT="$TARGET_DIR"
        ;;

    STATIC)
        DOC_ROOT="$TARGET_DIR"
        ;;
esac

# ------------------------------------------------------------------------------
# 7. KONFIGURASI APACHE VIRTUALHOST & PROXY
# ------------------------------------------------------------------------------
VHOST_CONF="/etc/apache2/sites-available/$REPO_NAME.conf"

if [ "$PROJECT_TYPE" == "NODE" ]; then
    # Proxy Pass ke Node.js App (Port 3000)
    sudo bash -c "cat <<EOF > $VHOST_CONF
<VirtualHost *:80>
    ServerName localhost
    ProxyRequests Off
    ProxyPreserveHost On
    ProxyVia Full
    <Proxy *>
        Require all granted
    </Proxy>
    ProxyPass / http://127.0.0.1:3000/
    ProxyPassReverse / http://127.0.0.1:3000/
</VirtualHost>
EOF"
else
    # Standar VirtualHost Apache untuk PHP/Laravel/Statis
    sudo bash -c "cat <<EOF > $VHOST_CONF
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot $DOC_ROOT

    <Directory $DOC_ROOT>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF"
fi

# Aktifkan Site Baru & Restart Apache
sudo a2dissite 000-default.conf 2>/dev/null || true
sudo a2ensite "$REPO_NAME.conf"
sudo systemctl restart apache2

# ------------------------------------------------------------------------------
# RINGKASAN HASIL DEPLOYMENT
# ------------------------------------------------------------------------------
echo -e "\n${GREEN}====================================================${NC}"
echo -e "${GREEN}      DEPLOYMENT BERHASIL! APLIKASI SIAP DEMO       ${NC}"
echo -e "${GREEN}====================================================${NC}"
echo -e "Tipe Proyek : ${CYAN}$PROJECT_TYPE${NC}"
echo -e "Direktori   : ${CYAN}$TARGET_DIR${NC}"
echo -e "Port Publik : ${CYAN}80${NC}"
echo -e "\nLangkah Akses di Killercoda:"
echo -e "1. Klik tombol ${YELLOW}'Traffic / Ports'${NC} pada panel atas Killercoda."
echo -e "2. Ketikkan nomor Port: ${YELLOW}80${NC}"
echo -e "3. Klik ${GREEN}'Access'${NC} untuk melihat aplikasi publik kamu."