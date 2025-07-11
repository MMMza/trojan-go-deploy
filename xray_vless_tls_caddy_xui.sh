#!/bin/bash
# 一键安装 Xray + VLESS + WebSocket + TLS + Caddy + x-ui 面板（不启用 x-ui TLS）
# 更新日期: $(date +"%Y-%m-%d")

read -p "请输入你的域名（已解析到本机IP）: " DOMAIN
read -p "请输入 WebSocket 路径（默认 /ray）: " WS_PATH
WS_PATH={WS_PATH:-/ray}

# 自动生成 UUID
UUID=$(cat /proc/sys/kernel/random/uuid)
echo -e "已生成 UUID: $UUID"

# 安装依赖
dnf install -y curl wget unzip tar socat vim 'dnf-command(copr)'
dnf copr enable @caddy/caddy -y
dnf install -y caddy

# 安装 Xray-core
bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)

# 写入 Xray 配置
mkdir -p /usr/local/etc/xray
cat > /usr/local/etc/xray/config.json <<EOF
{
  "inbounds": [
    {
      "port": 10000,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "$UUID", "level": 0, "email": "user@$DOMAIN" }],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "$WS_PATH" }
      }
    }
  ],
  "outbounds": [{ "protocol": "freedom" }]
}
EOF

# 写入 Xray systemd 服务
cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
User=nobody
ExecStart=/usr/local/bin/xray -config /usr/local/etc/xray/config.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# 写入 Caddyfile
cat > /etc/caddy/Caddyfile <<EOF
$DOMAIN {
    encode gzip
    reverse_proxy $WS_PATH 127.0.0.1:10000 {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
    root * /usr/share/caddy
    file_server
}
EOF

# 启动服务
systemctl daemon-reload
systemctl enable --now xray
systemctl enable --now caddy

# 防火墙放通
firewall-cmd --permanent --add-port=80/tcp
firewall-cmd --permanent --add-port=443/tcp
firewall-cmd --permanent --add-port=54321/tcp
firewall-cmd --permanent --add-port=54322/tcp
firewall-cmd --reload

# 检查 TLS 签发是否成功
echo "等待 Caddy 自动申请 TLS（10秒）..."
sleep 10
CERT_PATH="/var/lib/caddy/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/$DOMAIN"
if [[ -d "$CERT_PATH" ]]; then
  echo "✅ TLS 证书签发成功，存放路径：$CERT_PATH"
else
  echo "⚠️ TLS 证书可能未签发，请确认域名解析 & 80/443 未被占用"
fi

# 安装 x-ui 面板（不启用 TLS）
bash <(curl -Ls https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh)

# 输出信息
echo -e "\n✅ 安装完成！"
echo "域名：$DOMAIN"
echo "UUID：$UUID"
echo "路径：$WS_PATH"
echo "协议：VLESS + WS + TLS"
echo -e "\n导入链接："
echo "vless://$UUID@$DOMAIN:443?encryption=none&security=tls&type=ws&host=$DOMAIN&path=$(echo -n $WS_PATH | jq -sRr @uri)#Xray-VLESS"
