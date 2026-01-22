#!/bin/bash
set -e

App_dir="/opt/shadowsocks"
BIN="$App_dir/ssserver"
CONF="$App_dir/config.json"
SERVICE="$App_dir/shadowsocks.service"
UPGRADE_SERVICE="$App_dir/shadowsocks-upgrade.service"

SYSTEMD_SERVICE="/etc/systemd/system/shadowsocks.service"
SYSTEMD_UPGRADE_SERVICE="/etc/systemd/system/shadowsocks-upgrade.service"
SYSTEMD_UPGRADE_TIMER="/etc/systemd/system/shadowsocks-upgrade.timer"
SYSTEMD_RESTART_TIMER="/etc/systemd/system/shadowsocks-restart.timer"

mkdir -p "$App_dir"

install_tools() {
    apt update && apt install -y curl unzip jq
}

get_local_version() {
    if [ -x "$BIN" ]; then
        $BIN -V 2>/dev/null | awk '{print $2}'
    else
        echo "none"
    fi
}

get_latest_version() {
    curl -s https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest \
        | jq -r '.tag_name'
}

download_latest() {
    echo "🔍 获取最新版本..."
    LATEST_URL=$(curl -s https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest \
        | jq -r '.assets[] | select(.name | test("x86_64-unknown-linux-gnu.tar.xz$")) | .browser_download_url')

    echo "⬇️ 下载: $LATEST_URL"
    curl -L "$LATEST_URL" -o /tmp/ssr.tar.xz
    tar -xf /tmp/ssr.tar.xz -C /tmp
}

install_ss() {
    install_tools
    download_latest

    echo "📦 安装到 $App_dir"
    install -m 755 /tmp/ssserver "$BIN"

    # 默认配置
    cat > "$CONF" <<EOF
{
    "server": "::",
    "server_port": 20443,
    "password": "A9cF9aFFbB11c72c49fC10bDF0f75eeD",
    "method": "aes-128-gcm",
    "mode": "tcp_only"
}
EOF

    # 主服务文件
    cat > "$SERVICE" <<EOF
[Unit]
Description=Shadowsocks-Rust Server
After=network.target

[Service]
ExecStart=$BIN -c $CONF
Restart=on-failure
User=nobody
Group=nogroup
LimitNOFILE=32768

[Install]
WantedBy=multi-user.target
EOF

    ln -sf "$SERVICE" "$SYSTEMD_SERVICE"

    # 升级服务文件
    cat > "$UPGRADE_SERVICE" <<EOF
[Unit]
Description=Upgrade Shadowsocks-Rust

[Service]
Type=oneshot
ExecStart=$App_dir/shadowsocks-rust.sh -up
EOF

    ln -sf "$UPGRADE_SERVICE" "$SYSTEMD_UPGRADE_SERVICE"

    # 升级定时器
    cat > "$SYSTEMD_UPGRADE_TIMER" <<EOF
[Unit]
Description=Monthly upgrade for Shadowsocks-Rust

[Timer]
OnCalendar=monthly
Persistent=true

[Install]
WantedBy=timers.target
EOF

    # 每周重启定时器
    cat > "$SYSTEMD_RESTART_TIMER" <<EOF
[Unit]
Description=Weekly restart of Shadowsocks service

[Timer]
OnCalendar=weekly
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable --now shadowsocks
    systemctl enable --now shadowsocks-upgrade.timer
    systemctl enable --now shadowsocks-restart.timer

    echo "🎉 Shadowsocks 已安装并启动，自动升级和每周重启已启用"
}

upgrade_ss() {
    local_version=$(get_local_version)
    latest_version=$(get_latest_version)

    echo "本地版本:  $local_version"
    echo "最新版本:  $latest_version"

    if [ "$local_version" = "$latest_version" ]; then
        echo "⚡ 已是最新版本，无需升级"
        return
    fi

    echo "🔄 升级 Shadowsocks..."
    download_latest
    systemctl stop shadowsocks
    install -m 755 /tmp/ssserver "$BIN"
    systemctl start shadowsocks

    echo "🎉 已升级到版本 $latest_version"
}

update_conf_from_url() {
    url="$1"
    echo "📥 下载配置: $url"
    curl -L "$url" -o "$CONF"
    echo "✅ 配置文件已更新: $CONF"
    systemctl restart shadowsocks
    echo "🔄 Shadowsocks 服务已重启以应用新配置"
}

case "$1" in
    -up)
        upgrade_ss
        ;;
    -http://*|-https://*)
        update_conf_from_url "${1#-}"
        ;;
    *)
        install_ss
        ;;
esac
