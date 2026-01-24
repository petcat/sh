#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="/opt/gotify"
SERVICE_FILE="/etc/systemd/system/gotify.service"
UPD_SERVICE_FILE="/etc/systemd/system/gotify-update.service"
TIMER_FILE="/etc/systemd/system/gotify-update.timer"

# 自动检测架构
detect_arch() {
    arch=$(uname -m)
    case "$arch" in
        x86_64) echo "amd64" ;;
        aarch64) echo "arm64" ;;
        armv7l) echo "armv7" ;;
        *) echo "unsupported" ;;
    esac
}

# 自动检测系统
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "[*] 系统: $NAME $VERSION_ID ($ID)"
    else
        echo "[!] 无法检测系统版本"
    fi
}

# 获取最新版本号并拼接下载 URL
get_gotify_url() {
    arch=$(detect_arch)
    if [ "$arch" = "unsupported" ]; then
        echo "[!] 不支持的架构: $(uname -m)"
        exit 1
    fi

    latest=$(curl -s https://api.github.com/repos/gotify/server/releases/latest \
             | grep tag_name | cut -d '"' -f4)

    echo "https://github.com/gotify/server/releases/download/${latest}/gotify-linux-${arch}-${latest}.tar.gz"
}

install_gotify() {
    detect_os
    url=$(get_gotify_url)
    echo "[*] 安装 Gotify ($url)"
    sudo mkdir -p "$BASE_DIR"
    curl -L "$url" | sudo tar -xz -C "$BASE_DIR"

    # 默认配置
    if [ ! -f "$BASE_DIR/config.yml" ]; then
        sudo tee "$BASE_DIR/config.yml" > /dev/null <<'EOF'
server:
  listenaddr: ""
  port: 80
  ssl:
    enabled: false
    redirecttohttps: true
    listenaddr: ""
    port: 443
    certfile: ""
    certkey: ""
    letsencrypt:
      enabled: false
      accepttos: false
      cache: data/certs
      hosts: []
database:
  dialect: sqlite3
  connection: data/gotify.db
defaultuser:
  name: admin
  pass: admin
passstrength: 10
uploadedimagesdir: data/images
pluginsdir: data/plugins
registration: false
EOF
    fi

    # systemd 服务
    sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Gotify Server
After=network.target

[Service]
Type=simple
WorkingDirectory=$BASE_DIR
ExecStart=$BASE_DIR/gotify-linux-$(detect_arch) -config $BASE_DIR/config.yml
Restart=always
User=nobody

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable --now gotify.service
    echo "[+] Gotify 已安装并启动"
}

upgrade_gotify() {
    detect_os
    url=$(get_gotify_url)
    echo "[*] 升级 Gotify ($url)"
    tmpdir=$(mktemp -d)
    curl -L "$url" | tar -xz -C "$tmpdir"
    sudo cp "$tmpdir/gotify-linux-$(detect_arch)" "$BASE_DIR/"
    sudo systemctl restart gotify.service
    rm -rf "$tmpdir"
    echo "[+] Gotify 已升级并重启"
}

install_timer() {
    echo "[*] 安装 systemd timer..."
    sudo tee "$UPD_SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Gotify Monthly Upgrade

[Service]
Type=oneshot
ExecStart=$BASE_DIR/gotify.sh -up
EOF

    sudo tee "$TIMER_FILE" > /dev/null <<EOF
[Unit]
Description=Monthly Gotify Upgrade

[Timer]
OnCalendar=monthly
Persistent=true

[Install]
WantedBy=timers.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable --now gotify-update.timer
    echo "[+] 每月自动升级定时器已启用"
}

case "${1:-}" in
    -up) upgrade_gotify ;;
    -timer) install_timer ;;
    *) install_gotify ;;
esac
