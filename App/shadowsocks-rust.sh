#!/bin/bash
set -e

App_dir="/opt/shadowsocks"
mkdir -p "$App_dir"

SYSTEMD_SERVICE="/etc/systemd/system/shadowsocks.service"
SYSTEMD_UPGRADE_SERVICE="/etc/systemd/system/shadowsocks-upgrade.service"
SYSTEMD_UPGRADE_TIMER="/etc/systemd/system/shadowsocks-upgrade.timer"
SYSTEMD_RESTART_TIMER="/etc/systemd/system/shadowsocks-restart.timer"

# -------------------------
# 系统检查
# -------------------------
check_system() {
    echo "🔍 检查系统环境..."

    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64) ARCH="x86_64" ;;
        aarch64|arm64) ARCH="aarch64" ;;
        armv7l|armhf) ARCH="armv7" ;;
        *)
            echo "❌ 不支持的 CPU 架构: $ARCH"
            exit 1
            ;;
    esac
    echo "✔ CPU 架构: $ARCH"

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME=$ID
        OS_VER=$VERSION_ID
    else
        echo "❌ 无法检测系统版本"
        exit 1
    fi

    case "$OS_NAME" in
        debian|ubuntu) echo "✔ 系统: $OS_NAME $OS_VER" ;;
        *)
            echo "❌ 不支持的系统: $OS_NAME"
            exit 1
            ;;
    esac

    if [ "$OS_NAME" = "debian" ] && [ "${OS_VER%%.*}" -lt 10 ]; then
        echo "❌ Debian 版本过低，需要 Debian 10+"
        exit 1
    fi

    if [ "$OS_NAME" = "ubuntu" ] && [ "${OS_VER%%.*}" -lt 20 ]; then
        echo "❌ Ubuntu 版本过低，需要 Ubuntu 20+"
        exit 1
    fi

    echo "🎉 系统环境检查通过"
}

install_tools() {
    apt update && apt install -y curl unzip jq
}

get_local_version() {
    if [ -x "$App_dir/ssserver" ]; then
        "$App_dir/ssserver" -V 2>/dev/null | awk '{print $2}'
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

    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64) ARCH="x86_64" ;;
        aarch64|arm64) ARCH="aarch64" ;;
        armv7l|armhf) ARCH="armv7" ;;
    esac

    URL=$(curl -s https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest \
        | jq -r ".assets[] | select(.name | test(\"$ARCH-unknown-linux-gnu.tar.xz$\")) | .browser_download_url")

    echo "⬇️ 下载: $URL"
    curl -L "$URL" -o /tmp/ssr.tar.xz
    tar -xf /tmp/ssr.tar.xz -C /tmp
}

install_ss() {
    check_system
    install_tools
    download_latest

    install -m 755 /tmp/ssserver "$App_dir/ssserver"

    cat > "$App_dir/config.json" <<EOF
{
    "server": "::",
    "server_port": 20443,
    "password": "A9cF9aFFbB11c72c49fC10bDF0f75eeD",
    "method": "aes-128-gcm",
    "mode": "tcp_only"
}
EOF

    cat > "$App_dir/shadowsocks.service" <<EOF
[Unit]
Description=Shadowsocks-Rust Server
After=network.target

[Service]
ExecStart=$App_dir/ssserver -c $App_dir/config.json
Restart=on-failure
User=nobody
Group=nogroup
LimitNOFILE=32768

[Install]
WantedBy=multi-user.target
EOF

    ln -sf "$App_dir/shadowsocks.service" "$SYSTEMD_SERVICE"

    cat > "$App_dir/shadowsocks-upgrade.service" <<EOF
[Unit]
Description=Upgrade Shadowsocks-Rust

[Service]
Type=oneshot
ExecStart=$App_dir/shadowsocks-rust.sh -up
EOF

    ln -sf "$App_dir/shadowsocks-upgrade.service" "$SYSTEMD_UPGRADE_SERVICE"

    cat > "$SYSTEMD_UPGRADE_TIMER" <<EOF
[Unit]
Description=Monthly upgrade for Shadowsocks-Rust

[Timer]
OnCalendar=monthly
Persistent=true

[Install]
WantedBy=timers.target
EOF

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

    echo "🎉 Shadowsocks 已安装并启动，自动升级与每周重启已启用"
}

upgrade_ss() {
    check_system

    local_version=$(get_local_version)
    latest_version=$(get_latest_version)

    echo "本地版本:  $local_version"
    echo "最新版本:  $latest_version"

    if [ "$local_version" = "$latest_version" ]; then
        echo "⚡ 已是最新版本，无需升级"
        return
    fi

    download_latest
    systemctl stop shadowsocks
    install -m 755 /tmp/ssserver "$App_dir/ssserver"
    systemctl start shadowsocks

    echo "🎉 已升级到版本 $latest_version"
}

update_conf_from_url() {
    url="$1"
    echo "📥 下载配置: $url"
    curl -L "$url" -o "$App_dir/config
