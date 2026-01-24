#!/bin/bash
set -e

App_dir="/opt/shadowsocks"
mkdir -p "$App_dir"

SYSTEMD_SERVICE="/etc/systemd/system/shadowsocks.service"
SYSTEMD_UPGRADE_SERVICE="/etc/systemd/system/shadowsocks-upgrade.service"
SYSTEMD_UPGRADE_TIMER="/etc/systemd/system/shadowsocks-upgrade.timer"
SYSTEMD_RESTART_TIMER="/etc/systemd/system/shadowsocks-restart.timer"

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

    echo
