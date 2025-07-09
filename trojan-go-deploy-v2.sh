#!/bin/bash

# ========= 参数定义 =========
DOMAIN="notetracker.top"
PASSWORD="pw20250728"
WS_PATH="/trojan"
TROJAN_DIR="/usr/local/trojan-go"
SSL_DIR="/etc/ssl/trojan"
NGINX_CONF="/etc/nginx/conf.d/${DOMAIN}.conf"

# ========= 安装基础环境 =========
echo "[+] 安装必要组件..."
dnf install -y epel-release
dnf install -y nginx unzip curl socat git firewalld

# ========= 开启防火墙端口 =========
systemctl enable firewalld --now
firewall-cmd --permanent --add-port=80/tcp
firewall-cmd --permanent --add-port=443/tcp
firewall-cmd --reload

# ========= Trojan-Go 安装 =========
echo "[+] 下载 Trojan-Go..."
mkdir -p $TROJAN_DIR && cd $TROJAN_DIR
curl -LO https://github.com/p4gefau1t/trojan-go/releases/latest/download/trojan-go-linux-amd64.zip
unzip trojan-go-linux-amd64.zip && chmod +x trojan-go

# ========= 申请 SSL 证书 =========
echo "[+] 签发 TLS 证书..."
mkdir -p $SSL_DIR
systemctl stop nginx || true
curl https://get.acme.sh | sh
~/.acme.sh/acme.sh --issue -d $DOMAIN --standalone
~/.acme.sh/acme.sh --install-cert -d $DOMAIN \
  --key-file $SSL_DIR/privkey.pem \
  --fullchain-file $SSL_DIR/fullchain.pem

# ========= 写入 Trojan-Go 配置 =========
echo "[+] 写入 Trojan-Go 配置..."
cat > $TROJAN_DIR/config.json <<EOF
{
  "run_type": "server",
  "local_addr": "127.0.0.1",
  "local_port": 9001,
  "remote_addr": "127.0.0.1",
  "remote_port": 80,
  "password": ["$PASSWORD"],
  "websocket": {
    "enabled": true,
    "path": "$WS_PATH",
    "host": "$DOMAIN"
  },
  "ssl": {
    "cert": "$SSL_DIR/fullchain.pem",
    "key": "$SSL_DIR/privkey.pem",
    "sni": "$DOMAIN"
  }
}
EOF

# ========= 配置 Nginx 伪装站点 =========
echo "[+] 设置伪装站点..."
mkdir -p /var/www/html
echo "<h1>Welcome to $DOMAIN</h1><p>技术博客</p>" > /var/www/html/index.html

cat > $NGINX_CONF <<EOF
server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate $SSL_DIR/fullchain.pem;
    ssl_certificate_key $SSL_DIR/privkey.pem;

    location / {
        root /var/www/html;
        index index.html;
    }

    location = $WS_PATH {
        proxy_pass http://127.0.0.1:9001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
    }
}
EOF

systemctl enable nginx --now
systemctl restart nginx

# ========= Trojan-Go Systemd 启动 =========
echo "[+] 设置 Trojan-Go 服务..."
cat > /etc/systemd/system/trojan-go.service <<EOF
[Unit]
Description=Trojan-Go Service
After=network.target

[Service]
ExecStart=$TROJAN_DIR/trojan-go -config $TROJAN_DIR/config.json
Restart=always
User=nobody
LimitNOFILE=51200

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl enable trojan-go --now

echo "[✓] Trojan-Go 已成功部署！请使用域名 $DOMAIN 连接节点。"
