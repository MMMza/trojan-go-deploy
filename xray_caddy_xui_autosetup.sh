#!/bin/bash

# 安装依赖
wait_for_cert() {
  local domain="$1"
  local cert_path="/root/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/$domain/$domain.crt"

  echo "等待 Caddy 为 $domain 生成证书..."

  for i in {1..30}; do
    if [[ -f "$cert_path" ]]; then
      echo "✅ 证书已生成：$cert_path"
      return 0
    fi
    echo "等待中（$i 秒）..."
    sleep 1
  done

  echo "❌ 等待证书超时，$cert_path 未生成"
  exit 1
}
dnf install -y curl wget unzip firewalld

# 启动防火墙
systemctl enable firewalld --now
firewall-cmd --permanent --add-port=80/tcp
firewall-cmd --permanent --add-port=443/tcp
firewall-cmd --reload

# 安装 Caddy
mkdir -p /etc/caddy /var/www/html
cat > /etc/yum.repos.d/caddy.repo << EOF
[caddy]
name=Caddy repository
baseurl=https://rpm.nodesource.com/pub_18.x/el/8/x86_64/
enabled=1
gpgcheck=0
EOF

dnf install -y 'dnf-command(copr)'
dnf copr enable @caddy/caddy -y
dnf install -y caddy

# 设置默认伪装网页
echo "Welcome to TechLog - $(date)" > /var/www/html/index.html

# 设置Caddyfile
cat > /etc/caddy/Caddyfile << EOF
mynotehub.top {
  encode gzip
  root * /var/www/html
  file_server
  reverse_proxy 127.0.0.1:8443
}
EOF

# 重启 Caddy
systemctl enable caddy --now

# 拷贝Caddy证书
sleep 5
mkdir -p /etc/ssl/xray
CERT_SRC="/root/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/mynotehub.top"
cp $CERT_SRC/mynotehub.top.crt /etc/ssl/xray/
cp $CERT_SRC/mynotehub.top.key /etc/ssl/xray/
chmod 644 /etc/ssl/xray/*

# 安装 Xray
mkdir -p /usr/local/etc/xray
curl -Lo /usr/local/bin/xray https://github.com/XTLS/Xray-core/releases/latest/download/xray-linux-64.zip
unzip xray-linux-64.zip -d /tmp/xray
install -m 755 /tmp/xray/xray /usr/local/bin/xray
rm -rf /tmp/xray xray-linux-64.zip

# 写入 Xray 配置
cat > /usr/local/etc/xray/config.json << EOF
{
  "inbounds": [
    {
      "port": 8443,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "b4e1c1e7-ca12-412c-b77b-1d8be7aa57ef",
            "flow": "xtls-rprx-vision",
            "level": 0,
            "email": "user@example.com"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "/etc/ssl/xray/mynotehub.top.crt",
              "keyFile": "/etc/ssl/xray/mynotehub.top.key"
            }
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF

# 创建 Xray systemd 服务
cat > /etc/systemd/system/xray.service << EOF
[Unit]
Description=Xray Service
After=network.target nss-lookup.target

[Service]
User=nobody
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# 启动 Xray
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable xray --now

# 安装 x-ui
bash <(curl -Ls https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh)

echo "UUID: b4e1c1e7-ca12-412c-b77b-1d8be7aa57ef"
echo "Xray and Caddy are configured for domain mynotehub.top"