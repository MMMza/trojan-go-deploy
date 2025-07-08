#!/bin/bash

set -e

# 参数定义
DOMAIN="notetracker.top"
PASSWORD="pw20250728"
WS_PATH="/trojan"
TROJAN_GO_BIN="/usr/local/bin/trojan-go"
TROJAN_GO_DIR="/usr/local/etc/trojan-go"
CERT_FILE="/etc/ssl/trojan/fullchain.crt"
KEY_FILE="/etc/ssl/trojan/private.key"
NGINX_CONF="/etc/nginx/conf.d/notetracker.conf"

# 1. 安装依赖
dnf install -y epel-release
dnf install -y nginx unzip wget vim curl socat

# 2. 安装 acme.sh 并签发证书
curl https://get.acme.sh | sh
~/.acme.sh/acme.sh --register-account -m admin@${DOMAIN}
~/.acme.sh/acme.sh --issue -d ${DOMAIN} --standalone --force --keylength ec-256
mkdir -p /etc/ssl/trojan
~/.acme.sh/acme.sh --install-cert -d ${DOMAIN} --ecc \
  --key-file ${KEY_FILE} \
  --fullchain-file ${CERT_FILE}

# 3. 下载并部署 Trojan-Go
mkdir -p ${TROJAN_GO_DIR}
cd /usr/local/bin
wget -q https://github.com/p4gefau1t/trojan-go/releases/latest/download/trojan-go-linux-amd64.zip
unzip -o trojan-go-linux-amd64.zip
chmod +x trojan-go
rm -f trojan-go-linux-amd64.zip

# 4. 配置 Trojan-Go
cat > ${TROJAN_GO_DIR}/config.json <<EOF
{
  "run_type": "server",
  "local_addr": "127.0.0.1",
  "local_port": 9001,
  "remote_addr": "127.0.0.1",
  "remote_port": 80,
  "password": [
    "${PASSWORD}"
  ],
  "websocket": {
    "enabled": true,
    "path": "${WS_PATH}"
  },
  "ssl": {
    "cert": "${CERT_FILE}",
    "key": "${KEY_FILE}",
    "sni": "${DOMAIN}"
  }
}
EOF

# 5. 配置 systemd 服务
cat > /etc/systemd/system/trojan-go.service <<EOF
[Unit]
Description=Trojan-Go Server
After=network.target

[Service]
Type=simple
ExecStart=${TROJAN_GO_BIN} -config ${TROJAN_GO_DIR}/config.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# 6. 配置 nginx
cat > ${NGINX_CONF} <<EOF
server {
    listen 443 ssl http2;
    server_name ${DOMAIN};

    ssl_certificate ${CERT_FILE};
    ssl_certificate_key ${KEY_FILE};

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location ${WS_PATH} {
        proxy_pass http://127.0.0.1:9001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    root /var/www/notetracker;
    index index.html;
}

server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$server_name\$request_uri;
}
EOF

# 7. 设置伪装网页
mkdir -p /var/www/notetracker
cat > /var/www/notetracker/index.html <<EOF
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <title>欢迎访问</title>
</head>
<body>
  <h2>欢迎访问我的技术博客</h2>
</body>
</html>
EOF

# 8. 启动服务
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable nginx trojan-go
systemctl restart nginx trojan-go

echo "Trojan-Go 已部署完毕！"
