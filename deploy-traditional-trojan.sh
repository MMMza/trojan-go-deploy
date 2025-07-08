#!/bin/bash

# 停止并移除现有 Trojan-Go 服务
systemctl stop trojan-go
systemctl disable trojan-go
rm -f /etc/systemd/system/trojan-go.service
rm -rf /usr/local/etc/trojan-go
rm -f /usr/local/bin/trojan-go

# 移除 Nginx WS 反代配置
rm -f /etc/nginx/conf.d/notetracker.conf
nginx -t && systemctl restart nginx

# 下载 Trojan 原版二进制
wget -O /usr/local/bin/trojan https://github.com/trojan-gfw/trojan/releases/download/v1.16.0/trojan-linux-amd64
chmod +x /usr/local/bin/trojan

# 创建配置目录
mkdir -p /usr/local/etc/trojan

# 写入 Trojan 配置文件
cat > /usr/local/etc/trojan/config.json <<EOF
{
  "run_type": "server",
  "local_addr": "0.0.0.0",
  "local_port": 443,
  "remote_addr": "127.0.0.1",
  "remote_port": 80,
  "password": ["pw20250728"],
  "ssl": {
    "cert": "/etc/ssl/trojan/fullchain.crt",
    "key": "/etc/ssl/trojan/private.key",
    "sni": "notetracker.top"
  }
}
EOF

# 写入 systemd 服务文件
cat > /etc/systemd/system/trojan.service <<EOF
[Unit]
Description=Trojan Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/trojan -c /usr/local/etc/trojan/config.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# 启动并设置开机启动
systemctl daemon-reload
systemctl enable trojan
systemctl start trojan
