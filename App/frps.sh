#!/usr/bin/env bash
# frps.sh - 自动化安装/升级 frps 服务端
# 用法:
#   ./frps.sh        # 安装
#   ./frps.sh -up    # 升级

set -euo pipefail

REPO="fatedier/frp"
FRPS_DIR="/opt/frps"

# ===== 获取最新版本号 =====
get_latest_release() {
    curl -s https://api.github.com/repos/$REPO/releases/latest \
    | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/'
}

# ===== 下载并安装 frps =====
install_frps() {
    mkdir -p "$FRPS_DIR"
    cd "$FRPS_DIR"

    VERSION=$(get_latest_release)
    echo "最新版本: $VERSION"

    URL="https://github.com/$REPO/releases/download/v${VERSION}/frp_${VERSION}_linux_amd64.tar.gz"
    curl -L "$URL" -o frp.tar.gz
    tar -xzf frp.tar.gz --strip-components=1
    rm -f frp.tar.gz

    # 默认配置
    if [[ ! -f "$FRPS_DIR/frps.ini" ]]; then
        cat > "$FRPS_DIR/frps.ini" <<EOF
[common]
bind_port = 7000
dashboard_port = 7500
dashboard_user = admin
dashboard_pwd = admin
EOF
    fi

    # systemd service
    cat > /etc/systemd/system/frps.service <<EOF
[Unit]
Description=frps service
After=network.target

[Service]
ExecStart=$FRPS_DIR/frps -c $FRPS_DIR/frps.ini
Restart=always
User=nobody
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reexec
    systemctl enable frps
    systemctl restart frps
    echo "frps 已安装并启动"
}

# ===== 升级 frps =====
upgrade_frps() {
    echo "开始升级 frps..."
    install_frps
    echo "frps 已升级到最新版本"
}

# ===== 配置定时更新 =====
setup_timer() {
    # 升级 service
    cat > /etc/systemd/system/frps-up.service <<EOF
[Unit]
Description=Upgrade frps to latest version

[Service]
Type=oneshot
ExecStart=$FRPS_DIR/frps.sh -up
EOF

    # 每月执行一次
    cat > /etc/systemd/system/frps-up.timer <<EOF
[Unit]
Description=Monthly frps upgrade

[Timer]
OnCalendar=monthly
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reexec
    systemctl enable frps-up.timer
    systemctl start frps-up.timer
    echo "frps 每月自动升级已配置完成"
}

# ===== 主逻辑 =====
if [[ "${1:-}" == "-up" ]]; then
    upgrade_frps
else
    install_frps
    setup_timer
fi
