#!/bin/bash
#
# Sing-Box & MosDNS & Mihomo 多功能一体化管理脚本
# 版本: 1.2
# 作者: herozmy
# 最后更新: 2024-04-21
#

# --- 严格模式 ---
set -e
set -o pipefail

# --- 变量定义 ---
DIRPATH="/usr/local/bin/tools"
SINGBOX_SCRIPT="$DIRPATH/sing-box.sh"
MOSDNS_RULES_DIR=""
MOSDNS_BASE_DIR=""
MIHOMO_PATH="/usr/local/bin/mihomo"
MIHOMO_CONFIG="/etc/mihomo/config.yaml"

# --- 颜色定义 ---
green_text="\033[32m"
yellow_text="\033[33m"
red_text="\033[31m"
blue_text="\033[34m"
reset="\033[0m"
bold="\033[1m"

# --- 格式化输出函数 ---
print_header() {
    local title="$1"
    echo -e "\n${bold}${green_text}=== $title ===${reset}\n"
}

print_status() {
    local label="$1"
    local value="$2"
    local status="$3"
    printf "  %-12s: ${yellow_text}%-25s${reset}%s\n" "$label" "$value" "$status"
}

print_menu_item() {
    local number="$1"
    local text="$2"
    printf "  ${green_text}%s${reset}. %-30s\n" "$number" "$text"
}

# --- 日志函数 ---
log_info() { echo -e "${green_text}==> $1${reset}"; }
log_warn() { echo -e "${yellow_text}!!> $1${reset}"; }
log_error() { echo -e "${red_text}✖ $1${reset}" >&2; }
log_success() { echo -e "${green_text}✓ $1${reset}"; }

# --- 错误处理 ---
handle_error() {
    local err_code=$1
    local line_no=$2
    log_error "错误发生在第 $line_no 行，错误代码: $err_code"
    exit 1
}
trap 'handle_error $? $LINENO' ERR

# --- 工具函数 ---
detect_architecture() {
    case $(uname -m) in
        x86_64)  echo "amd64" ;;
        aarch64) echo "arm64" ;;
        armv7l)  echo "armv7" ;;
        armhf)   echo "armhf" ;;
        s390x)   echo "s390x" ;;
        i386|i686) echo "386" ;;
        *)
            log_error "不支持的CPU架构: $(uname -m)"
            exit 1
            ;;
    esac
}

check_root() {
    if [ "$(id -u)" != "0" ]; then
        log_error "请使用 root 用户执行此脚本"
        echo -e "请执行以下命令切换用户：\n  sudo su -"
        exit 1
    fi
}

check_dependencies() {
    local missing_deps=()
    for cmd in curl wget git awk sed unzip systemctl; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "缺少必要的依赖: ${missing_deps[*]}"
        log_info "请使用包管理器安装这些依赖后重试"
        exit 1
    fi
}

# --- MosDNS 路径检测 ---
detect_mosdns_paths() {
    log_info "正在检测 MosDNS 配置目录..."
    if [ -d "/etc/mosdns/rule" ] && [ -f "/etc/mosdns/config.yaml" ]; then
        MOSDNS_BASE_DIR="/etc/mosdns"
        MOSDNS_RULES_DIR="/etc/mosdns/rule"
        log_info "检测到标准 MosDNS 安装路径: /etc/mosdns"
    elif [ -d "/cus/mosdns/rule" ] && [ -f "/cus/mosdns/config_custom.yaml" ]; then
        MOSDNS_BASE_DIR="/cus/mosdns"
        MOSDNS_RULES_DIR="/cus/mosdns/rule"
        log_info "检测到魔改版 MosDNS 安装路径: /cus/mosdns"
    else
        log_error "未找到 MosDNS 的配置目录"
        return 1
    fi
    return 0
}

# --- 下载函数 ---
download() {
    local output_file=$1
    local url=$2
    local progress=${3:-"show"}
    local redirect=${4:-"yes"}
    
    if command -v curl &>/dev/null; then
        local progress_opt="-#"
        [ "$progress" = "hide" ] && progress_opt="-s"
        local redirect_opt="-L"
        [ "$redirect" = "no" ] && redirect_opt=""
        
        if ! curl $progress_opt $redirect_opt -o "$output_file" "$url"; then
            return 1
        fi
    elif command -v wget &>/dev/null; then
        local progress_opt="--show-progress"
        [ "$progress" = "hide" ] && progress_opt="-q"
        local redirect_opt=""
        [ "$redirect" = "no" ] && redirect_opt="--max-redirect=0"
        
        if ! wget $progress_opt $redirect_opt --no-check-certificate -O "$output_file" "$url"; then
            return 1
        fi
    else
        log_error "未找到 curl 或 wget"
        return 1
    fi
    return 0
}

# --- 规则更新函数 ---
update_all_rules() {
    log_info "开始更新所有规则文件..."
    local temp_dir
    temp_dir=$(mktemp -d)
    trap 'rm -rf "$temp_dir"' EXIT
    
    if [ "$MOSDNS_BASE_DIR" = "/etc/mosdns" ]; then
        # 标准版规则
        local rules=(
            "https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/proxy-list.txt|geosite_geolocation_noncn.txt"
            "https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/gfw.txt|gfw.txt"
            "https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/direct-list.txt|geosite_cn.txt"
            "https://raw.githubusercontent.com/Hackl0us/GeoIP2-CN/release/CN-ip-cidr.txt|geoip_cn.txt"
        )
        
        mkdir -p "$MOSDNS_RULES_DIR"
        for rule in "${rules[@]}"; do
            local url=${rule%|*}
            local filename=${rule#*|}
            local output="$MOSDNS_RULES_DIR/$filename"
            
            log_info "正在下载: $filename"
            if download "$temp_dir/$filename" "$url" "show" "yes"; then
                mv "$temp_dir/$filename" "$output"
                log_info "更新成功: $filename"
            else
                log_error "下载失败: $filename"
            fi
        done
    else
        # 魔改版规则
        local github_raw_base="https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing"
        local rules=(
            "$github_raw_base/geo/geosite/cn.srs|geosite-cn.srs"
            "$github_raw_base/geo/geosite/geolocation-!cn.srs|geolocation-!cn.srs"
            "$github_raw_base/geo/geoip/cn.srs|geoip-cn.srs"
        )
        
        mkdir -p "$MOSDNS_BASE_DIR/unpack"
        for rule in "${rules[@]}"; do
            local url=${rule%|*}
            local filename=${rule#*|}
            local output="$MOSDNS_BASE_DIR/unpack/$filename"
            
            log_info "正在下载: $filename"
            if download "$temp_dir/$filename" "$url" "show" "yes"; then
                mv "$temp_dir/$filename" "$output"
                log_info "更新成功: $filename"
            else
                log_error "下载失败: $filename"
            fi
        done
    fi
}

# --- 规则管理函数 ---
add_rules() {
    local type=$1
    local target_file="$MOSDNS_RULES_DIR/${type}list.txt"
    mkdir -p "$(dirname "$target_file")" && touch "$target_file"
    clear

    echo -e "${green_text}添加规则到 ${type}list.txt${reset}"
    echo -e "  - 输入格式: ${yellow_text}内容#类型${reset} (例如: example.com#domain)"
    echo -e "  - 支持类型: ${yellow_text}full, domain, suffix, keyword, regex${reset}"
    echo -e "  - 类型可省略，默认为 'full'"
    echo -e "  - 多条规则请用 ${yellow_text}逗号 (,) ${reset}分隔"
    echo -e "  - 输入 'q' 或空行退出"

    read -p "请输入规则: " input
    [[ -z "$input" || "$input" == "q" ]] && return

    local new_rules
    new_rules=$(echo "$input" | tr ',' '\n' | awk -F'#' '
        function sanitize(str) { gsub(/^[ \t]+|[ \t]+$/, "", str); return str }
        {
            domain = sanitize($1);
            type = sanitize(tolower($2));
            if (domain == "") next;
            if (type !~ /^(full|domain|suffix|keyword|regex)$/) type = "full";
            if (type == "suffix" && domain !~ /^\./) domain = "." domain;
            print type ":" domain;
        }
    ' | sort -u)

    local added_count=0
    local exist_count=0
    while IFS= read -r line; do
        if grep -qFx "$line" "$target_file"; then
            log_warn "! 规则已存在: $line"
            ((exist_count++))
        else
            echo "$line" >> "$target_file"
            log_info "+ 规则已添加: $line"
            ((added_count++))
        fi
    done <<< "$new_rules"

    log_info "操作完成: 新增 ${added_count} 条, 已存在 ${exist_count} 条。"

    if [ "$added_count" -gt 0 ]; then
        read -p "是否立即重启 mosdns 使规则生效？[Y/n] " confirm
        [[ "${confirm:-Y}" =~ ^[Yy]$ ]] && systemctl restart mosdns && log_info "mosdns 已重启。"
    fi
}

view_rules() {
    local type=$1
    local target_file="$MOSDNS_RULES_DIR/${type}list.txt"
    mkdir -p "$(dirname "$target_file")" && touch "$target_file"
    clear

    if [ ! -s "$target_file" ]; then
        log_warn "当前无任何'${type}'规则。"
        return
    fi

    log_info "当前'${type}'规则列表:"
    echo "----------------------------------------"
    awk -F: '{ printf "  %-5d %-10s %s\n", NR, $1, $2 }' "$target_file"
    echo "----------------------------------------"

    log_info "类型统计:"
    awk -F: '{count[$1]++} END {for (t in count) printf "  %-10s: %d 条\n", t, count[t]}' "$target_file"
    echo ""
}

delete_rules() {
    local type=$1
    local target_file="$MOSDNS_RULES_DIR/${type}list.txt"

    view_rules "$type"
    [ ! -s "$target_file" ] && return

    read -p "输入要删除的行号 (多个用逗号或空格隔开, 'q'取消): " nums
    [[ -z "$nums" || "$nums" == "q" ]] && return

    local sed_script
    sed_script=$(echo "$nums" | tr ',' ' ' | sed 's/[^0-9 ]//g' | awk '{for(i=1;i<=NF;i++)print $i"d;"}')

    if [ -z "$sed_script" ]; then
        log_warn "输入无效，未执行任何操作。"
        return
    fi
    
    local tmp_file
    tmp_file=$(mktemp)
    trap 'rm -f "$tmp_file"' RETURN

    cp "$target_file" "$tmp_file"
    sed -i -e "$sed_script" "$target_file"

    if diff -q "$target_file" "$tmp_file" >/dev/null; then
        log_warn "无变更，可能输入的行号无效。"
    else
        log_info "已删除指定规则。"
        systemctl restart mosdns && log_info "mosdns 已重启。"
    fi
}

manage_list() {
    local type=$1
    while true; do
        clear
        echo -e "\n${green_text}=== ${type^} 名单管理 ===${reset}"
        echo -e "  1. 添加规则"
        echo -e "  2. 查看规则"
        echo -e "  3. 删除规则"
        echo -e "  0. 返回上级\n"

        read -p "请选择: " choice
        case $choice in
            1) add_rules "$type" ;;
            2) view_rules "$type" ;;
            3) delete_rules "$type" ;;
            0) break ;;
            *) log_warn "无效选择" ;;
        esac
        [ "$choice" != "0" ] && read -p "按回车键继续..."
    done
}

# --- MosDNS 核心更新函数 ---
update_mosdns_core() {
    local arch
    arch=$(detect_architecture)
    log_info "系统架构: $arch"
    
    local mosdns_url="https://github.com/herozmy/StoreHouse/releases/download/mosdns/mosdns-linux-$arch.zip"
    local temp_dir
    temp_dir=$(mktemp -d)
    trap 'rm -rf "$temp_dir"' RETURN

    log_info "正在备份当前 mosdns核心..."
    cp -f /usr/local/bin/mosdns /usr/local/bin/mosdns.bak_"$(date +%F)" || log_warn "备份失败或 MosDNS 未安装。"
    
    log_info "正在下载最新 MosDNS 核心..."
    if ! download "$temp_dir/mosdns.zip" "$mosdns_url" "show" "yes"; then
        log_error "下载失败！请检查网络或URL: $mosdns_url"
        return 1
    fi
    
    log_info "正在解压..."
    if ! unzip -o "$temp_dir/mosdns.zip" "mosdns" -d "$temp_dir"; then
        log_error "解压失败！请检查ZIP文件内容。"
        return 1
    fi

    if [ -f "$temp_dir/mosdns" ]; then
        mv -f "$temp_dir/mosdns" /usr/local/bin/mosdns
        chmod +x /usr/local/bin/mosdns
        log_info "MosDNS 核心更新成功！"
    else
        log_error "在解压文件中未找到 'mosdns' 可执行文件。"
        return 1
    fi
}

# --- 获取运行时长函数 ---
get_uptime_str() {
    local service=$1
    local start_time
    start_time=$(systemctl show "$service" --property=ActiveEnterTimestamp | cut -d= -f2)
    if [ -n "$start_time" ]; then
        local start_seconds=$(date -d "$start_time" +%s)
        local current_seconds=$(date +%s)
        local uptime_seconds=$((current_seconds - start_seconds))
        
        local days=$((uptime_seconds / 86400))
        local hours=$(( (uptime_seconds % 86400) / 3600 ))
        local minutes=$(( (uptime_seconds % 3600) / 60 ))
        local seconds=$((uptime_seconds % 60))
        
        local uptime_str=""
        [ $days -gt 0 ] && uptime_str="${days}天"
        [ $hours -gt 0 ] && uptime_str="${uptime_str}${hours}小时"
        [ $minutes -gt 0 ] && uptime_str="${uptime_str}${minutes}分"
        [ $seconds -gt 0 ] && uptime_str="${uptime_str}${seconds}秒"
        [ -z "$uptime_str" ] && uptime_str="刚刚启动"
        
        echo "$uptime_str"
    fi
}

# --- 检查服务状态函数 ---
check_service_status() {
    local service=$1
    if systemctl is-active --quiet "$service"; then
        local uptime_str
        uptime_str=$(get_uptime_str "$service")
        echo -e "${green_text}运行中${reset} - 已运行${yellow_text}${uptime_str}${reset}"
    else
        echo -e "${red_text}未运行${reset}"
    fi
}

# --- 检查代理服务状态 ---
check_proxy_status() {
    local has_singbox=false
    local has_mihomo=false
    local singbox_running=false
    local mihomo_running=false
    
    # 检查是否安装了服务
    if command -v sing-box &>/dev/null && [ -f "$SINGBOX_SCRIPT" ]; then
        has_singbox=true
    fi
    if command -v mihomo &>/dev/null; then
        has_mihomo=true
    fi
    
    # 检查每个服务是否在运行
    if systemctl is-active --quiet "sing-box"; then
        singbox_running=true
    fi
    if systemctl is-active --quiet "mihomo"; then
        mihomo_running=true
    fi
    
    # 返回结果
    echo "${has_singbox}:${has_mihomo}:${singbox_running}:${mihomo_running}"
}

# --- 切换代理核心函数 ---
switch_proxy_core() {
    local from_service=$1
    local to_service=$2
    
    # 检查目标服务是否可用
    if ! command -v "$to_service" &>/dev/null; then
        log_error "切换失败：${to_service^} 程序不存在"
        return 1
    fi
    
    # 如果当前没有服务在运行，直接启动目标服务
    if ! systemctl is-active --quiet "$from_service"; then
        log_info "当前无代理服务运行，直接启动 ${to_service^}..."
        systemctl enable "$to_service"
        systemctl start "$to_service" tproxy-router nftables
        log_info "${to_service^} 服务已启动"
        return 0
    fi
    
    log_info "正在停止 ${from_service^} 服务..."
    systemctl stop "$from_service" tproxy-router nftables
    systemctl disable "$from_service"
    
    log_info "正在启动 ${to_service^} 服务..."
    systemctl enable "$to_service"
    systemctl start "$to_service" tproxy-router nftables
    
    if systemctl is-active --quiet "$to_service"; then
        log_info "已成功从 ${from_service^} 切换到 ${to_service^}"
    else
        log_error "切换失败：${to_service^} 启动异常"
        return 1
    fi
}

# --- Sing-Box 管理函数 ---
manage_singbox() {
    while true; do
        clear
        local core_type="未知"
        local core_version="未知"
        
        # 获取核心类型
        [ -f "/etc/sing-box/version" ] && core_type=$(cat /etc/sing-box/version)
        
        # 获取核心版本
        if command -v sing-box &>/dev/null; then
            core_version=$(sing-box version | awk '/version/ {print $3}' || echo "未知")
        fi
        
        local status
        status=$(check_service_status "sing-box")

        echo -e "${green_text}=== Sing-Box 管理 ===${reset}"
        echo -e "  - 当前核心: ${yellow_text}${core_type}${reset}"
        echo -e "  - 核心版本: ${yellow_text}${core_version}${reset}"
        echo -e "  - 运行状态: $status"
        
        echo -e "\n${green_text}功能选项:${reset}"
        echo -e "  1. 更新核心"
        echo -e "  2. 切换核心"
        echo -e "  3. 更新UI面板"
        echo -e "  4. 安装回家配置"
        echo -e "  5. 重启服务"
        echo -e "  6. 切换nft规则模式"
        echo -e "  0. 返回主菜单\n"

        read -p "请选择操作: " choice
        case $choice in
            1) 
                log_info "开始更新 Sing-Box 核心..." 
                bash "$SINGBOX_SCRIPT" update_core 
                ;;
            2) 
                log_info "开始切换 Sing-Box 核心..." 
                bash "$SINGBOX_SCRIPT" switch_core 
                ;;
            3) 
                log_info "开始更新 UI 面板..." 
                bash "$SINGBOX_SCRIPT" update_ui 
                ;;
            4) 
                log_info "开始安装 Hysteria2 '回家' 配置..." 
                bash "$SINGBOX_SCRIPT" update_home 
                ;;
            5)
                log_info "正在重启服务..."
                systemctl restart sing-box tproxy-router nftables || log_warn "部分服务重启失败"
                log_info "服务已重启。"
                ;;
            6) bash "$SINGBOX_SCRIPT" switch_nft 
               systemctl restart sing-box tproxy-router nftables || log_warn "部分服务重启失败，请手动检查状态。"
            ;;
            0) break ;;
            *) log_warn "无效选择" ;;
        esac
        [ "$choice" != "0" ] && read -p "按回车键继续..."
    done
}

# --- MosDNS 管理函数 ---
manage_mosdns() {
    while true; do
        clear
        local status
        status=$(check_service_status "mosdns")
        
        # 获取 MosDNS 版本
        local version="未知"
        if command -v mosdns &>/dev/null; then
            version=$(mosdns version || echo "未知")
        fi
        
        echo -e "${green_text}=== MosDNS 管理 ===${reset}"
        echo -e "  - 核心版本: ${yellow_text}${version}${reset}"
        echo -e "  - 运行状态: $status"
        
        echo -e "\n${green_text}功能选项:${reset}"
        echo -e "  1. 更新核心"
        echo -e "  2. 更新规则文件"
        echo -e "  3. 规则管理"
        echo -e "  4. 清除DNS缓存"
        echo -e "  5. 查看实时日志"
        echo -e "  0. 返回主菜单\n"

        read -p "请选择操作: " choice
        case $choice in
            1) 
                update_mosdns_core
                systemctl restart mosdns
                ;;
            2) 
                update_all_rules
                systemctl restart mosdns
                ;;
            3)
                while true; do
                    clear
                    echo -e "\n${green_text}=== 规则列表选择 ===${reset}"
                    echo -e "  1. 白名单 (whitelist.txt)"
                    echo -e "  2. 黑名单 (blacklist.txt)"
                    echo -e "  0. 返回 MosDNS 管理\n"
                    read -p "请选择要管理的规则列表: " list_choice
                    case $list_choice in
                        1) manage_list "white" ;;
                        2) manage_list "black" ;;
                        0) break ;;
                        *) log_warn "无效选择" ;;
                    esac
                done
                ;;
            4)
                log_info "正在清除DNS缓存..."
                rm -f "$MOSDNS_BASE_DIR"/*.dump
                systemctl restart mosdns
                log_info "DNS缓存已清除并重启服务。"
                ;;
            5)
                clear
                log_info "正在显示 MosDNS 实时日志... 按 Ctrl+C 退出。"
                trap 'echo -e "\n${yellow_text}已停止日志查看。${reset}"; trap - INT; return' INT
                journalctl -u mosdns -f -o cat --no-pager
                trap - INT
                ;;
            0) break ;;
            *) log_warn "无效选择" ;;
        esac
        if [[ "$choice" != "0" && "$choice" != "5" && "$choice" != "3" ]]; then
             read -p "按回车键继续..."
        fi
    done
}

# --- 服务检测函数 ---
check_services() {
    local found_singbox=false
    local found_mosdns=false
    local found_mihomo=false
    local singbox_version=""
    local mosdns_version=""
    local mihomo_version=""
    
    if command -v sing-box &>/dev/null && [ -f "$SINGBOX_SCRIPT" ]; then
        found_singbox=true
        singbox_version=$(sing-box version | awk '/version/ {print $3}' || echo "N/A")
    fi

    if command -v mosdns &>/dev/null; then
        found_mosdns=true
        mosdns_version=$(mosdns version || echo "N/A")
    fi

    if command -v mihomo &>/dev/null; then
        found_mihomo=true
        mihomo_version=$(mihomo -v | awk '{print $3}' || echo "N/A")
    fi

    # 返回检测结果
    if $found_singbox; then echo "singbox:$singbox_version"; fi
    if $found_mosdns; then echo "mosdns:$mosdns_version"; fi
    if $found_mihomo; then echo "mihomo:$mihomo_version"; fi
}

# --- Mihomo 管理函数 ---
manage_mihomo() {
    while true; do
        clear
        local status
        status=$(check_service_status "mihomo")
        
        # 获取 Mihomo 版本
        local version="未知"
        if command -v mihomo &>/dev/null; then
            version=$(mihomo -v | awk '{print $3}' || echo "未知")
        fi
        
        echo -e "${green_text}=== Mihomo 管理面板 ===${reset}"
        echo -e "  - 当前版本: ${yellow_text}${version}${reset}"
        echo -e "  - 运行状态: $status"
        
        echo -e "\n${green_text}可用操作:${reset}"
        echo -e "  1. 重启 Mihomo 服务"
        echo -e "  2. 查看运行日志"
        echo -e "  0. 返回上级菜单\n"

        read -p "请选择操作 [0-2]: " choice
        case $choice in
            1)
                log_info "正在重启 Mihomo 服务..."
                systemctl restart mihomo tproxy-router nftables || log_warn "部分服务重启失败"
                log_info "Mihomo 服务已重启完成"
                ;;
            2)
                clear
                log_info "正在查看 Mihomo 运行日志... 按 Ctrl+C 退出"
                trap 'echo -e "\n${yellow_text}已退出日志查看${reset}"; trap - INT; return' INT
                journalctl -u mihomo -f -o cat --no-pager
                trap - INT
                ;;
            0) break ;;
            *) log_warn "无效的选择，请重试" ;;
        esac
        if [[ "$choice" != "0" && "$choice" != "2" ]]; then
             read -p "按回车键继续..."
        fi
    done
}

# --- 服务切换和启动函数 ---
start_singbox() {
    log_info "正在启动 Sing-Box..."
    sleep 1
    
    log_info "设置服务开机自启..."
    systemctl enable sing-box tproxy-router nftables &>/dev/null
    sleep 1
    
    log_info "启动 Sing-Box 服务..."
    systemctl start sing-box &>/dev/null
    sleep 1
    
    log_info "启动透明代理服务..."
    systemctl start tproxy-router &>/dev/null
    sleep 1
    
    log_info "启动防火墙服务..."
    systemctl start nftables &>/dev/null
    sleep 1

    if systemctl is-active --quiet sing-box; then
        log_success "Sing-Box 及相关服务已成功启动并设置为开机自启"
    else
        log_error "Sing-Box 启动失败！请检查服务状态"
        log_info "正在回滚更改..."
        systemctl disable sing-box tproxy-router nftables
        sleep 1
        log_info "已禁用所有相关服务"
    fi
    sleep 1
}

start_mihomo() {
    log_info "正在启动 Mihomo..."
    sleep 1
    
    log_info "设置服务开机自启..."
    systemctl enable mihomo tproxy-router nftables &>/dev/null
    sleep 1
    
    log_info "启动 Mihomo 服务..."
    systemctl start mihomo &>/dev/null
    sleep 1
    
    log_info "启动透明代理服务..."
    systemctl start tproxy-router &>/dev/null
    sleep 1
    
    log_info "启动防火墙服务..."
    systemctl start nftables &>/dev/null
    sleep 1

    if systemctl is-active --quiet mihomo; then
        log_success "Mihomo 及相关服务已成功启动并设置为开机自启"
    else
        log_error "Mihomo 启动失败！请检查服务状态"
        log_info "正在回滚更改..."
        systemctl disable mihomo tproxy-router nftables
        sleep 1
        log_info "已禁用所有相关服务"
    fi
    sleep 1
}

stop_singbox() {
    log_info "正在停止 Sing-Box..."
    sleep 1
    
    systemctl stop sing-box &>/dev/null
    log_info "Sing-Box 服务已停止"
    sleep 1

    # 如果没有其他代理服务在运行，也停止并禁用相关服务
    if ! systemctl is-active --quiet mihomo &>/dev/null; then
        log_info "停止透明代理服务..."
        systemctl stop tproxy-router &>/dev/null
        sleep 1
        
        log_info "停止防火墙服务..."
        systemctl stop nftables &>/dev/null
        sleep 1
        
        log_info "禁用所有服务自启动..."
        systemctl disable sing-box tproxy-router nftables &>/dev/null
        sleep 1
        
        log_success "已停止并禁用 Sing-Box 及相关服务"
    else
        log_info "禁用 Sing-Box 自启动..."
        systemctl disable sing-box &>/dev/null
        sleep 1
        
        log_success "已停止并禁用 Sing-Box 服务"
    fi
    sleep 1
}

stop_mihomo() {
    log_info "正在停止 Mihomo..."
    sleep 1
    
    systemctl stop mihomo &>/dev/null
    log_info "Mihomo 服务已停止"
    sleep 1

    # 如果没有其他代理服务在运行，也停止并禁用相关服务
    if ! systemctl is-active --quiet sing-box &>/dev/null; then
        log_info "停止透明代理服务..."
        systemctl stop tproxy-router &>/dev/null
        sleep 1
        
        log_info "停止防火墙服务..."
        systemctl stop nftables &>/dev/null
        sleep 1
        
        log_info "禁用所有服务自启动..."
        systemctl disable mihomo tproxy-router nftables &>/dev/null
        sleep 1
        
        log_success "已停止并禁用 Mihomo 及相关服务"
    else
        log_info "禁用 Mihomo 自启动..."
        systemctl disable mihomo &>/dev/null
        sleep 1
        
        log_success "已停止并禁用 Mihomo 服务"
    fi
    sleep 1
}

switch_to_mihomo() {
    switch_proxy_core "sing-box" "mihomo"
}

switch_to_singbox() {
    switch_proxy_core "mihomo" "sing-box"
}

# --- 主函数 ---
main() {
    check_root
    check_dependencies

    # 检测已安装的服务
    local services
    mapfile -t services < <(check_services)
    local num_services=${#services[@]}

    if [ "$num_services" -eq 0 ]; then
        log_error "未检测到任何可用服务（Sing-Box、MosDNS 或 Mihomo）"
        log_error "请确保至少安装了其中一个服务"
        exit 1
    fi

    # 如果只安装了一个服务，直接进入对应的管理界面
    if [ "$num_services" -eq 1 ]; then
        local service_name=${services[0]%%:*}
        log_info "检测到已安装 ${service_name^}，正在进入管理界面..."
        sleep 1
        case "$service_name" in
            "singbox") manage_singbox ;;
            "mosdns") detect_mosdns_paths && manage_mosdns ;;
            "mihomo") manage_mihomo ;;
        esac
        exit 0
    fi

    # 如果安装了多个服务，显示选择菜单
    while true; do
        clear
        # 获取代理服务状态
        IFS=':' read -r has_singbox has_mihomo singbox_running mihomo_running <<< "$(check_proxy_status)"
        
        print_header "网络工具管理面板"
        
        # 显示已安装的服务及其版本和运行状态
        echo -e "${bold}已安装的服务:${reset}"
        for service in "${services[@]}"; do
            local name=${service%%:*}
            local version=${service#*:}
            local status_text=""
            
            # 根据服务类型和运行状态设置显示文本
            case "$name" in
                "singbox")
                    status_text=$([ "$singbox_running" = "true" ] && 
                        printf "${green_text}[运行中]${reset}" || 
                        printf "${yellow_text}[已停止]${reset}")
                    print_status "Sing-Box" "$version" "$status_text"
                    ;;
                "mosdns")
                    status_text=$(systemctl is-active --quiet "mosdns" && 
                        printf "${green_text}[运行中]${reset}" || 
                        printf "${yellow_text}[已停止]${reset}")
                    print_status "MosDNS" "$version" "$status_text"
                    ;;
                "mihomo")
                    status_text=$([ "$mihomo_running" = "true" ] && 
                        printf "${green_text}[运行中]${reset}" || 
                        printf "${yellow_text}[已停止]${reset}")
                    print_status "Mihomo" "$version" "$status_text"
                    ;;
            esac
        done
        
        echo -e "\n${bold}${green_text}可用操作:${reset}"
        local i=1
        for service in "${services[@]}"; do
            local name=${service%%:*}
            case "$name" in
                "singbox") print_menu_item "$i" "Sing-Box 管理" ;;
                "mosdns") print_menu_item "$i" "MosDNS 管理" ;;
                "mihomo") print_menu_item "$i" "Mihomo 管理" ;;
            esac
            ((i++))
        done

        # 如果同时安装了 Sing-Box 和 Mihomo，显示切换选项
        if [ "$has_singbox" = "true" ] && [ "$has_mihomo" = "true" ]; then
            # 计算当前运行状态
            local both_running=false
            local none_running=false
            
            if [ "$singbox_running" = "true" ] && [ "$mihomo_running" = "true" ]; then
                both_running=true
            elif [ "$singbox_running" = "false" ] && [ "$mihomo_running" = "false" ]; then
                none_running=true
            fi
            
            if [ "$both_running" = "true" ]; then
                # 两个服务都在运行
                print_menu_item "$i" "停止 Sing-Box 代理"
                print_menu_item "$((i+1))" "停止 Mihomo 代理"
            elif [ "$none_running" = "true" ]; then
                # 两个服务都没运行
                print_menu_item "$i" "启动 Sing-Box 代理"
                print_menu_item "$((i+1))" "启动 Mihomo 代理"
            else
                # 只有一个服务在运行
                if [ "$singbox_running" = "true" ]; then
                    print_menu_item "$i" "切换到 Mihomo 代理"
                    
                    print_menu_item "$((i+1))" "停止 Sing-Box 代理"
                else
                    print_menu_item "$i" "切换到 Sing-Box 代理"
                    
                    print_menu_item "$((i+1))" "停止 Mihomo 代理"
                fi
            fi
        fi
        
        print_menu_item "q" "退出程序"
        echo
        
        # 根据是否有切换选项调整提示文本
        local prompt_range="1-$((num_services))"
        if [ "$has_singbox" = "true" ] && [ "$has_mihomo" = "true" ]; then
            # 根据不同的运行状态设置不同的提示范围
            if [ "$singbox_running" = "true" ] && [ "$mihomo_running" = "true" ]; then
                # 两个都在运行
                prompt_range="1-$((num_services+2))"
            elif [ "$singbox_running" = "false" ] && [ "$mihomo_running" = "false" ]; then
                # 两个都没运行
                prompt_range="1-$((num_services+2))"
            else
                # 只有一个运行
                prompt_range="1-$((num_services+2))"
            fi
        fi
        
        read -rp "请选择要执行的操作 [$prompt_range/q]: " choice
        case "$choice" in
            q|Q)
                echo -e "感谢使用！"
                exit 0 
                ;;
            *)
                # 将数字选择转换为实际的服务管理
                if [[ "$choice" =~ ^[0-9]+$ ]]; then
                    # 获取菜单项对应的服务名称
                    local index=$((choice-1))
                    if [ $index -ge 0 ] && [ $index -lt ${#services[@]} ]; then
                        local service_name=${services[$index]%%:*}
                        case "$service_name" in
                            "singbox") 
                                manage_singbox 
                                ;;
                            "mihomo")
                                manage_mihomo
                                ;;
                            "mosdns") 
                                detect_mosdns_paths && manage_mosdns
                                ;;
                        esac
                    elif [ "$has_singbox" = "true" ] && [ "$has_mihomo" = "true" ]; then
                        # 处理额外的切换或启动/停止选项
                        local both_running=false
                        local none_running=false
            
                        if [ "$singbox_running" = "true" ] && [ "$mihomo_running" = "true" ]; then
                            both_running=true
                        elif [ "$singbox_running" = "false" ] && [ "$mihomo_running" = "false" ]; then
                            none_running=true
                        fi
                        
                        if [ "$both_running" = "true" ]; then
                            # 两个都运行时的选项
                            if [ "$choice" = "$((num_services+1))" ]; then
                                stop_singbox
                            elif [ "$choice" = "$((num_services+2))" ]; then
                                stop_mihomo
                            fi
                        elif [ "$none_running" = "true" ]; then
                            # 没有服务运行时的选项
                            if [ "$choice" = "$((num_services+1))" ]; then
                                start_singbox
                            elif [ "$choice" = "$((num_services+2))" ]; then
                                start_mihomo
                            fi
                        else
                            # 只有一个服务运行时的选项
                            if [ "$singbox_running" = "true" ]; then
                                if [ "$choice" = "$((num_services+1))" ]; then
                                    switch_to_mihomo
                                elif [ "$choice" = "$((num_services+2))" ]; then
                                    stop_singbox
                                fi
                            else
                                if [ "$choice" = "$((num_services+1))" ]; then
                                    switch_to_singbox
                                elif [ "$choice" = "$((num_services+2))" ]; then
                                    stop_mihomo
                                fi
                            fi
                        fi
                    else
                        log_warn "无效输入，请重新选择。" && sleep 1
                    fi
                else
                    log_warn "无效输入，请重新选择。" && sleep 1
                fi
                ;;
        esac
done
}

# --- 执行主函数 ---
main "$@"