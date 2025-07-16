#!/bin/bash

set -e

# === 系统变量定义 ===
DOMAIN="woxidoxi.top"
DB_NAME="v2board"
DB_USER="v2user"
DB_PASS="v2securepass"
ADMIN_EMAIL="admin@woxidoxi.top"
ADMIN_PASS="admin123456"

# === 更新系统 ===
apt update && apt upgrade -y

# === 安装依赖 ===
apt install -y nginx mysql-server php php-fpm php-mysql php-curl php-mbstring php-xml php-bcmath php-zip unzip git curl composer ufw certbot python3-certbot-nginx

# === 配置防火墙 ===
ufw allow OpenSSH
ufw allow 80
ufw allow 443
ufw --force enable

# === 配置数据库 ===
mysql -u root <<EOF
CREATE DATABASE $DB_NAME DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF

# === 克隆并部署 V2Board ===
cd /var/www
git clone https://github.com/v2board/v2board.git
cd v2board
composer install --no-dev
cp .env.example .env

# === 写入 .env 文件 ===
cat > .env <<EOF
APP_NAME=V2Board
APP_ENV=production
APP_KEY=
APP_DEBUG=false
APP_URL=https://$DOMAIN

DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=$DB_NAME
DB_USERNAME=$DB_USER
DB_PASSWORD=$DB_PASS

REDIS_HOST=127.0.0.1
REDIS_PASSWORD=null
REDIS_PORT=6379

MAIL_DRIVER=smtp
MAIL_HOST=mail.example.com
MAIL_PORT=465
MAIL_USERNAME=null
MAIL_PASSWORD=null
MAIL_ENCRYPTION=ssl
MAIL_FROM_ADDRESS=$ADMIN_EMAIL
MAIL_FROM_NAME="V2Board"
EOF

# === 设置权限并初始化 Laravel 应用 ===
chown -R www-data:www-data /var/www/v2board
php artisan key:generate
php artisan migrate --force
php artisan db:seed --force
php artisan storage:link

# === 创建管理员账户 ===
php artisan admin:create --email=$ADMIN_EMAIL --password=$ADMIN_PASS

# === 配置 Nginx 虚拟主机 ===
cat > /etc/nginx/sites-available/v2board <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    root /var/www/v2board/public;
    index index.php index.html;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

ln -s /etc/nginx/sites-available/v2board /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx

# === 配置 HTTPS 证书 ===
certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m $ADMIN_EMAIL

echo "✅ V2Board 安装完成"
echo "🔗 面板地址: https://$DOMAIN"
echo "📧 登录邮箱: $ADMIN_EMAIL"
echo "🔐 登录密码: $ADMIN_PASS"
