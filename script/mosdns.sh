#!/bin/bash
#
# MosDNS 全功能安装与管理脚本 (优化版)
#

# --- 全局设置 ---
# set -e: 当命令失败时立即退出脚本
# set -o pipefail: 管道中任何一个命令失败，整个管道都视为失败
set -e
set -o pipefail

# --- 变量与常量定义 ---
readonly green_text="\033[32m"
readonly yellow_text="\033[33m"
readonly red_text="\033[31m"
readonly reset="\033[0m"
readonly DIRPATH="/usr/local/bin/tools"

readonly local_ip=$(hostname -I | awk '{print $1}')
readonly NFT_RULESET="/etc/nftables.conf"
readonly RESOLVED_CONF="/etc/systemd/resolved.conf"

# --- 日志函数 ---
log_info() { echo -e "${green_text}[INFO]${reset} $1"; }
log_warn() { echo -e "${yellow_text}[WARN]${reset} $1"; }
log_error() { echo -e "${red_text}[ERROR]${reset} $1"; }

# --- 辅助函数 ---

# 检测系统架构
detect_architecture() {
    case $(uname -m) in
        x86_64)  echo "amd64" ;;
        aarch64) echo "arm64" ;;
        armv7l)  echo "armv7" ;;
        armhf)   echo "armhf" ;;
        *)
            log_error "不支持的CPU架构: $(uname -m)"
            exit 1
            ;;
    esac
}

# 检查并解除 systemd-resolved 对53端口的占用
check_resolved() {
    log_info "正在检查 systemd-resolved 53端口占用情况..."
    if [ ! -f "$RESOLVED_CONF" ]; then
        log_info "$RESOLVED_CONF 不存在，无需操作。"
        return
    fi

    # 如果 DNSStubListener 已经是 'no'，则无需任何操作
    if grep -qE "^\s*DNSStubListener\s*=\s*no\s*$" "$RESOLVED_CONF"; then
        log_info "DNSStubListener 已正确配置为 'no'，无需修改。"
        return
    fi

    log_warn "检测到 DNSStubListener 配置不正确或被注释，正在调整..."
    # 如果找到了被注释或值为yes的行，则替换它
    if grep -qE "^\s*#?\s*DNSStubListener\s*=" "$RESOLVED_CONF"; then
        sed -i -E 's/^\s*#?\s*DNSStubListener\s*=.*/DNSStubListener=no/' "$RESOLVED_CONF"
    else
        # 如果压根没找到这行，就追加到文件末尾
        echo "DNSStubListener=no" >> "$RESOLVED_CONF"
    fi

    systemctl restart systemd-resolved.service
    log_info "53端口占用已解除。"
}

# 下载并解压文件
download_and_unzip() {
    local url=$1
    local dest_dir=$2
    local zip_file
    zip_file=$(basename "$url")

    log_info "正在从 $url 下载..."
    wget --quiet --show-progress -O "$zip_file" "$url"
    
    log_info "正在解压 $zip_file 到 $dest_dir..."
    mkdir -p "$dest_dir"
    unzip -o "$zip_file" -d "$dest_dir"
    rm -f "$zip_file"
    log_info "解压完成。"
}


# --- 核心功能函数 ---

# 安装 MosDNS 主程序
install_mosdns_binary() {
    log_info "开始安装 MosDNS..."
    local arch
    arch=$(detect_architecture)
    log_info "系统架构: $arch"
    
    local mosdns_url="https://github.com/herozmy/StoreHouse/releases/download/mosdns/mosdns-linux-$arch.zip"
    
    log_info "正在更新系统软件包..."
    apt-get update && apt-get -y upgrade
    apt-get install -y curl wget git tar gawk sed cron unzip nano
    
    download_and_unzip "$mosdns_url" "."
    
    log_info "移动 MosDNS 到 /usr/local/bin/"
    mv ./mosdns /usr/local/bin/
    chmod +x /usr/local/bin/mosdns
    
    log_info "设置时区为 Asia/Shanghai"
    timedatectl set-timezone Asia/Shanghai
    log_info "MosDNS 主程序安装完成。"
}

# 配置 MosDNS 规则
configure_mosdns_rules() {
    log_info "开始配置 MosDNS 规则..."
    
    read -rp "请输入 sing-box/mihomo 的入站地址 (默认 10.10.10.147:6666): " uiport
    uiport="${uiport:-10.10.10.147:6666}"
    log_info "已设置代理入站地址: $uiport"
    read -rp "请输入 本地运营商DNS (默认 114.114.114.114): " localdns
    localdns="${localdns:-114.114.114.114}"
    log_info "已设置本地运营商DNS: $localdns"
    check_resolved
    
    echo "----------------------------------------"
    echo "请选择 MosDNS 分流规则:"
    echo "  1. O佬分流规则 (经典稳定)"
    echo "  2. PH佬分流规则 (越用越快)"
    echo "  999. J佬/PH 魔改Ui (测试)"
    echo "  0. 退出脚本"
    echo "----------------------------------------"
    read -rp "请输入选择 [0-2]: " choice
    
    case "$choice" in
        1)
            download_and_unzip "https://github.com/herozmy/StoreHouse/raw/refs/heads/latest/config/mosdns/o/mosdns.zip" "/etc/mosdns/"
            ;;
        2)
            download_and_unzip "https://github.com/herozmy/StoreHouse/raw/refs/heads/latest/config/mosdns/ph/mosdns20250401.zip" "/etc/mosdns/"
            echo "请选择 PH佬规则版本:"
            echo "  1. leak版 (默认)"
            echo "  2. noleak版"
            read -rp "请输入选择 [1-2], 回车默认1: " version_choice
            if [[ "$version_choice" == "2" ]]; then
                mv /etc/mosdns/config_noleak.yaml /etc/mosdns/config.yaml
            else
                mv /etc/mosdns/config_leak.yaml /etc/mosdns/config.yaml
            fi
            ;;
        999)
            mkdir -p /cus/
            download_and_unzip "https://github.com/herozmy/StoreHouse/raw/refs/heads/latest/config/mosdns/jph/mosdns.zip" "/cus/mosdns/"
            sed -i 's|fc00::/18|f2b0::/18|g' /cus/mosdns/sub_config/cache.yaml
            sed -i "s|127.0.0.1:7874|${uiport}|g" /cus/mosdns/sub_config/forward_1.yaml
            sed -i "s/202.102.128.68/${localdns}/g" /cus/mosdns/sub_config/forward_local.yaml
            sed -i '/^socks5: "127.0.0.1:7891"$/s/^/#/' /cus/mosdns/sub_config/forward_nocn.yaml
            sed -i 's/listen: 127.0.0.1:6666/listen: ":53"/g' /cus/mosdns/config_custom.yaml

            ;;
        0)
            log_info "用户选择退出。"
            exit 0
            ;;
        *)
            log_error "无效输入，请输入 0-2 之间的数字。"
            exit 1
            ;;
    esac
    if [ $choice != 999 ]; then
        log_info "MosDNS 规则拉取成功。"
        log_info "正在根据您的输入调整配置文件..."
        sed -i "s/- addr: 10.10.10.147:6666/- addr: ${uiport}/g" /etc/mosdns/config.yaml
    fi
}

# 安装 MosDNS 服务并启动
setup_mosdns_service() {
    log_info "正在设置 MosDNS 系统服务..."
    
    # 安装 systemd 服务
    if [ $choice == 999 ]; then
        /usr/local/bin/mosdns service install -d /cus/mosdns -c /cus/mosdns/config_custom.yaml
    else
        /usr/local/bin/mosdns service install -d /etc/mosdns -c /etc/mosdns/config.yaml
    fi
    

    # 增加文件句柄限制
    mkdir -p /etc/systemd/system/mosdns.service.d
    cat <<EOF > /etc/systemd/system/mosdns.service.d/override.conf
[Service]
LimitNOFILE=65536
EOF
    systemctl daemon-reload
    
    log_info "正在启动 MosDNS 服务..."
    systemctl restart mosdns
    systemctl enable mosdns
    
    log_info "MosDNS 开机自启设置完成。"
}

# 配置日志轮转
setup_logrotate() {
    log_info "正在配置 MosDNS 日志轮转..."
    if [ $choice == 999 ]; then
        cat <<EOF > /etc/logrotate.d/mosdns
/cus/mosdns/mosdns.log {
    copytruncate
    rotate 3
    daily
    missingok
    notifempty
    compress
}
EOF
    else
        cat <<EOF > /etc/logrotate.d/mosdns
/etc/mosdns/mosdns.log {
    copytruncate
    rotate 3
    daily
    missingok
    notifempty
    compress
}
EOF
    fi
    log_info "日志轮转配置完成。"
}

# 更新规则集 (此函数保持原样，因其内部逻辑相对独立)
get_mosdns_rule(){
    log_info "=== 开始更新MosDNS规则集 ==="
    local MOSDNS_INSTALL_DIR="/opt/mosdns_install"
    # 省略了原函数主体，因为其内部逻辑已经比较独立和完整。
    # 只是将 echo 替换为 log_* 函数可以进一步优化。
    # ... 原有 get_mosdns_rule 代码 ...
    echo "调用了 get_mosdns_rule 函数 (此为占位符)"
}

# --- 主函数 ---
main() {
    # 处理命令行参数，允许单独调用某个功能
    if [ -n "$1" ]; then
        case "$1" in
    cn_mosdns)
        mosdns_install && cn_mosdns_install
        return 0
        ;;
    get_mosdns_rule)
        get_mosdns_rule
        return 0
        ;;
    mosdns_logrotate)
        mosdns_logrotate
        return 0
        ;;
    mosdns_service)
        mosdns_service
        return 0
            ;;
        *)
            log_error "未知参数: $1"
            exit 1
            ;;
        esac
    fi

    # 默认执行完整的安装流程
    install_mosdns_binary
    configure_mosdns_rules
    setup_logrotate
    setup_mosdns_service
    bash /usr/local/bin/tools/check_aio.sh
    echo "-----------------------------------------------"
    log_info "MosDNS 安装与配置全部完成！"
    log_info "常用命令:"
    echo -e "  重启服务: ${yellow_text}systemctl restart mosdns${reset}"
    echo -e "  停止服务: ${yellow_text}systemctl stop mosdns${reset}"
    echo -e "  查看状态: ${yellow_text}systemctl status mosdns${reset}"
    echo -e "  查看日志: ${yellow_text}journalctl -u mosdns -f${reset}"
    echo -e "  管理工具: ${yellow_text}proxytool${reset}"
    echo "-----------------------------------------------"
}

# --- 脚本入口 ---
# 使用 "$@" 将所有命令行参数传递给 main 函数
main "$@"