#!/bin/bash
#
# 服务管理菜单
# 优化版本: 1.0

# --- 颜色定义 ---
green_text="\033[32m"
yellow_text="\033[33m"
red_text="\033[31m"
grey_text="\033[90m"
reset="\033[0m"

# --- 变量定义 ---
DIRPATH="/usr/local/bin/tools"
local_ip=$(hostname -I | awk '{print $1}')
# --- 工具函数 ---
# 确保 proxytool 命令可用
ensure_proxytool() {
    if ! command -v proxytool &> /dev/null; then
        echo "检测到 proxytool 未安装，正在设置..."
        cp "$DIRPATH/proxytool.sh" /usr/bin/proxytool
        chmod +x /usr/bin/proxytool
        echo "proxytool 已设置。"
    fi
    proxytool
}

# 获取服务状态: 1=运行中, 0=未运行, 9=未安装
get_service_status() {
    local program_name=$1
    local program_path="/usr/local/bin/$program_name"
    local service_name=$program_name
    
    # Redis服务名与程序名不同
    [[ "$program_name" == "redis-server" ]] && service_name="redis"
    
    # 检查安装和运行状态
    if [[ ! -f "$program_path" ]]; then 
        return 9  # 未安装
    elif systemctl is-active --quiet "$service_name"; then 
        return 1  # 运行中
    else 
        return 0  # 未运行
    fi
}

# 格式化状态显示
format_status_for_menu() {
    case $1 in
        1) echo -e "${green_text}[运行中]${reset}" ;;
        0) echo -e "${red_text}[未运行]${reset}" ;;
        9) echo -e "${grey_text}[未安装]${reset}" ;;
    esac
}

# 处理“服务已运行”的交互逻辑
handle_running_service() {
    local display_name=$1
    local cleanup_cmd=$2
    local install_script=$3

    echo -e "${display_name} 服务已运行，继续安装将进行${yellow_text}覆盖安装${reset}。"
    echo -e "输入 ${green_text}g${reset} 进行覆盖安装"
    echo -e "输入 ${green_text}n${reset} 返回主菜单"
    echo -e "输入 ${green_text}任意其他键${reset} 进入 ${display_name} 快捷管理脚本"
    read -rp "请输入: " input
    case "$input" in
        g|G) 
            echo "正在执行覆盖安装前的清理操作..."
            eval "$cleanup_cmd"
            echo "清理完成，开始执行安装脚本..."
            eval "$install_script"
            ;;
        n|N) . "$DIRPATH/menu.sh" ;;
        *) ensure_proxytool ;;
    esac
}

# 处理“服务未运行”的交互逻辑
handle_stopped_service() {
    local service_name=$1
    local display_name=$2
    echo "${display_name} 服务未运行，是否启动服务？ (y/n)"
    read -rp "请输入: " start_input
    if [[ "$start_input" == "y" || "$start_input" == "Y" ]]; then
        systemctl start "$service_name"
        echo "${display_name} 服务已启动。"
    else
        echo "未启动 ${display_name} 服务。"
    fi
}

# --- 核心逻辑 ---

# --- 主程序 ---
# 1. 获取各服务状态
get_service_status "mosdns"; mosdns_status=$?
mosdns_display=$(format_status_for_menu $mosdns_status)

# 处理 Unbound+Redis 复合状态
get_service_status "unbound"; unbound_status=$?
get_service_status "redis-server"; redis_status=$?
if [[ $unbound_status -eq 1 && $redis_status -eq 1 ]]; then 
    unbound_redis_status=1  # 全部运行中
elif [[ $unbound_status -eq 9 && $redis_status -eq 9 ]]; then 
    unbound_redis_status=9  # 全部未安装
else 
    unbound_redis_status=0  # 部分运行
fi
unbound_redis_display=$(format_status_for_menu $unbound_redis_status)

# 获取代理服务状态
get_service_status "sing-box"; singbox_status=$?
singbox_display=$(format_status_for_menu $singbox_status)

get_service_status "mihomo"; mihomo_status=$?
mihomo_display=$(format_status_for_menu $mihomo_status)


# 2. 显示菜单
clear
echo "-------------------------------------------------"
echo -e "${green_text}DNS服务${reset}"
echo "-------------------------------------------------"
echo -e "1. ${yellow_text}Mosdns${reset}          ${mosdns_display}"
echo -e "2. ${yellow_text}Unbound+Redis${reset}   ${unbound_redis_display}"
echo "------------------------------------------------- "
echo -e "${green_text}Proxy代理${reset}"
echo "-------------------------------------------------"
echo -e "3. ${yellow_text}sing-box${reset}        ${singbox_display}"
echo -e "4. ${yellow_text}mihomo${reset}          ${mihomo_display}"
echo "**************************************************"
echo -e "0. ${red_text}卸载核心组件${reset}"
echo -e "999. ${yellow_text}更新脚本${reset}"
echo "================================================="
echo -e "当前机器地址: ${green_text}${local_ip}${reset}"
echo "-------------------------------------------------"
read -rp "请选择: " choice

# 3. 根据选择执行操作
case $choice in
    1)  # MosDNS
        case $mosdns_status in
            1)  # 运行中
                if [[ -d "/cus/mosdns" ]]; then
                    # 魔改UI版
                    cleanup_cmd=". ${DIRPATH}/init.sh mosdns /usr/local/bin/mosdns /cus/mosdns && rm -rf /cus/mosdns && rm -rf /etc/mosdns"
                    handle_running_service "Mosdns (魔改UI版)" "$cleanup_cmd" ". $DIRPATH/mosdns.sh" 
                else
                    # 标准版
                    cleanup_cmd=". ${DIRPATH}/init.sh mosdns /usr/local/bin/mosdns /etc/mosdns && rm -rf /etc/mosdns"
                    handle_running_service "Mosdns (标准版)" "$cleanup_cmd" ". $DIRPATH/mosdns.sh" 
                fi
                ;;
            0) handle_stopped_service "mosdns" "Mosdns" ;;
            9) . "$DIRPATH/mosdns.sh" ;;
        esac
        ;;
    2)  # Unbound+Redis
        case $unbound_redis_status in
            1)  # 全部运行中
                unbound_cleanup=". $DIRPATH/init.sh unbound /usr/local/bin/unbound* /etc/unbound && rm -rf /etc/unbound"
                redis_cleanup=". $DIRPATH/init.sh redis-server /usr/local/bin/redis* /etc/redis && rm -rf /etc/redis"
                handle_running_service "Unbound+Redis" "$unbound_cleanup && $redis_cleanup" ". $DIRPATH/unbound.sh"
                ;;
            0)  # 部分运行或未运行
                echo "Unbound 或 Redis 未完全运行，是否尝试启动？ (y/n)"
                read -rp "请输入: " start_input
                if [[ "${start_input,,}" == "y" ]]; then
                    [[ $unbound_status -ne 1 ]] && systemctl start unbound
                    [[ $redis_status -ne 1 ]] && systemctl start redis
                    echo "Unbound+Redis DNS 服务已尝试启动。"
                else
                    echo "未启动服务。"
                fi
                ;;
            9)  # 未安装
                . "$DIRPATH/unbound.sh" 
                ;;
        esac
        ;;
        
    3)  # sing-box
        case $singbox_status in
            1)  # 运行中
                handle_running_service "sing-box" \
                    ". $DIRPATH/init.sh sing-box /usr/local/bin/sing-box /etc/sing-box && rm -rf /etc/sing-box" \
                    ". $DIRPATH/sing-box.sh" 
                ;;
            0)  # 未运行
                handle_stopped_service "sing-box" "sing-box" 
                ;;
            9)  # 未安装
                . "$DIRPATH/sing-box.sh" 
                ;;
        esac
        ;;
        
    4)  # mihomo
        case $mihomo_status in
            1)  # 运行中
                handle_running_service "mihomo" \
                    ". $DIRPATH/init.sh mihomo /usr/local/bin/mihomo /etc/mihomo && rm -rf /etc/mihomo" \
                    ". $DIRPATH/sing-box.sh mihomo" 
                ;;
            0)  # 未运行
                handle_stopped_service "mihomo" "mihomo" 
                ;;
            9)  # 未安装
                . "$DIRPATH/sing-box.sh" mihomo 
                ;;
        esac
        ;;
    0)  # 卸载核心
        . "$DIRPATH/uninstall.sh"
        ;;
        
    999)  # 更新脚本
        . "$DIRPATH/install.sh"
        ;;
        
    *)
        echo "无效的选项，请重新运行脚本并选择有效的选项。"
        ;;
esac