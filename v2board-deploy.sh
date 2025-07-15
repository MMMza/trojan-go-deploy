#!/bin/bash

# -------------------------------
# 一键部署 V2Board 面板 (Ubuntu)
# 作者：MMMza / ChatGPT辅助生成
# -------------------------------

set -e

DOMAIN="woxidoxi.top"
DB_NAME="v2board"
DB_USER="v2user"
DB_PASS="v2boardpassword"
ADMIN_EMAIL="admin@${DOMAIN}"
ADMIN_PASS="MySecurePassword2025"
WEB_DIR="/var/www/v2board"

echo "📦 更新系统并安装基础组件..."
apt update && apt install -y nginx mysql-server redis-server php8.1 php8.1-fpm php8.1-mysql php8.1-cli php8.1-mbstring php8.1-curl php8.1-xml php8.1-zip unzip curl git supervisor

echo "📦 安装 Composer..."
curl -sS https://getcomposer.org/installer | php && mv composer.phar /usr/local/bin/composer

echo "📦 安装 Node.js 与 Yarn..."
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs
npm install -g yarn

echo "📁 克隆 V2Board 项目..."
rm -rf $WEB_DIR
mkdir -p $WEB_DIR
cd /var/www
wget https://github.com/MMMza/trojan-go-deploy/raw/main/v2board-complete.tar.gz
tar -xzf v2board-complete.tar.gz -C $WEB_DIR

echo "🔧 设置 .env 配置..."
cd $WEB_DIR
cat > .env <<EOF
APP_NAME=V2Board
APP_ENV=production
APP_KEY=
APP_DEBUG=false
APP_URL=https://${DOMAIN}

LOG_CHANNEL=stack

DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=${DB_NAME}
DB_USERNAME=${DB_USER}
DB_PASSWORD=${DB_PASS}

BROADCAST_DRIVER=log
CACHE_DRIVER=file
QUEUE_CONNECTION=redis
SESSION_DRIVER=redis
SESSION_LIFETIME=120

REDIS_HOST=127.0.0.1
REDIS_PASSWORD=null
REDIS_PORT=6379

MAIL_DRIVER=smtp
MAIL_HOST=smtp.mailtrap.io
MAIL_PORT=2525
MAIL_USERNAME=null
MAIL_PASSWORD=null
MAIL_ENCRYPTION=null
MAIL_FROM_ADDRESS=null
MAIL_FROM_NAME=null
EOF

echo "🛠 设置 MySQL 数据库..."
mysql -e "DROP DATABASE IF EXISTS ${DB_NAME};"
mysql -e "CREATE DATABASE ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -e "DROP USER IF EXISTS '${DB_USER}'@'localhost';"
mysql -e "CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
mysql -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

echo "🔧 安装 Laravel 依赖..."
composer install -o

echo "🧵 安装 Node 构建依赖..."
yarn install
cat > webpack.mix.js <<'EOF'
const mix = require('laravel-mix');
mix.js('resources/js/app.js', 'public/js')
   .sass('resources/sass/app.scss', 'public/css')
   .vue()
   .version();
EOF
yarn add vue-loader@15.9.8 --dev
yarn run production

echo "🔑 Laravel 设置与迁移..."
php artisan key:generate
php artisan migrate:fresh --seed

echo "➕ 创建管理员账号..."
php artisan tinker --execute "DB::table('admins')->insert([
  'email' => '${ADMIN_EMAIL}',
  'password' => bcrypt('${ADMIN_PASS}'),
  'created_at' => now(),
  'updated_at' => now()
]);"

echo "🧩 设置目录权限..."
chown -R www-data:www-data $WEB_DIR
chmod -R 755 $WEB_DIR/storage $WEB_DIR/bootstrap/cache

echo "🌐 配置 Nginx..."
cat > /etc/nginx/sites-available/default <<EOF
server {
    listen 80;
    server_name ${DOMAIN};

    root ${WEB_DIR}/public;
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

echo "🔁 重启服务..."
systemctl reload nginx
systemctl restart php8.1-fpm

echo "✅ 部署完成！请访问： http://${DOMAIN}/"
echo "管理员账号：${ADMIN_EMAIL}"
echo "管理员密码：${ADMIN_PASS}"
