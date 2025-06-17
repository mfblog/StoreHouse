#!/bin/bash

# --- 变量定义 ---
green_text="\033[32m"
yellow_text="\033[33m"
red_text="\033[31m"
grey_text="\033[90m"
reset="\033[0m"
DIRPATH="/usr/local/bin/tools"


# 获取本机IP
local_ip=$(hostname -I | awk '{print $1}')

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

# 获取服务状态，不输出任何信息，只返回状态码
# 0: 已安装但未运行, 1: 运行中, 9: 未安装
get_service_status() {
    local program_name=$1
    local program_path="/usr/local/bin/$program_name"
    local service_name=$program_name

    # 特殊情况处理
    [ "$program_name" == "redis-server" ] && service_name="redis"

    if [ ! -f "$program_path" ]; then
        return 9 # 未安装
    fi

    if systemctl is-active --quiet "$service_name"; then
        return 1 # 运行中
    else
        return 0 # 未运行
    fi
}

# 根据状态码生成用于菜单显示的文本
format_status_for_menu() {
    local status_code=$1
    case $status_code in
        1) echo -e "${green_text}[运行中]${reset}" ;;
        0) echo -e "${red_text}[未运行]${reset}" ;;
        9) echo -e "${grey_text}[未安装]${reset}" ;;
    esac
}

# 处理“服务已运行”的交互逻辑
handle_running_service() {
    local display_name=$1
    local install_cmd=$2
    local menu_script=$3

    echo -e "${display_name} 服务已运行，继续安装将进行${yellow_text}覆盖安装${reset}。"
    echo -e "输入 ${green_text}g${reset} 进行覆盖安装"
    echo -e "输入 ${green_text}n${reset} 返回主菜单"
    echo -e "输入 ${green_text}任意其他键${reset} 进入 ${display_name} 快捷管理脚本"
    read -rp "请输入: " input
    case "$input" in
        g|G) eval "$install_cmd" && eval "$menu_script" ;; # 执行安装和后续脚本
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

# 1. 在显示菜单前，预先检查所有服务的状态
get_service_status "mosdns"
mosdns_status=$?
mosdns_display=$(format_status_for_menu $mosdns_status)

get_service_status "unbound"
unbound_status=$?
get_service_status "redis-server"
redis_status=$?
# Unbound+Redis 的组合状态
if [ "$unbound_status" -eq 1 ] && [ "$redis_status" -eq 1 ]; then
    unbound_redis_status=1
elif [ "$unbound_status" -eq 9 ] && [ "$redis_status" -eq 9 ]; then
    unbound_redis_status=9
else
    unbound_redis_status=0
fi
unbound_redis_display=$(format_status_for_menu $unbound_redis_status)

get_service_status "sing-box"
singbox_status=$?
singbox_display=$(format_status_for_menu $singbox_status)

get_service_status "mihomo"
mihomo_status=$?
mihomo_display=$(format_status_for_menu $mihomo_status)


# 2. 显示带有状态的菜单
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

# 3. 根据用户的选择和预先获取的状态进行操作
case $choice in
    1)
        case $mosdns_status in
            1) handle_running_service "Mosdns" ". $DIRPATH/init.sh mosdns /usr/local/bin/mosdns /etc/mosdns" ". $DIRPATH/mosdns.sh" ;;
            0) handle_stopped_service "mosdns" "Mosdns" ;;
            9) . "$DIRPATH/mosdns.sh" ;;
        esac
        ;;
    2)
        case $unbound_redis_status in
            1) handle_running_service "Unbound+Redis" ". $DIRPATH/init.sh unbound /usr/local/bin/unbound* /etc/unbound && . $DIRPATH/init.sh redis /usr/local/bin/redis* /etc/redis" ". $DIRPATH/unbound.sh" ;;
            0)
                echo "Unbound 或 Redis 未完全运行，是否尝试启动？ (y/n)"
                read -rp "请输入: " start_input
                if [[ "$start_input" == "y" || "$start_input" == "Y" ]]; then
                    [ "$unbound_status" -ne 1 ] && systemctl start unbound
                    [ "$redis_status" -ne 1 ] && systemctl start redis
                    echo "Unbound+Redis DNS 服务已尝试启动。"
                else
                    echo "未启动服务。"
                fi
                ;;
            9) . "$DIRPATH/unbound.sh" ;;
        esac
        ;;
    3)
        case $singbox_status in
            1) handle_running_service "sing-box" ". $DIRPATH/init.sh sing-box /usr/local/bin/sing-box /etc/sing-box" ". $DIRPATH/sing-box.sh" ;;
            0) handle_stopped_service "sing-box" "sing-box" ;;
            9) . "$DIRPATH/sing-box.sh" ;;
        esac
        ;;
    4)
        case $mihomo_status in
            1) handle_running_service "mihomo" ". $DIRPATH/init.sh mihomo /usr/local/bin/mihomo /etc/mihomo" ". $DIRPATH/sing-box.sh mihomo" ;;
            0) handle_stopped_service "mihomo" "mihomo" ;;
            9) . $DIRPATH/sing-box.sh mihomo ;;
        esac
        ;;
    0)
        . "$DIRPATH/uninstall.sh"
        ;;
    999)
        systemctl stop tproxy-router > /dev/null 2>&1
        . "$DIRPATH/install.sh"
        ;;
    *)
        echo "无效的选项，请重新运行脚本并选择有效的选项."
        ;;
esac