#!/usr/bin/env bash
# Trojan-Go 一键安装脚本
# 适用于 AlmaLinux 8 x64
# 请在root用户下运行

set -e

DOMAIN="your.domain.com"
PASSWORD="your_password"

# 安装依赖
dnf install -y epel-release
dnf install -y unzip curl socat git nginx firewalld

# 关闭防火墙（如需开启请自行放行端口）
systemctl stop firewalld
systemctl disable firewalld

# 下载 Trojan-Go
mkdir -p /usr/local/trojan-go
cd /usr/local/trojan-go
curl -L -o trojan-go.zip https://github.com/p4gefau1t/trojan-go/releases/latest/download/trojan-go-linux-amd64.zip
unzip -o trojan-go.zip
chmod +x trojan-go

# 创建目录用于证书
mkdir -p /etc/ssl/trojan/

# 安装 acme.sh 并签发证书
curl https://get.acme.sh | sh
export PATH=~/.acme.sh:$PATH
~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
~/.acme.sh/acme.sh --issue -d $DOMAIN --standalone

# 安装证书
~/.acme.sh/acme.sh --install-cert -d $DOMAIN \
  --key-file /etc/ssl/trojan/privkey.pem \
  --fullchain-file /etc/ssl/trojan/fullchain.pem

# 配置 Trojan-Go
cat > /usr/local/trojan-go/config.json <<EOF
{
  "run_type": "server",
  "local_addr": "127.0.0.1",
  "local_port": 9001,
  "remote_addr": "0.0.0.0",
  "remote_port": 80,
  "password": ["$PASSWORD"],
  "ssl": {
    "cert": "/etc/ssl/trojan/fullchain.pem",
    "key": "/etc/ssl/trojan/privkey.pem",
    "sni": "$DOMAIN"
  },
  "websocket": {
    "enabled": true,
    "path": "/trojan"
  }
}
EOF

# 配置 Nginx
cat > /etc/nginx/conf.d/$DOMAIN.conf <<EOF
server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate /etc/ssl/trojan/fullchain.pem;
    ssl_certificate_key /etc/ssl/trojan/privkey.pem;

    location / {
        root /var/www/html;
        index index.html;
    }

    location /trojan {
        proxy_pass http://127.0.0.1:9001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }
}
EOF

# 启动Nginx
systemctl enable nginx
systemctl restart nginx

# 配置 Systemd 服务
cat > /etc/systemd/system/trojan-go.service <<EOF
[Unit]
Description=Trojan-Go
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/trojan-go/trojan-go -config /usr/local/trojan-go/config.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# 启动 Trojan-Go
systemctl daemon-reload
systemctl enable trojan-go
systemctl restart trojan-go

echo "✅ 部署完成！请使用域名 $DOMAIN 进行连接。"

