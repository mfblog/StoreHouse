#!/bin/bash
#
# MosDNS - 独立安装与管理脚本 (最终优化完整版)
#
# 功能: 提供 MosDNS 的完整安装、规则配置、服务管理以及命令行工具功能。
#

# --- 严格模式与安全设置 ---
#set -e
#set -o pipefail

# --- 引入通用工具库 ---
# 加载包含日志函数和颜色定义的共享脚本，实现代码复用。
readonly COMMON_UTILS_PATH="/usr/local/bin/tools/common.sh"
if [ -f "$COMMON_UTILS_PATH" ]; then
    source "$COMMON_UTILS_PATH"
else
    # 如果找不到依赖库，打印清晰的错误信息并退出。
    echo -e "\033[31m✖ 致命错误: 依赖库缺失: $COMMON_UTILS_PATH\033[0m" >&2
    exit 1
fi

# --- 全局常量 ---
readonly NFT_RULESET_PATH="/etc/nftables.conf"
# 定义两种可能的配置文件路径
readonly MOSDNS_PATH_DEFAULT="/etc/mosdns"
readonly MOSDNS_PATH_CUSTOM="/cus/mosdns"

# --- 主调度器 (脚本入口) ---
main() {
    # 根据传入的第一个命令行参数 ($1)，决定执行哪个任务。
    case "$1" in
        cn_mosdns)         task_cn_mosdns ;;
        get_mosdns_rule)   task_get_mosdns_rule ;;
        mosdns_logrotate)  task_setup_logrotate_mosdns ;;
        mosdns_service)    task_setup_service_mosdns ;;
        *)                 task_install_mosdns ;;
    esac
}

# ==============================================================================
# SECTION: 任务层 (Tasks) - 由主调度器触发的高级功能组合
# ==============================================================================

# 任务：执行 MosDNS 的完整安装流程
task_install_mosdns() {
    log_info "开始 MosDNS 完整安装流程..."
    
    install_dependencies
    install_mosdns_binary
    configure_mosdns_rules # 此函数会创建配置文件，为后续任务提供路径检测依据
    task_setup_logrotate_mosdns
    task_setup_service_mosdns
    
    log_success "=================================================================="
    log_success "  MosDNS 安装完毕!"
    log_success "  技术支持: www.herozmy.com 2025"
    log_success "=================================================================="
    print_service_commands
}

# 任务：安装 "cn佬" 的嵌套规则
task_cn_mosdns() {
    log_info "正在执行 'cn_mosdns' 安装任务..."
    install_dependencies
    install_mosdns_binary
    install_cn_mosdns_rules
    log_success "'cn_mosdns' 任务完成。"
}

# 任务：更新 MosDNS 使用的远程规则集
task_get_mosdns_rule() {
    log_info "开始更新 MosDNS 规则集..."
    update_mosdns_rulesets
    log_success "MosDNS 规则集更新完成。"
}

# 任务：配置 MosDNS 的日志轮转 (优化版)
task_setup_logrotate_mosdns() {
    log_info "正在配置 MosDNS 日志轮转..."

    local log_file_path="${MOSDNS_PATH_DEFAULT}/mosdns.log"
    # 自动检测应使用哪个路径
    if [ -d "$MOSDNS_PATH_CUSTOM" ]; then
        log_file_path="${MOSDNS_PATH_CUSTOM}/mosdns.log"
        log_info "检测到自定义路径，日志文件设置为: $log_file_path"
    fi

    cat <<EOF > /etc/logrotate.d/mosdns
${log_file_path} {
    copytruncate
    rotate 3
    daily
    missingok
    notifempty
    compress
}
EOF
    task_crontab
}
task_crontab() {
    log_info "正在设置 MosDNS 定时任务..."
    CRON_JOB="57 23 * * * /usr/sbin/logrotate -f /etc/logrotate.d/mosdns"
    JOB_CHECK_STRING="/usr/sbin/logrotate -f /etc/logrotate.d/mosdns"
    CURRENT_CRONTAB=$(crontab -l 2>/dev/null)
    if ! echo "${CURRENT_CRONTAB}" | grep -Fq "${JOB_CHECK_STRING}"; then
        (echo "${CURRENT_CRONTAB}"; echo "${CRON_JOB}") | crontab -
    else
        log_info "定时任务已存在，无需重复设置。"
    fi
    log_success "MosDNS 定时任务配置完成。"
}
# 任务：安装并启动 MosDNS 系统服务 (优化版)
task_setup_service_mosdns() {
    log_info "正在设置并启动 MosDNS 服务..."

    local work_dir="$MOSDNS_PATH_DEFAULT"
    local config_file="${work_dir}/config.yaml"
    # 自动检测应使用哪个路径
    if [ -d "$MOSDNS_PATH_CUSTOM" ] && [ -f "${MOSDNS_PATH_CUSTOM}/config_custom.yaml" ]; then
        work_dir="$MOSDNS_PATH_CUSTOM"
        config_file="${work_dir}/config_custom.yaml"
        log_info "检测到自定义UI路径，使用配置: $config_file"
    fi
    
    # 使用 mosdns 内置命令安装服务
    /usr/local/bin/mosdns service install -d "$work_dir" -c "$config_file"
    
    # 增加文件句柄限制
    mkdir -p /etc/systemd/system/mosdns.service.d
    cat <<EOF > /etc/systemd/system/mosdns.service.d/override.conf
[Service]
LimitNOFILE=65536
EOF
    systemctl daemon-reload
    
    systemctl restart mosdns
    log_success "MosDNS 服务已启动并设置为开机自启。"
    
    # 在服务启动后检查AIO环境
    bash /usr/local/bin/tools/check_aio.sh
    
    print_service_commands
}


# ==============================================================================
# SECTION: 辅助与核心函数 (Helpers & Core Logic)
# ==============================================================================

install_dependencies() {
    log_info "正在更新软件包列表并安装依赖..."
    # 优化点：移除 upgrade，避免不必要的系统升级
    apt-get update
    apt-get -y install curl wget git tar gawk sed cron unzip nano nftables
    log_info "正在设置时区为 Asia/Shanghai..."
    timedatectl set-timezone Asia/Shanghai
    log_success "依赖安装和时区设置完成。"
}

detect_architecture() {
    case $(uname -m) in
        x86_64)  echo "amd64" ;;
        aarch64) echo "arm64" ;;
        armv7l)  echo "armv7" ;;
        *) log_error "不支持的CPU架构: $(uname -m)"; exit 1 ;;
    esac
}

install_mosdns_binary() {
    log_info "正在安装 MosDNS 主程序..."
    local arch
    arch=$(detect_architecture)
    log_info "检测到系统架构: $arch"
    
    local mosdns_url="https://github.com/herozmy/StoreHouse/releases/download/mosdns/mosdns-linux-${arch}.zip"
    
    local temp_file
    temp_file=$(mktemp)
    trap 'rm -f "$temp_file"' RETURN

    log_info "正在下载 MosDNS..."
    if ! wget -q --show-progress -O "$temp_file" "$mosdns_url"; then
        log_error "下载 MosDNS 失败，URL: $mosdns_url"
        exit 1
    fi
    
    unzip -o "$temp_file" -d /usr/local/bin/
    chmod +x /usr/local/bin/mosdns
    
    log_success "MosDNS 主程序已安装至 /usr/local/bin/mosdns"
}

configure_mosdns_rules() {
    log_info "开始交互式配置 MosDNS 规则..."
    
    read -rp "请输入 sing-box/mihomo 的入站地址 (默认 10.10.10.147:6666): " uiport
    uiport="${uiport:-10.10.10.147:6666}"
    read -rp "请输入 本地运营商DNS (默认 114.114.114.114): " localdns
    localdns="${localdns:-114.114.114.114}"
    
    log_info "已设置代理入站地址: $uiport"
    log_info "已设置本地运营商DNS: $localdns"
    check_resolved_port53
    
    echo
    log_info "请选择要使用的 MosDNS 分流规则:"
    echo "  1. O佬分流规则 (经典稳定)"
    echo "  2. PH佬分流规则 (越用越快)"
    echo "  999. J佬/PH 魔改Ui (测试)"
    echo "  0. 退出"
    read -rp "请输入您的选择 [1,2,999,0]: " choice
    
    local config_url=""
    local dest_dir="$MOSDNS_PATH_DEFAULT"
    case "$choice" in
        1) config_url="https://github.com/herozmy/StoreHouse/raw/refs/heads/latest/config/mosdns/o/mosdns.zip" ;;
        2) config_url="https://github.com/herozmy/StoreHouse/raw/refs/heads/latest/config/mosdns/ph/mosdns20250401.zip" ;;
        999)
            dest_dir="$MOSDNS_PATH_CUSTOM"
            config_url="https://github.com/herozmy/StoreHouse/raw/refs/heads/latest/config/mosdns/jph/mosdns.zip"
            ;;
        0) log_warn "操作已取消。"; return ;;
        *) log_error "无效的选择。"; exit 1 ;;
    esac

    mkdir -p "$dest_dir"
    local temp_zip
    temp_zip=$(mktemp)
    trap 'rm -f "$temp_zip"' RETURN
    log_info "正在下载规则包..."
    if ! wget -q --show-progress -O "$temp_zip" "$config_url"; then
        log_error "下载规则包失败，URL: $config_url"
        exit 1
    fi
    unzip -o "$temp_zip" -d "$dest_dir/"
    
    if [ "$choice" == "2" ]; then
        log_info "请选择 PH佬规则的具体版本:"
        echo "  1. leak版 (默认)"
        echo "  2. noleak版"
        read -rp "请输入您的选择 [1-2], 回车默认为1: " version_choice
        if [ "$version_choice" == "2" ]; then
            mv -f "${dest_dir}/config_noleak.yaml" "${dest_dir}/config.yaml"
        else
            mv -f "${dest_dir}/config_leak.yaml" "${dest_dir}/config.yaml"
        fi        
    fi
    
    log_success "MosDNS 规则已成功拉取。"
    log_info "正在根据您的输入适配配置文件..."
    if [ "$choice" == "999" ]; then
        sed -i 's|fc00::/18|f2b0::/18|g' "${dest_dir}/sub_config/cache.yaml"
        sed -i "s|127.0.0.1:7874|${uiport}|g" "${dest_dir}/sub_config/forward_1.yaml"
        sed -i "s/202.102.128.68/${localdns}/g" "${dest_dir}/sub_config/forward_local.yaml"
        sed -i '/^[[:space:]]*socks5: "127.0.0.1:7891"$/s/^[[:space:]]*/\#&/' "${dest_dir}/sub_config/forward_nocn.yaml"
        sed -i '/^[[:space:]]*socks5: "127.0.0.1:7891"$/s/^[[:space:]]*/\#&/' "${dest_dir}/sub_config/forward_nocn_ecs.yaml"
        sed -i 's|/tmp/mosdns|/cus/mosdns/mosdns|g' /cus/mosdns/config_custom.yaml
        sed -i 's/listen: 127.0.0.1:6666/listen: ":53"/' "${dest_dir}/config_custom.yaml"

    else
        sed -i "s/- addr: 10.10.10.147:6666/- addr: ${uiport}/g" "${dest_dir}/config.yaml"
    fi
    log_success "配置文件适配完成。"
}

install_cn_mosdns_rules() {
    log_info "正在安装 'cn佬' 的 MosDNS 嵌套规则..."
    local url="https://github.com/herozmy/StoreHouse/raw/refs/heads/latest/config/mosdns/cn_mosdns/cn_mosdns.zip"
    
    local temp_zip
    temp_zip=$(mktemp)
    trap 'rm -f "$temp_zip"' RETURN
    
    log_info "正在下载规则包..."
    wget -q --show-progress -O "$temp_zip" "$url"
    
    mkdir -p "$MOSDNS_PATH_DEFAULT"
    unzip -o "$temp_zip" -d "$MOSDNS_PATH_DEFAULT/"
    log_success "'cn佬' 规则安装完成。"
}

update_mosdns_rulesets() {
    local -A RULESET_URLS=(
        ["geosite_cn.txt"]="https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/direct-list.txt"
        ["geosite_no_cn.txt"]="https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/proxy-list.txt"
        ["gfw.txt"]="https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/gfw.txt"
        ["ChinaAllNetwork_IPv4.txt"]="https://file.bairuo.net/iplist/output/Aggregated_ChinaAllNetwork_IPv4.txt"
        ["ChinaAllNetwork_IPv6.txt"]="https://file.bairuo.net/iplist/output/Aggregated_ChinaAllNetwork_IPv6.txt"
        ["ChinaEducation_IPv4.txt"]="https://file.bairuo.net/iplist/output/Aggregated_ChinaEducation_IPv4.txt"
        ["ChinaEducation_IPv6.txt"]="https://file.bairuo.net/iplist/output/Aggregated_ChinaEducation_IPv6.txt"
        ["ChinaMobile_IPv4.txt"]="https://file.bairuo.net/iplist/output/Aggregated_ChinaMobile_IPv4.txt"
        ["ChinaMobile_IPv6.txt"]="https://file.bairuo.net/iplist/output/Aggregated_ChinaMobile_IPv6.txt"
        ["ChinaSciences_IPv4.txt"]="https://file.bairuo.net/iplist/output/Aggregated_ChinaSciences_IPv4.txt"
        ["ChinaSciences_IPv6.txt"]="https://file.bairuo.net/iplist/output/Aggregated_ChinaSciences_IPv6.txt"
        ["ChinaTelecom_IPv4.txt"]="https://file.bairuo.net/iplist/output/Aggregated_ChinaTelecom_IPv4.txt"
        ["ChinaTelecom_IPv6.txt"]="https://file.bairuo.net/iplist/output/Aggregated_ChinaTelecom_IPv6.txt"
        ["ChinaUnicom_IPv4.txt"]="https://file.bairuo.net/iplist/output/Aggregated_ChinaUnicom_IPv4.txt"
        ["ChinaUnicom_IPv6.txt"]="https://file.bairuo.net/iplist/output/Aggregated_ChinaUnicom_IPv6.txt"
    )
    
    local temp_dir
    temp_dir=$(mktemp -d)
    trap 'rm -rf "$temp_dir"' RETURN

    log_info "开始从网络下载所有规则文件到临时目录..."
    for filename in "${!RULESET_URLS[@]}"; do
        local url="${RULESET_URLS[$filename]}"
        echo "  -> 下载中: $filename"
        if ! curl -sSL --retry 3 --connect-timeout 30 -o "${temp_dir}/${filename}" "$url" || [ ! -s "${temp_dir}/${filename}" ]; then
            log_warn "下载失败或文件为空: $filename. 将继续尝试其他文件。"
        fi
    done
    log_success "所有规则文件下载尝试完成。"
    
    log_info "正在合并 IP 文件..."
    find "$temp_dir" -name "*IPv4.txt" -type f -exec cat {} + > "${temp_dir}/geoip_cn_v4.txt"
    find "$temp_dir" -name "*IPv6.txt" -type f -exec cat {} + > "${temp_dir}/geoip_cn_v6.txt"
    cat "${temp_dir}/geoip_cn_v4.txt" "${temp_dir}/geoip_cn_v6.txt" > "${temp_dir}/geoip_cn.txt"
    
    log_info "正在将规则文件部署到 $MOSDNS_PATH_DEFAULT ..."
    mkdir -p "$MOSDNS_PATH_DEFAULT"
    # 使用 find 安全地复制文件，即使源文件不存在也不会报错
    find "$temp_dir" -maxdepth 1 -type f -name "*.txt" -not -name "*IPv[46]*" -not -name "geoip_cn_v4.txt" -not -name "geoip_cn_v6.txt" -exec cp -v {} "$MOSDNS_PATH_DEFAULT/" \;
    if [ -s "${temp_dir}/geoip_cn.txt" ]; then
        cp -v "${temp_dir}/geoip_cn.txt" "$MOSDNS_PATH_DEFAULT/"
    else
        log_warn "合并后的 geoip_cn.txt 为空，未部署。"
    fi
    
    log_success "规则集更新并部署完成。"
}

check_resolved_port53() {
    log_info "正在检查 systemd-resolved 对 53 端口的占用情况..."
    local conf_file="/etc/systemd/resolved.conf"
    if [ ! -f "$conf_file" ]; then
        log_info "$conf_file 不存在，无需操作。"
        return
    fi
    if grep -qE "^\s*DNSStubListener\s*=\s*no\s*$" "$conf_file"; then
        log_success "DNSStubListener 已正确配置为 'no'。"
        return
    fi
    log_warn "DNSStubListener 配置需要调整，正在修改..."
    if ! grep -qE "^\s*#?\s*DNSStubListener\s*=" "$conf_file"; then
        echo "DNSStubListener=no" >> "$conf_file"
    else
        sed -i -E 's/^\s*#?\s*DNSStubListener\s*=.*/DNSStubListener=no/' "$conf_file"
    fi
    systemctl restart systemd-resolved.service
    log_success "53 端口冲突已解决。"
}

task_check_aio_and_apply_rules() {
    log_info "正在检测 AIO 环境 (MosDNS与代理核心共存)..."
    
    if ! [ -f "$NFT_RULESET_PATH" ]; then
        log_warn "nftables 配置文件不存在 ($NFT_RULESET_PATH)，跳过AIO规则检查。"
        return
    fi
    
    if [ -x "/usr/local/bin/mosdns" ] && { [ -x "/usr/local/bin/sing-box" ] || [ -x "/usr/local/bin/mihomo" ]; }; then
        log_warn "检测到DNS与代理核心共存，需要调整防火墙规则。"
        
        # 优化点：使用专门的标记作为锚点，更可靠
        local nft_bak_path="$NFT_RULESET_PATH.bak_$(date +%F-%T)"
        cp "$NFT_RULESET_PATH" "$nft_bak_path" 
        log_info "已备份当前防火墙配置到: $nft_bak_path"

        # 1. 先安全地删除旧的规则块，防止重复
        sed -i '/# MOSDNS_AIO_RULES_BEGIN/,/# MOSDNS_AIO_RULES_END/d' "$NFT_RULESET_PATH"

        # 2. 定义新的规则块
        read -r -d '' aio_rules <<'EOF'
      # MOSDNS_AIO_RULES_BEGIN
      # Rules for MosDNS to bypass proxy in AIO mode
      223.5.5.5, 223.6.6.6,                                 # AliDNS
      2400:3200::1, 2400:3200:baba::1,                       # AliDNS IPv6
      119.29.29.29, 182.254.116.116,                         # DNSPod
      2402:4e00::,                                           # DNSPod IPv6
      # MOSDNS_AIO_RULES_END
EOF
        
        # 3. 将规则块插入到正确的锚点之后 (这里假设在 `define lan_ip` 块中)
        # 如果找不到锚点，则报错
        if ! grep -q "define lan_ip = {" "$NFT_RULESET_PATH"; then
             log_error "在 $NFT_RULESET_PATH 中未找到 'define lan_ip' 锚点，无法自动添加规则。"
             log_error "请手动将 AliDNS 和 DNSPod 的 IP 添加到直连列表，或恢复备份: $nft_bak_path"
             exit 1
        fi
        sed -i "/define lan_ip = {/a ${aio_rules}" "$NFT_RULESET_PATH"
        
        log_info "正在验证并应用新的防火墙规则..."
        if nft -c -f "$NFT_RULESET_PATH"; then
            nft flush ruleset
            nft -f "$NFT_RULESET_PATH"
            log_success "AIO 防火墙规则已成功应用。"
            if systemctl is-active --quiet "tproxy-router"; then
                log_info "正在重启 tproxy-router 服务以应用新规则..."
                systemctl restart "tproxy-router"
            fi
            rm -f "$nft_bak_path"
        else
            log_error "新的防火墙配置无效！已自动从备份回滚。"
            mv "$nft_bak_path" "$NFT_RULESET_PATH"
            exit 1
        fi
    else
        log_info "未检测到 AIO 环境，无需修改防火墙规则。"
    fi
}

# --- 帮助与收尾函数 ---

print_help() {
    echo "用法: $0 [命令]"
    echo "可用命令:"
    echo "  install (默认)     - 执行完整的 MosDNS 安装流程"
    echo "  cn_mosdns          - 安装 'cn佬' 的嵌套规则"
    echo "  get_mosdns_rule    - 更新远程规则集"
    echo "  mosdns_logrotate   - 仅设置日志轮转"
    echo "  mosdns_service     - 仅安装系统服务"
    echo "  check_aio          - 检查并应用AIO防火墙规则"
    echo "  help, -h, --help   - 显示此帮助信息"
}

print_service_commands() {
    log_info "常用管理命令:"
    echo "  systemctl restart mosdns"
    echo "  systemctl status mosdns"
    echo "  journalctl -u mosdns -f"
    echo "  使用 'proxytool' 命令进行快速管理。"
}


# --- 脚本执行入口 ---
main "$@"
