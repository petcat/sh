#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/opt/gotify"

# 自动检测架构
detect_arch() {
    case "$(uname -m)" in
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
    fi
}

# 获取最新版本号并拼接 zip 下载 URL
get_gotify_url() {
    arch=$(detect_arch)
    [ "$arch" = "unsupported" ] && { echo "[!] 不支持架构"; exit 1; }
    latest=$(curl -s https://api.github.com/repos/gotify/server/releases/latest \
             | grep tag_name | cut -d '"' -f4)
    echo "https://github.com/gotify/server/releases/download/${latest}/gotify-linux-${arch}.zip"
}

# 提取并只保留二进制，命名为 gotify
extract_binary() {
    zipfile="$1"
    tmpdir=$(mktemp -d)
    unzip -j "$zipfile" -d "$tmpdir"
    binfile=$(find "$tmpdir" -type f -name "gotify-linux-*")
    sudo mv "$binfile" "$APP_DIR/gotify"
    sudo chmod +x "$APP_DIR/gotify"
    rm -rf "$tmpdir"
}

install_gotify() {
    detect_os
    url=$(get_gotify_url)
    echo "[*] 安装 Gotify ($url)"
    sudo mkdir -p "$APP_DIR"
    tmpzip=$(mktemp)
    curl -L -o "$tmpzip" "$url"
    extract_binary "$tmpzip"
    rm -f "$tmpzip"

    # 默认配置
    if [ ! -f "$APP_DIR/config.yml" ]; then
        sudo tee "$APP_DIR/config.yml" > /dev/null <<'EOF'
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

    # systemd 服务文件放在 APP_DIR
    sudo tee "$APP_DIR/gotify.service" > /dev/null <<EOF
[Unit]
Description=Gotify Server
After=network.target

[Service]
Type=simple
WorkingDirectory=$APP_DIR
ExecStart=$APP_DIR/gotify -config $APP_DIR/config.yml
Restart=always
User=nobody

[Install]
WantedBy=multi-user.target
EOF

    # 建立软链接
    sudo ln -sf "$APP_DIR/gotify.service" /etc/systemd/system/gotify.service

    sudo systemctl daemon-reload
    sudo systemctl enable --now gotify.service
    echo "[+] Gotify 已安装并启动"
}

upgrade_gotify() {
    detect_os
    url=$(get_gotify_url)
    echo "[*] 升级 Gotify ($url)"
    tmpzip=$(mktemp)
    curl -L -o "$tmpzip" "$url"
    extract_binary "$tmpzip"
    rm -f "$tmpzip"
    sudo systemctl restart gotify.service
    echo "[+] Gotify 已升级并重启"
}

install_timer() {
    echo "[*] 安装 systemd timer..."
    sudo mkdir -p "$APP_DIR"

    # 升级 service 文件
    sudo tee "$APP_DIR/gotify-update.service" > /dev/null <<EOF
[Unit]
Description=Gotify Monthly Upgrade

[Service]
Type=oneshot
ExecStart=$APP_DIR/gotify.sh -up
EOF

    # 定时器文件
    sudo tee "$APP_DIR/gotify-update.timer" > /dev/null <<EOF
[Unit]
Description=Monthly Gotify Upgrade

[Timer]
OnCalendar=monthly
Persistent=true

[Install]
WantedBy=timers.target
EOF

    # 建立软链接
    sudo ln -sf "$APP_DIR/gotify-update.service" /etc/systemd/system/gotify-update.service
    sudo ln -sf "$APP_DIR/gotify-update.timer" /etc/systemd/system/gotify-update.timer

    sudo systemctl daemon-reload
    sudo systemctl enable --now gotify-update.timer
    echo "[+] 每月自动升级定时器已启用"
}

case "${1:-}" in
    -up) upgrade_gotify ;;
    -timer) install_timer ;;
    *) install_gotify ;;
esac
