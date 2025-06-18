#!/bin/bash
#
# Sing-Box & MosDNS 多功能一体化管理脚本 (纯 echo -e 版本)
#
#
# --- 严格模式 ---
set -e
set -o pipefail

# --- 颜色与日志函数 ---
readonly green="\033[32m"
readonly yellow="\033[33m"
readonly red="\033[31m"
readonly reset="\033[0m"

log_info() {
    echo -e "${green}==> $1${reset}"
}

log_warn() {
    echo -e "${yellow}!!> $1${reset}"
}

log_error() {
    echo -e "${red}✖ $1${reset}" >&2
}

# --- 全局常量与变量 ---
readonly RULES_DIR="/etc/mosdns/rule"
readonly SINGBOX_SCRIPT="/usr/local/bin/tools/sing-box.sh"

# 动态变量
found_singbox=false
found_mosdns=false
singbox_version=""
mosdns_version=""

# --- 核心功能函数 ---

detect_architecture() {
    case $(uname -m) in
        x86_64)     echo "amd64" ;;
        aarch64)    echo "arm64" ;;
        armv7l)     echo "armv7" ;;
        armhf)      echo "armhf" ;;
        s390x)      echo "s390x" ;;
        i386|i686)  echo "386" ;;
        *)
            log_error "不支持的CPU架构: $(uname -m)"
            exit 1
            ;;
    esac
}

update_all_rules() {
    log_info "开始并行更新所有规则文件..."
    mkdir -p "$RULES_DIR"

    declare -A rules
    rules=(
        ["https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/proxy-list.txt"]="$RULES_DIR/geosite_geolocation_noncn.txt"
        ["https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/gfw.txt"]="$RULES_DIR/gfw.txt"
        ["https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/direct-list.txt"]="$RULES_DIR/geosite_cn.txt"
        ["https://raw.githubusercontent.com/Hackl0us/GeoIP2-CN/release/CN-ip-cidr.txt"]="$RULES_DIR/geoip_cn.txt"
    )

    local pids=()
    local failed_counter_file
    failed_counter_file=$(mktemp)
    echo 0 > "$failed_counter_file"
    trap 'rm -f "$failed_counter_file"' RETURN

    for url in "${!rules[@]}"; do
        local file="${rules[$url]}"
        {
            echo -e "  -> 正在下载: $(basename "$file")"
            if curl -sL --retry 3 --connect-timeout 5 "$url" -o "$file.tmp"; then
                mv "$file.tmp" "$file"
                echo -e "  ${green}✔ 更新成功: $(basename "$file")${reset}"
            else
                echo -e "  ${red}✖ 更新失败: $(basename "$file")${reset}"
                (flock 200; count=$(cat "$failed_counter_file"); echo $((count + 1)) > "$failed_counter_file") 200>"$failed_counter_file.lock"
            fi
        } &
        pids+=($!)
    done

    for pid in "${pids[@]}"; do
        wait "$pid"
    done

    local failed_downloads
    failed_downloads=$(cat "$failed_counter_file")
    if [ "$failed_downloads" -gt 0 ]; then
        log_error "有 $failed_downloads 个规则文件更新失败，请检查网络连接。"
    else
        log_info "所有规则文件更新完成。"
    fi
}

# --- MosDNS 规则管理模块 ---

add_rules() {
    local type=$1
    local target_file="$RULES_DIR/${type}list.txt"
    mkdir -p "$(dirname "$target_file")" && touch "$target_file"
    clear

    echo -e "${green}添加规则到 ${type}list.txt${reset}"
    echo -e "  - 输入格式: ${yellow}内容#类型${reset} (例如: example.com#domain)"
    echo -e "  - 支持类型: ${yellow}full, domain, suffix, keyword, regex${reset}"
    echo -e "  - 类型可省略，默认为 'full'"
    echo -e "  - 多条规则请用 ${yellow}逗号 (,) ${reset}分隔"
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
    local target_file="$RULES_DIR/${type}list.txt"
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
    local target_file="$RULES_DIR/${type}list.txt"

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
        echo -e "\n${green}=== ${type^} 名单管理 ===${reset}"
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

# --- 独立程序管理模块 ---

update_mosdns_core() {
    local arch
    arch=$(detect_architecture)
    log_info "系统架构: $arch"
    
    local mosdns_url="https://github.com/herozmy/StoreHouse/releases/download/mosdns/mosdns-linux-$arch.zip"
    local temp_dir
    temp_dir=$(mktemp -d)
    trap 'rm -rf "$temp_dir"' RETURN

    log_info "正在备份当前 mosdns核心..."
    cp -f /usr/local/bin/mosdns /usr/local/bin/mosdns.bak_"$(date +%F)"
    
    log_info "正在下载最新 MosDNS 核心..."
    if ! wget -qO "$temp_dir/mosdns.zip" "$mosdns_url"; then
        log_error "下载失败！请检查网络或URL: $mosdns_url"
        return 1
    fi
    
    log_info "正在解压..."
    if ! unzip -o "$temp_dir/mosdns.zip" -d "$temp_dir"; then
        log_error "解压失败！"
        return 1
    fi

    log_info "正在安装新核心..."
    if [ -f "$temp_dir/mosdns" ]; then
        mv -f "$temp_dir/mosdns" /usr/local/bin/mosdns
        chmod +x /usr/local/bin/mosdns
        log_info "MosDNS 核心更新成功！"
    else
        log_error "在解压文件中未找到 'mosdns' 可执行文件。"
        return 1
    fi
}

check_services() {
    found_singbox=false
    found_mosdns=false
    
    if command -v sing-box &>/dev/null && [ -f "$SINGBOX_SCRIPT" ]; then
        found_singbox=true
        singbox_version=$(sing-box version | awk '/version/ {print $3}' || echo "N/A")
    fi

    if command -v mosdns &>/dev/null; then
        found_mosdns=true
        mosdns_version=$(mosdns version || echo "N/A")
    fi
}

manage_singbox() {
    while true; do
        check_services
        clear
        local core_type="未知"
        [ -f "/etc/sing-box/version" ] && core_type=$(cat /etc/sing-box/version)

        echo -e "${green}=== Sing-Box 管理 ===${reset}"
        echo -e "  - 当前核心: ${yellow}${core_type}${reset}"
        echo -e "  - 当前版本: ${yellow}${singbox_version}${reset}\n"
        echo -e "  1. 更新核心"
        echo -e "  2. 切换核心"
        echo -e "  3. 更新UI面板"
        echo -e "  4. 安装回家配置"
        echo -e "  5. 重启所有服务"
        echo -e "  0. 返回主菜单\n"

        read -p "请选择操作: " choice
        case $choice in
            1) log_info "开始更新 Sing-Box 核心..." && bash "$SINGBOX_SCRIPT" update_core ;;
            2) log_info "开始切换 Sing-Box 核心..." && bash "$SINGBOX_SCRIPT" switch_core ;;
            3) log_info "开始更新 UI 面板..." && bash "$SINGBOX_SCRIPT" update_ui ;;
            4) log_info "开始安装 Hysteria2 '回家' 配置..." && bash "$SINGBOX_SCRIPT" update_home ;;
            5)
                log_info "正在重启所有相关服务..."
                systemctl restart sing-box tproxy-router nftables || log_warn "部分服务重启失败，请手动检查状态。"
                log_info "服务已重启。"
                ;;
            0) break ;;
            *) log_warn "无效选择" ;;
        esac
        [ "$choice" != "0" ] && read -p "按回车键返回菜单..."
    done
}

manage_mosdns() {
    while true; do
        check_services
        clear
        echo -e "${green}=== MosDNS 管理 ===${reset}"
        echo -e "  - 当前版本: ${yellow}${mosdns_version}${reset}\n"
        echo -e "  1. 更新核心"
        echo -e "  2. 更新规则文件"
        echo -e "  3. 规则管理 (白/灰名单)"
        echo -e "  4. 清除DNS缓存"
        echo -e "  5. 查看实时日志"
        echo -e "  0. 返回主菜单\n"

        read -p "请选择操作: " choice
        case $choice in
            1) update_mosdns_core && systemctl restart mosdns ;;
            2) update_all_rules && systemctl restart mosdns && log_info "mosdns 已重启。" ;;
            3) manage_list "white" ;;
            4)
                log_info "正在清除DNS缓存..."
                rm -f /etc/mosdns/*.dump
                systemctl restart mosdns
                log_info "DNS缓存已清除并重启服务。"
                ;;
            5)
                clear
                log_info "正在显示 MosDNS 实时日志... 按 Ctrl+C 退出。"
                trap 'echo -e "\n${yellow}已停止日志查看。${reset}"; trap - INT; return' INT
                journalctl -u mosdns -f -o cat --no-pager
                trap - INT
                ;;
            0) break ;;
            *) log_warn "无效选择" ;;
        esac
        if [[ "$choice" != "0" && "$choice" != "5" && "$choice" != "3" ]]; then
             read -p "按回车键返回菜单..."
        fi
    done
}


# --- 主程序入口 (Main) ---
main() {
    for cmd in curl wget git awk sed unzip; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "关键命令 '$cmd' 未找到，请先安装。"
            exit 1
        fi
    done
    
    check_services
    
    local installed=()
    $found_singbox && installed+=("Sing-Box")
    $found_mosdns && installed+=("MosDNS")

    if [ ${#installed[@]} -eq 0 ]; then
        log_error "未检测到 Sing-Box 或 MosDNS，脚本无法执行。"
        exit 1
    fi

    if [ ${#installed[@]} -eq 1 ]; then
        log_info "检测到仅安装了 ${installed[0]}，直接进入管理界面..."
        sleep 1
        if [ "${installed[0]}" == "Sing-Box" ]; then
            manage_singbox
        else
            manage_mosdns
        fi
        exit 0
    fi

    while true; do
        clear
        echo -e "${green}=== proxytool 工具箱 ===${reset}\n"
        echo -e "  1. 管理 Sing-Box (版本: $singbox_version)"
        echo -e "  2. 管理 MosDNS (版本: $mosdns_version)\n"
        echo -e "  q. 退出脚本\n"

        read -p "请输入您的选择: " choice
        case "$choice" in
            1) manage_singbox ;;
            2) manage_mosdns ;;
            q|Q)
                echo -e "感谢使用！"
                exit 0 ;;
            *) log_warn "无效输入，请重新选择。" && sleep 1 ;;
        esac
    done
}

# --- 脚本执行 ---
main "$@"