#!/bin/bash
# Xray + VLESS + WebSocket + TLS + Caddy 安装脚本
# 生成日期: 2025-07-08

DOMAIN="notetracker.top"
UUID="74f73914-85f7-4c87-937c-d1f233cdca83"
WS_PATH="/ray"

# 安装依赖
dnf install -y curl wget unzip tar socat vim 'dnf-command(copr)'
dnf copr enable @caddy/caddy -y
dnf install -y caddy

# 安装 Xray-core
bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)

# 配置 Xray
mkdir -p /usr/local/etc/xray
cat > /usr/local/etc/xray/config.json <<EOF
{
  "inbounds": [
    {
      "port": 10000,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "74f73914-85f7-4c87-937c-d1f233cdca83",
            "level": 0,
            "email": "user@notetracker.top"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/ray"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
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

# 配置 Caddyfile
cat > /etc/caddy/Caddyfile <<EOF
notetracker.top {
    encode gzip
    reverse_proxy /ray 127.0.0.1:10000 {
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

# 防火墙放行
firewall-cmd --permanent --add-port=80/tcp
firewall-cmd --permanent --add-port=443/tcp
firewall-cmd --reload

echo -e "\n✅ 安装完成！"
echo "域名：notetracker.top"
echo "UUID：74f73914-85f7-4c87-937c-d1f233cdca83"
echo "路径：/ray"
echo "协议：VLESS + WS + TLS"
echo "导入链接："
echo "vless://74f73914-85f7-4c87-937c-d1f233cdca83@notetracker.top:443?encryption=none&security=tls&type=ws&host=notetracker.top&path=%2Fray#KR-Xray-VLESS"
