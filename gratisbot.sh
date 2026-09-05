#!/bin/bash

# ==============================================================================
# GRATISBOT v4.0 - Universal & Deep-Technology Aware Auto-Deployment Engine
# Fixed: Standalone Composer binary, dynamic PHP extension binder, & Apache permissions
# ==============================================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}====================================================${NC}"
echo -e "${CYAN}   GRATISBOT v4.0: UNIVERSAL AUTO-DEPLOY ENGINE     ${NC}"
echo -e "${CYAN}====================================================${NC}"

export DEBIAN_FRONTEND=noninteractive
export COMPOSER_ALLOW_SUPERUSER=1

# ------------------------------------------------------------------------------
# 1. PERSIAPAN SISTEM & DEPENDENSI DASAR
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}[1/6] Menginstal Sistem Base & Tools...${NC}"
sudo apt-get update -y
sudo apt-get install -y curl wget git unzip software-properties-common ufw \
                        apache2 libapache2-mod-fcgid mariadb-server mariadb-client jq

git config --global --add safe.directory "*"
sudo a2enmod rewrite headers proxy proxy_http proxy_balancer lbmethod_byrequests 2>/dev/null || true

# Install Standalone Composer Phar (Solusi PHP Parse Error pada Composer APT)
echo -e "${YELLOW}Mengunduh Standalone Composer Phar Binary...${NC}"
sudo wget https://getcomposer.org/download/latest-stable/composer.phar -O /usr/local/bin/composer
sudo chmod +x /usr/local/bin/composer

# ------------------------------------------------------------------------------
# 2. KLONING REPOSITORI GITHUB
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}[2/6] Mengambil Repositori GitHub...${NC}"
read -p "Masukkan URL Repository GitHub: " REPO_URL < /dev/tty

if [ -z "$REPO_URL" ]; then
    echo -e "${RED}Error: URL Repository tidak boleh kosong!${NC}"
    exit 1
fi

REPO_NAME=$(basename "$REPO_URL" .git)
TARGET_DIR="/var/www/$REPO_NAME"

if [ -d "$TARGET_DIR" ]; then
    echo -e "${YELLOW}Membersihkan direktori lama di $TARGET_DIR...${NC}"
    sudo rm -rf "$TARGET_DIR"
fi

echo -e "${GREEN}Kloning repositori ke $TARGET_DIR...${NC}"
sudo git clone "$REPO_URL" "$TARGET_DIR"
cd "$TARGET_DIR"

# ------------------------------------------------------------------------------
# 3. DETEKSI OTOMATIS FRAMEWORK & BAHASA PEMROGRAMAN
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}[3/6] Menganalisis Arsitektur Proyek & Tech Stack...${NC}"

FRAMEWORK="UNKNOWN"
PORT_APP=8080

if [ -f "Dockerfile" ] || [ -f "docker-compose.yml" ]; then
    FRAMEWORK="DOCKER"
elif [ -f "artisan" ]; then
    FRAMEWORK="LARAVEL"
elif [ -f "composer.json" ] || [ -f "index.php" ]; then
    FRAMEWORK="PHP"
elif [ -f "package.json" ]; then
    if grep -q '"next"' package.json 2>/dev/null || grep -q '"react"' package.json 2>/dev/null || grep -q '"vue"' package.json 2>/dev/null; then
        FRAMEWORK="NODE_FRONTEND"
    else
        FRAMEWORK="NODE_BACKEND"
    fi
    PORT_APP=3000
elif [ -f "manage.py" ]; then
    FRAMEWORK="DJANGO"
    PORT_APP=8000
elif [ -f "app.py" ] || [ -f "wsgi.py" ] || [ -f "requirements.txt" ]; then
    FRAMEWORK="PYTHON_FLASK"
    PORT_APP=5000
elif [ -f "Gemfile" ]; then
    FRAMEWORK="RUBY_RAILS"
    PORT_APP=3000
elif [ -f "go.mod" ] || [ -f "main.go" ]; then
    FRAMEWORK="GOLANG"
    PORT_APP=8080
elif [ -f "pom.xml" ] || [ -f "build.gradle" ]; then
    FRAMEWORK="JAVA_SPRING"
    PORT_APP=8080
elif [ -f "index.html" ]; then
    FRAMEWORK="STATIC"
fi

echo -e "${CYAN}Tech Stack Terdeteksi : [ $FRAMEWORK ]${NC}"

# ------------------------------------------------------------------------------
# 4. DEPLOYMENT & INSTALLATION ENGINE (ADAPTIF SEPENUHNYA)
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}[4/6] Mengonfigurasi Runtime Environment...${NC}"

case $FRAMEWORK in
    LARAVEL|PHP)
        PHP_VER="8.2" # Default modern
        if [ -f "composer.json" ]; then
            if grep -q '"php":' composer.json; then
                REQ_PHP=$(grep -i '"php"' composer.json | head -n 1)
                if echo "$REQ_PHP" | grep -qE '8\.3'; then PHP_VER="8.3";
                elif echo "$REQ_PHP" | grep -qE '8\.2'; then PHP_VER="8.2";
                elif echo "$REQ_PHP" | grep -qE '8\.1'; then PHP_VER="8.1";
                elif echo "$REQ_PHP" | grep -qE '8\.0'; then PHP_VER="8.0";
                elif echo "$REQ_PHP" | grep -qE '7\.4|7\.3|7\.2'; then PHP_VER="7.4"; fi
            fi
        fi

        echo -e "${YELLOW}Menginstal PHP $PHP_VER & Ekstensi Komplit...${NC}"
        sudo add-apt-repository -y ppa:ondrej/php
        sudo apt-get update -y
        sudo apt-get install -y php$PHP_VER php$PHP_VER-cli php$PHP_VER-common \
                                php$PHP_VER-mysql php$PHP_VER-xml php$PHP_VER-curl \
                                php$PHP_VER-mbstring php$PHP_VER-zip php$PHP_VER-gd \
                                php$PHP_VER-bcmath php$PHP_VER-intl php$PHP_VER-tokenizer \
                                php$PHP_VER-sqlite3 libapache2-mod-php$PHP_VER

        # Alihkan CLI dan Apache MPM ke versi terdeteksi
        sudo update-alternatives --set php /usr/bin/php$PHP_VER
        
        # Matikan semua modul PHP di Apache sebelum mengaktifkan yang sesuai
        for mod in $(ls /etc/apache2/mods-enabled/php*.load 2>/dev/null); do
            sudo a2dismod $(basename "$mod" .load) 2>/dev/null || true
        done
        sudo a2enmod php$PHP_VER

        if [ -f "composer.json" ]; then
            echo -e "${YELLOW}Menjalankan Composer Install...${NC}"
            /usr/local/bin/composer install --no-interaction --prefer-dist --optimize-autoloader --ignore-platform-reqs
        fi

        if [ "$FRAMEWORK" == "LARAVEL" ]; then
            [ ! -f ".env" ] && ([ -f ".env.example" ] && cp .env.example .env || touch .env)
            sed -i 's|APP_URL=.*|APP_URL=http://localhost|' .env
            php$PHP_VER artisan key:generate --force
            php$PHP_VER artisan storage:link --force 2>/dev/null || true
            DOC_ROOT="$TARGET_DIR/public"
        else
            DOC_ROOT="$TARGET_DIR"
        fi

        if [ -f "package.json" ]; then
            echo -e "${YELLOW}Mengompilasi Aset Frontend (NPM)...${NC}"
            sudo apt-get install -y nodejs npm
            export NODE_OPTIONS=--max-old-space-size=2048
            npm install --legacy-peer-deps || npm install
            npm run build 2>/dev/null || npm run prod 2>/dev/null || true
        fi
        ;;

    NODE_BACKEND|NODE_FRONTEND)
        echo -e "${YELLOW}Menginstal Node.js Runtime & PM2 Process Manager...${NC}"
        sudo apt-get install -y nodejs npm
        sudo npm install -g pm2
        npm install

        if [ "$FRAMEWORK" == "NODE_FRONTEND" ] && grep -q '"build":' package.json; then
            export NODE_OPTIONS=--max-old-space-size=2048
            npm run build
            DOC_ROOT="$TARGET_DIR/dist"
            [ ! -d "$DOC_ROOT" ] && DOC_ROOT="$TARGET_DIR/build"
            [ ! -d "$DOC_ROOT" ] && DOC_ROOT="$TARGET_DIR/out"
        else
            pm2 stop "$REPO_NAME" 2>/dev/null || true
            pm2 start npm --name "$REPO_NAME" -- start 2>/dev/null || pm2 start index.js --name "$REPO_NAME"
            pm2 save
            IS_PROXY=true
        fi
        ;;

    DJANGO|PYTHON_FLASK)
        echo -e "${YELLOW}Menginstal Python3, Virtualenv, & Gunicorn...${NC}"
        sudo apt-get install -y python3 python3-pip python3-venv gunicorn
        python3 -m venv venv
        source venv/bin/activate
        
        if [ -f "requirements.txt" ]; then
            pip install -r requirements.txt
        fi

        pip install gunicorn

        if [ "$FRAMEWORK" == "DJANGO" ]; then
            python3 manage.py migrate 2>/dev/null || true
            python3 manage.py collectstatic --noinput 2>/dev/null || true
            
            WSGI_MODULE=$(find . -name "wsgi.py" | head -n 1 | cut -d'/' -f2)
            pm2 stop "$REPO_NAME" 2>/dev/null || true
            pm2 start "venv/bin/gunicorn ${WSGI_MODULE}.wsgi:application --bind 127.0.0.1:$PORT_APP" --name "$REPO_NAME"
        else
            APP_FILE="app:app"
            [ -f "main.py" ] && APP_FILE="main:app"
            pm2 stop "$REPO_NAME" 2>/dev/null || true
            pm2 start "venv/bin/gunicorn $APP_FILE --bind 127.0.0.1:$PORT_APP" --name "$REPO_NAME"
        fi
        pm2 save
        IS_PROXY=true
        ;;

    RUBY_RAILS)
        echo -e "${YELLOW}Menginstal Ruby & Bundler...${NC}"
        sudo apt-get install -y ruby-full build-essential libsqlite3-dev
        sudo gem install bundler
        bundle install
        rails db:migrate 2>/dev/null || true
        rails assets:precompile 2>/dev/null || true
        pm2 stop "$REPO_NAME" 2>/dev/null || true
        pm2 start "bundle exec rails server -p $PORT_APP -b 127.0.0.1 -e production" --name "$REPO_NAME"
        pm2 save
        IS_PROXY=true
        ;;

    GOLANG)
        echo -e "${YELLOW}Menginstal Go Compiler & Build Binary...${NC}"
        sudo apt-get install -y golang-go
        go build -o app_binary
        pm2 stop "$REPO_NAME" 2>/dev/null || true
        pm2 start "./app_binary" --name "$REPO_NAME"
        pm2 save
        IS_PROXY=true
        ;;

    JAVA_SPRING)
        echo -e "${YELLOW}Menginstal OpenJDK & Building Spring Boot...${NC}"
        sudo apt-get install -y openjdk-17-jdk maven gradle
        if [ -f "mvnw" ]; then ./mvnw clean package -DskipTests
        elif [ -f "gradlew" ]; then ./gradlew build -x test
        else mvn clean package -DskipTests; fi

        JAR_FILE=$(find target/ build/libs/ -name "*.jar" | head -n 1)
        pm2 stop "$REPO_NAME" 2>/dev/null || true
        pm2 start "java -jar $JAR_FILE --server.port=$PORT_APP" --name "$REPO_NAME"
        pm2 save
        IS_PROXY=true
        ;;

    DOCKER)
        echo -e "${YELLOW}Menginstal Docker Engine & Docker Compose...${NC}"
        sudo apt-get install -y docker.io docker-compose
        sudo systemctl start docker
        sudo systemctl enable docker

        if [ -f "docker-compose.yml" ]; then
            sudo docker-compose up -d --build
        else
            sudo docker build -t "$REPO_NAME" .
            sudo docker run -d -p $PORT_APP:80 --name "$REPO_NAME" "$REPO_NAME"
        fi
        IS_PROXY=true
        ;;

    STATIC)
        DOC_ROOT="$TARGET_DIR"
        ;;
esac

# ------------------------------------------------------------------------------
# 5. DATABASE AUTOMATION (MARIADB)
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}[5/6] Penyiapan Database MySQL/MariaDB...${NC}"
sudo systemctl start mariadb
sudo mysql -e "CREATE USER IF NOT EXISTS 'gratisbot'@'localhost' IDENTIFIED BY 'gratisbot123';"
sudo mysql -e "GRANT ALL PRIVILEGES ON *.* TO 'gratisbot'@'localhost' WITH GRANT OPTION;"
sudo mysql -e "FLUSH PRIVILEGES;"

SQL_FILE=$(find . -maxdepth 2 -name "*.sql" | head -n 1)

read -p "Apakah aplikasi ini memerlukan Database MySQL/MariaDB? (y/n): " NEED_DB < /dev/tty

if [[ "$NEED_DB" =~ ^[Yy]$ ]]; then
    read -p "Masukkan Nama Database: " DB_NAME < /dev/tty
    if [ -z "$DB_NAME" ]; then DB_NAME="$REPO_NAME"; fi

    sudo mysql -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;"

    if [ -n "$SQL_FILE" ]; then
        echo -e "${YELLOW}Mengimpor file skema database ($SQL_FILE)...${NC}"
        sudo mysql "$DB_NAME" < "$SQL_FILE"
    fi

    # Auto Inject Konfigurasi DB ke File Environment
    if [ -f ".env" ]; then
        sed -i "s/DB_HOST=.*/DB_HOST=127.0.0.1/" .env 2>/dev/null || true
        sed -i "s/DB_DATABASE=.*/DB_DATABASE=$DB_NAME/" .env 2>/dev/null || true
        sed -i "s/DB_NAME=.*/DB_NAME=$DB_NAME/" .env 2>/dev/null || true
        sed -i "s/DB_USERNAME=.*/DB_USERNAME=gratisbot/" .env 2>/dev/null || true
        sed -i "s/DB_USER=.*/DB_USER=gratisbot/" .env 2>/dev/null || true
        sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=gratisbot123/" .env 2>/dev/null || true
        sed -i "s/DB_PASS=.*/DB_PASS=gratisbot123/" .env 2>/dev/null || true
    fi
fi

# Run Migration khusus Laravel jika DB kosong
if [ "$FRAMEWORK" == "LARAVEL" ] && [ -z "$SQL_FILE" ] && [ -n "$DB_NAME" ]; then
    php$PHP_VER artisan migrate:fresh --seed --force 2>/dev/null || php$PHP_VER artisan migrate --force 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 6. PENYESUAIAN HAK AKSES & APACHE SERVER
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}[6/6] Menyesuaikan Permisi Direktori & Apache VirtualHost...${NC}"

# Perbaikan Hak Akses Direktori Proyek
sudo chown -R www-data:www-data "$TARGET_DIR"
sudo chmod -R 775 "$TARGET_DIR"
if [ "$FRAMEWORK" == "LARAVEL" ]; then
    sudo chmod -R 777 "$TARGET_DIR/storage" "$TARGET_DIR/bootstrap/cache"
fi

VHOST_CONF="/etc/apache2/sites-available/$REPO_NAME.conf"

if [ "$IS_PROXY" = true ]; then
    # Jika berbasis Application Server (Node, Python, Go, Java, Docker, Rails) -> Reverse Proxy
    sudo bash -c "cat <<EOF > $VHOST_CONF
<VirtualHost *:80>
    ServerName localhost
    ProxyRequests Off
    ProxyPreserveHost On
    ProxyVia Full
    <Proxy *>
        Require all granted
    </Proxy>
    ProxyPass / http://127.0.0.1:$PORT_APP/
    ProxyPassReverse / http://127.0.0.1:$PORT_APP/
</VirtualHost>
EOF"
else
    # Jika berbasis File Server (PHP, Laravel, Static HTML, React/Vue Dist)
    [ -z "$DOC_ROOT" ] && DOC_ROOT="$TARGET_DIR"
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

sudo a2dissite 000-default.conf 2>/dev/null || true
sudo a2ensite "$REPO_NAME.conf"
sudo systemctl restart apache2

# ------------------------------------------------------------------------------
# FINISH & SUMMARY
# ------------------------------------------------------------------------------
echo -e "\n${GREEN}====================================================${NC}"
echo -e "${GREEN}      DEPLOYMENT SELESAI DAN BERJALAN SUKSES!      ${NC}"
echo -e "${GREEN}====================================================${NC}"
echo -e "Framework    : ${CYAN}$FRAMEWORK${NC}"
echo -e "Lokasi Proyek: ${CYAN}$TARGET_DIR${NC}"
echo -e "Port Web     : ${CYAN}80${NC}"
echo -e "\nBuka Killercoda menu ${YELLOW}'Traffic / Ports'${NC} -> Masukkan port ${YELLOW}80${NC}."