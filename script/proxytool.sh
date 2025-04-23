#!/bin/bash

# 颜色定义
green="\033[32m"
yellow="\033[33m"
red="\033[31m"
reset="\033[0m"

# 初始化检测状态
found_singbox=false
found_mosdns=false
# 通用配置
RULES_DIR="/etc/mosdns/rule"
WHITE_FILE="$RULES_DIR/whitelist.txt"
GREY_FILE="$RULES_DIR/greylist.txt"
# 专用版本变量
singbox_version=""
mosdns_version=""
DIRPATH="/usr/local/bin/tools"
# 修改架构检测函数为最新标准
detect_architecture() {
    case $(uname -m) in
        x86_64)     echo "amd64" ;;
        aarch64)    echo "arm64" ;;
        armv7l)     echo "armv7" ;;
        armhf)      echo "armhf" ;;
        s390x)      echo "s390x" ;;
        i386|i686)  echo "386" ;;
        *)
            echo -e "${yellow}不支持的CPU架构: $(uname -m)${reset}"
            exit 1
            ;;
    esac
}
update_all_rules(){
# 设置需要下载的文件 URL
proxy_list_url="https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/proxy-list.txt"
gfw_list_url="https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/gfw.txt"
direct_list_url="https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/direct-list.txt"
cn_ip_cidr_url="https://raw.githubusercontent.com/Hackl0us/GeoIP2-CN/release/CN-ip-cidr.txt"

# 设置本地文件路径
geosite_cn_file="/etc/mosdns/rule/geosite_cn.txt"
geoip_cn_file="/etc/mosdns/rule/geoip_cn.txt"
geosite_geolocation_noncn_file="/etc/mosdns/rule/geosite_geolocation_noncn.txt"
gfw_file="/etc/mosdns/rule/gfw.txt"

# 下载并替换文件的函数
    download_and_replace() {
        local url=$1
        local file=$2

    # 下载文件
        curl -s "$url" -o "$file.tmp"

    # 检查下载是否成功
        if [ $? -eq 0 ]; then
        # 用下载的文件替换原文件
            mv "$file.tmp" "$file"
            echo "文件 $file 更新成功。"
        else
            echo "下载 $file 失败。"
        fi
    }

# 下载并替换文件
download_and_replace "$proxy_list_url" "$geosite_geolocation_noncn_file"
download_and_replace "$gfw_list_url" "$gfw_file"
download_and_replace "$direct_list_url" "$geosite_cn_file"
download_and_replace "$cn_ip_cidr_url" "$geoip_cn_file"

echo "所有文件更新完成。"
}
# 初始化文件
init_file() {
    local file="$1"
    mkdir -p "$RULES_DIR"
    touch "$file"
}

# 通用添加规则函数
add_rules() {
    local type=$1
    local target_file="$RULES_DIR/${type}list.txt"
    
    init_file "$target_file"
    clear
    
    echo -e "${green}输入格式：内容#类型"
    echo -e "支持类型：full/domain/suffix/keyword/regex"
    echo -e "示例：example.com#domain 或 .google.com#suffix${reset}"
    echo -e "多个规则用逗号分隔："
    
    read -p "请输入规则: " input
    [ -z "$input" ] && return

    # 处理输入
    echo "$input" | tr ',' '\n' | awk -F# -v type="$type" '
    BEGIN {
        OFS = ":"
        valid["full"]; valid["domain"]; valid["suffix"]; valid["keyword"]; valid["regex"]
    }
    {
        gsub(/ /, "", $0)
        if (NF < 1) next
        
        # 解析类型
        rule_type = "full"
        if (NF >= 2) {
            rule_type = tolower($2)
            gsub(/[^a-z]/, "", rule_type)
            if (!(rule_type in valid)) {
                printf "'${yellow}'类型%s无效，使用默认full类型\n", $2 > "/dev/stderr"
                rule_type = "full"
            }
        }

        # 处理值
        value = $1
        if (rule_type == "suffix" && value !~ /^\./) {
            value = "." value
        }

        print rule_type, value
    }' | sort -u | while read -r line; do
        if ! grep -qFx "$line" "$target_file"; then
            echo "$line" >> "$target_file"
            echo -e "  ${green}+ ${line}${reset}"
        else
            echo -e "  ${yellow}! 已存在 ${line}${reset}"
        fi
    done

    read -p "是否立即生效？[Y/n] " confirm
    [[ "${confirm:-Y}" =~ [Yy] ]] && systemctl restart mosdns
}

# 通用查看函数
view_rules() {
    local type=$1
    local target_file="$RULES_DIR/${type}list.txt"
    
    init_file "$target_file"
    clear
    
    if [ ! -s "$target_file" ]; then
        echo -e "${yellow}无有效${type}规则${reset}"
        return
    fi

    echo -e "\n${green}当前${type}规则列表：${reset}"
    awk -F: -v type="$type" '
    BEGIN {
        printf "%-6s %-10s %s\n", "行号", "类型", "内容"
        print "----------------------------------"
    }
    {
        printf "%-6d %-10s %s\n", NR, $1, $2
    }' "$target_file"

    echo -e "\n${green}类型统计：${reset}"
    awk -F: '{count[$1]++} END {
        for (t in count) printf "  %-8s %d条\n", t":", count[t]
    }' "$target_file"
}

# 通用删除函数
delete_rules() {
    local type=$1
    local target_file="$RULES_DIR/${type}list.txt"
    
    view_rules "$type"
    [ ! -s "$target_file" ] && return

    read -p "输入要删除的行号（多个用逗号）: " nums
    [ -z "$nums" ] && return

    # 生成临时文件
    tmp_file=$(mktemp)
    awk -v list="$nums" '
    BEGIN {
        split(list, arr, ",")
        for (i in arr) delete_lines[arr[i]]
    }
    NR in delete_lines { next } 1
    ' "$target_file" > "$tmp_file"

    # 替换原文件
    if diff "$target_file" "$tmp_file" &>/dev/null; then
        echo -e "${yellow}无变更${reset}"
    else
        mv "$tmp_file" "$target_file"
        echo -e "${green}已删除指定规则${reset}"
        systemctl restart mosdns
    fi
    rm -f "$tmp_file"
}

# 名单类型管理菜单
manage_list() {
    local type=$1
    while true; do
        echo -e "\n${green}=== ${type}名单管理 ===${reset}"
        echo "1. 添加规则"
        echo "2. 查看规则"
        echo "3. 删除规则"
        echo "4. 返回上级"
        
        read -p "请选择: " choice
        case $choice in
            1) add_rules "$type" ;;
            2) view_rules "$type" ;;
            3) delete_rules "$type" ;;
            4) break ;;
            *) echo -e "${red}无效选择${reset}" ;;
        esac
    done
}
# 主菜单
rule_menu() {
    while true; do
        echo -e "\n${green}=== MosDNS 规则管理 ===${reset}"
        echo "1. 管理白名单"
        echo "2. 管理黑名单"
        echo "3. 退出"
        
        read -p "请选择: " choice
        case $choice in
            1) manage_list "white" ;;
            2) manage_list "grey" ;;
            3) exit ;;
            *) echo -e "${red}无效选择${reset}" ;;
        esac
    done
}


update_mosdns_core(){
    arch=$(detect_architecture)
    echo "系统架构是：$arch"
    cp -rf /usr/local/bin/mosdns /usr/local/bin/mosdns.bak
    mosdns_host="https://github.com/herozmy/StoreHouse/releases/download/mosdns/mosdns-linux-$arch.zip"
    #apt update && apt -y upgrade || { echo "更新失败！退出脚本"; exit 1; }
    #apt install curl wget git tar gawk sed cron unzip nano -y || { echo "更新失败！退出脚本"; exit 1; }
    wget "${mosdns_host}" || { echo -e "\e[31m下载失败！退出脚本\e[0m"; exit 1; }
    echo "开始解压"
    unzip ./mosdns-linux-$arch.zip 
    sleep 1
    mv -v ./mosdns /usr/local/bin/
    rm -rf mosdns-linux-$arch.zip
    chmod 0777 /usr/local/bin/mosdns 
}
# 专用检测函数
check_singbox() {
    if [ -f "/usr/local/bin/sing-box" ]; then
        found_singbox=true
        singbox_version=$(sing-box version | awk '{print $3}')
    fi
}

check_mosdns() {
    if [ -f "/usr/local/bin/mosdns" ]; then
        found_mosdns=true
        mosdns_version=$(mosdns version | awk '/Version/{print $2}')
    fi
}

# 独立管理函数
manage_singbox() {
    while true; do
        echo -e "\n${green}=== Sing-Box 管理 (v${singbox_version}) ===${reset}"
        echo "1. 更新核心"
        echo "2. 更新UI面板"
        echo "3. 重启服务"
        echo "4. 返回主菜单"
        
        read -p "请选择操作: " choice
        case $choice in
            1)
                echo -e "\n${green}开始更新 Sing-Box...${reset}"
                bash /usr/local/bin/tools/sing-box.sh update_core    
                echo -e "${green}更新完成，当前版本：$(sing-box version | awk '{print $3}')${reset}"

                ;;
            2)
                echo -e "\n${green}开始更新 UI 面板...${reset}"
                bash /usr/local/bin/tools/sing-box.sh update_ui
                echo -e "${green}UI 面板更新完成${reset}"
                ;;
            3)
                systemctl restart sing-box
                echo -e "${green}服务已重启${reset}"
                ;;
            4)
                break
                ;;
            *)
                echo -e "${red}无效选择${reset}"
                ;;
        esac
    done
}

manage_mosdns() {
    while true; do
        echo -e "\n${green}=== MosDNS 管理 (v${mosdns_version}) ===${reset}"
        echo "1. 更新核心"
        echo "2. 更新规则文件"
        echo "3. 清除DNS缓存"
        echo "4. 查看实时日志"
        echo "5. 规则管理"
        echo "0. 返回主菜单"
        
        read -p "请选择操作: " choice
        case $choice in
            1)
                echo -e "\n${green}开始更新 MosDNS...${reset}"
                update_mosdns_core
                systemctl restart mosdns
                echo -e "${green}更新完成，当前版本：$(mosdns version)${reset}"
                ;;
            2)
                echo -e "\n${green}更新分流规则文件...${reset}"
                update_all_rules
                systemctl restart mosdns
                echo -e "${green}分流规则文件更新完成${reset}"
                ;;
            3)
                rm -f /etc/mosdns/*.dump
                systemctl restart mosdns
                echo -e "${green}DNS缓存已清除${reset}"
                ;;
            4)
                journalctl -u mosdns -f
                ;;
            5)
                rule_menu
                ;;
            0)
                break
                ;;
            *)
                echo -e "${red}无效选择${reset}"
                ;;
        esac
    done
}

main() {
    # 执行检测
    check_singbox
    check_mosdns

    # 生成程序列表
    installed=()
    $found_singbox && installed+=("sing-box")
    $found_mosdns && installed+=("mosdns")

    # 无安装时退出
    if [ ${#installed[@]} -eq 0 ]; then
        echo -e "${yellow}未检测到已安装程序${reset}"
        exit 0
    fi

    # 显示菜单
    while true; do
        echo -e "\n${green}=== 工具管理 ===${reset}"
        for i in "${!installed[@]}"; do
            echo -e "  ${green}$((i+1))${reset}. 管理 ${installed[$i]}"
        done
        echo -e "  ${green}q${reset}. 退出"
        
        read -p "请输入选择: " input
        case $input in
            [1-9])
                # 转换为数组索引
                index=$((input-1))
                if (( index >= 0 && index < ${#installed[@]} )); then
                    case "${installed[$index]}" in
                        "sing-box") manage_singbox ;;
                        "mosdns") manage_mosdns ;;
                    esac
                else
                    echo -e "${red}无效选择${reset}"
                fi
                ;;
            q|Q)
                exit 0
                ;;
            *)
                echo -e "${red}无效输入，请重新选择${reset}"
                ;;
        esac
    done
}

# 执行主程序
main