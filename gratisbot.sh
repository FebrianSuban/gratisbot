#!/bin/bash

# ==========================================
# GRATISBOT - Auto Deployer untuk Demo Tugas
# ==========================================

# Warna Terminal
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

clear
echo -e "${BLUE}====================================================${NC}"
echo -e "${GREEN}    GRATISBOT: Automated Student App Deployment    ${NC}"
echo -e "${BLUE}====================================================${NC}"
echo ""

# 1. Input Repository GitHub (Menggunakan /dev/tty agar aman dijalankan via pipe curl)
read -p "Masukkan Link Repository GitHub Proyek Kamu: " REPO_URL < /dev/tty

if [ -z "$REPO_URL" ]; then
    echo -e "${RED}[ERROR] URL Repository tidak boleh kosong!${NC}"
    exit 1
fi

# Ambil nama folder dari URL git
REPO_NAME=$(basename "$REPO_URL" .git)
TARGET_DIR="/var/www/$REPO_NAME"

echo -e "\n${YELLOW}[1/4] Mengkloning Repository dari GitHub...${NC}"
sudo mkdir -p /var/www
sudo git clone "$REPO_URL" "$TARGET_DIR"

if [ $? -ne 0 ]; then
    echo -e "${RED}[ERROR] Gagal melakukan git clone. Pastikan URL benar atau repository bersifat PUBLIC.${NC}"
    exit 1
fi

cd "$TARGET_DIR" || exit

echo -e "\n${YELLOW}[2/4] Menganalisis Teknologi Proyek...${NC}"

PORT=80

# 2. Deteksi Otomatis Stack Teknologi

# PRIORITAS 1: Cek apakah ini Laravel / CodeIgniter / PHP Native
if [ -f "artisan" ] || [ -f "composer.json" ] || ls *.php &>/dev/null; then
    echo -e "${GREEN}[TERDETEKSI] Aplikasi PHP / Laravel${NC}"
    
    echo -e "${YELLOW}Menginstal Apache, PHP, & Ekstensi...${NC}"
    sudo apt-get update
    sudo apt-get install -y apache2 php libapache2-mod-php php-mysql php-cli php-curl php-xml php-mbstring unzip

    # Jika proyek Laravel memiliki package.json untuk build aset frontend (Mix/Vite)
    if [ -f "package.json" ]; then
        if ! command -v node &> /dev/null; then
            echo -e "${YELLOW}Menginstal Node.js untuk kompilasi aset...${NC}"
            curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
            sudo apt-get install -y nodejs
        fi
        echo -e "${YELLOW}Menginstal & Building Aset Frontend...${NC}"
        npm install && (npm run build 2>/dev/null || npm run dev 2>/dev/null)
    fi

    # Install dependensi Composer
    if [ -f "composer.json" ]; then
        if ! command -v composer &> /dev/null; then
            echo -e "${YELLOW}Menginstal Composer...${NC}"
            curl -sS https://getcomposer.org/installer | php
            sudo mv composer.phar /usr/local/bin/composer
        fi
        composer install --no-dev
    fi

    # Konfigurasi khusus Laravel
    if [ -f "artisan" ]; then
        DOC_ROOT="$TARGET_DIR/public"
        
        if [ -f ".env.example" ] && [ ! -f ".env" ]; then
            cp .env.example .env
            php artisan key:generate
        fi
    else
        DOC_ROOT="$TARGET_DIR"
    fi

    # Atur Hak Akses Folder Web Server
    sudo chown -R www-data:www-data "$TARGET_DIR"
    sudo chmod -R 775 "$TARGET_DIR"

    # Buat VirtualHost Apache
    VHOST_CONF="/etc/apache2/sites-available/$REPO_NAME.conf"
    echo "<VirtualHost *:80>
        ServerAdmin webmaster@localhost
        DocumentRoot $DOC_ROOT
        <Directory $DOC_ROOT>
            Options Indexes FollowSymLinks
            AllowOverride All
            Require all granted
        </Directory>
        ErrorLog \${APACHE_LOG_DIR}/error.log
        CustomLog \${APACHE_LOG_DIR}/access.log combined
    </VirtualHost>" | sudo tee "$VHOST_CONF" > /dev/null

    sudo a2dissite 000-default.conf 2>/dev/null
    sudo a2ensite "$REPO_NAME.conf"
    sudo a2enmod rewrite
    sudo systemctl restart apache2
    
    PORT=80

# PRIORITAS 2: Aplikasi Murni Node.js (Express / React / Next / Vue)
elif [ -f "package.json" ]; then
    echo -e "${GREEN}[TERDETEKSI] Aplikasi Node.js Murni${NC}"
    
    if ! command -v node &> /dev/null; then
        echo -e "${YELLOW}Menginstal Node.js...${NC}"
        curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
        sudo apt-get install -y nodejs
    fi
    
    echo -e "${YELLOW}Menginstal Dependensi NPM...${NC}"
    npm install

    PORT=3000

    if grep -q "\"build\":" "package.json"; then
        echo -e "${YELLOW}Membangun Proyek (Building)...${NC}"
        npm run build
    fi

    sudo npm install -g pm2
    
    if grep -q "\"start\":" "package.json"; then
        pm2 start npm --name "$REPO_NAME" -- start
    else
        pm2 start index.js --name "$REPO_NAME" 2>/dev/null || pm2 start app.js --name "$REPO_NAME"
    fi

# PRIORITAS 3: Aplikasi Python (Flask / Django)
elif [ -f "requirements.txt" ]; then
    echo -e "${GREEN}[TERDETEKSI] Aplikasi Python (Flask/Django)${NC}"
    
    sudo apt-get update
    sudo apt-get install -y python3 python3-pip python3-venv

    python3 -m venv venv
    source venv/bin/activate
    pip install -r requirements.txt

    PORT=5000
    nohup python3 app.py > app.log 2>&1 &

# PRIORITAS 4: Web Statis (HTML/CSS/JS)
else
    echo -e "${YELLOW}[TERDETEKSI] Situs Statis HTML/CSS/JS${NC}"
    sudo apt-get update
    sudo apt-get install -y apache2
    sudo cp -r . /var/www/html/
    PORT=80
fi

# 3. Deteksi & Install Database jika diperlukan
echo -e "\n${YELLOW}[3/4] Memeriksa Kebutuhan Database...${NC}"
read -p "Apakah aplikasi ini menggunakan MySQL Database? (y/n): " NEED_DB < /dev/tty

if [[ "$NEED_DB" =~ ^[Yy]$ ]]; then
    if ! command -v mysql &> /dev/null; then
        echo -e "${YELLOW}Menginstal MariaDB/MySQL Server...${NC}"
        sudo apt-get install -y mariadb-server
        sudo systemctl start mariadb
    fi

    read -p "Masukkan Nama Database yang ingin dibuat: " DB_NAME < /dev/tty
    sudo mysql -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;"
    echo -e "${GREEN}Database '$DB_NAME' berhasil dibuat!${NC}"

    # Jika Laravel, jalankan Artisan Migrate otomatis
    if [ -f "artisan" ]; then
        echo -e "${YELLOW}Menjalankan Laravel Migration...${NC}"
        # Update setting .env untuk DB
        sed -i "s/DB_DATABASE=.*/DB_DATABASE=$DB_NAME/" .env
        sed -i "s/DB_USERNAME=.*/DB_USERNAME=root/" .env
        sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=/" .env
        php artisan migrate --force
    fi

    # Cari file .sql untuk di-import otomatis (jika ada)
    SQL_FILE=$(find . -maxdepth 2 -name "*.sql" | head -n 1)
    if [ -n "$SQL_FILE" ]; then
        echo -e "${YELLOW}Ditemukan berkas database: $SQL_FILE. Mengimpor data...${NC}"
        sudo mysql "$DB_NAME" < "$SQL_FILE"
        echo -e "${GREEN}Impor database selesai!${NC}"
    fi
fi

# 4. Informasi Akses Publik
echo -e "\n${BLUE}====================================================${NC}"
echo -e "${GREEN}       DEPLOYMENT BERHASIL / SIAP DEMO!            ${NC}"
echo -e "${BLUE}====================================================${NC}"
echo ""
echo -e "Aplikasi kamu berjalan pada Port: ${YELLOW}$PORT${NC}"
echo ""
echo -e "Untuk mengakses link publik di Killercoda:"
echo -e "1. Klik tombol ${YELLOW}'Traffic / Ports'${NC} di panel atas Killercoda."
echo -e "2. Masukkan nomor Port: ${YELLOW}$PORT${NC}"
echo -e "3. Klik ${GREEN}'Access'${NC} untuk membuka URL publik aplikasi kamu."
echo ""