#!/bin/bash
green_text="\033[32m"
yellow_text="\033[33m"
red_text="\033[31m"
reset="\033[0m" 
DIRPATH="/usr/local/bin/tools"
red() {
    echo -e "\e[31m$1\e[0m"
}

green() {
    echo -e "\e[32m$1\e[0m"
}

yellow() {
    echo -e "\e[33m$1\e[0m"
}

local_ip=$(hostname -I | awk '{print $1}')

check_core_status() {
    local service_status=9  # 初始化为 9，表示未安装

    # 查找已安装的程序
    found_files=$(find /usr/local/bin/ -type f \( -name "mihomo" -o -name "sing-box" -o -name "mosdns"  -o -name "unbound"  -o -name "redis-server" \))

    if [ -z "$found_files" ]; then
        echo -e "${yellow}未检测到已安装的程序${reset}"
        return $service_status
    fi

    # 遍历检查每个已安装的程序
    for file in $found_files; do
        program=$(basename "$file")
        echo -e "\n${program}:"
        case "$program" in
            "sing-box"|"mihomo"|"mosdns"|"unbound"|"redis-server")
                if systemctl is-active --quiet ${program}; then
                    echo -e "  路由服务: ${green_text}运行中${reset}"
                    service_status=1  # 运行中
                else
                    echo -e "  路由服务: ${red_text}未运行${reset}"
                    service_status=0  # 未运行
                fi
                ;;
            "mosdns")
                if systemctl is-active --quiet mosdns; then
                    echo -e "  DNS服务: ${green_text}运行中${reset}"
                    service_status=1
                else
                    echo -e "  DNS服务: ${red_text}未运行${reset}"
                    service_status=0
                fi
                ;;
            "unbound")
                if systemctl is-active --quiet unbound; then
                    echo -e "  DNS服务: ${green_text}运行中${reset}"
                    service_status=1
                else
                    echo -e "  DNS服务: ${red_text}未运行${reset}"
                    service_status=0
                fi
                ;;
            "redis-server")
                if systemctl is-active --quiet redis; then
                    echo -e "  Redis服务: ${green_text}运行中${reset}"
                    service_status=1
                else
                    echo -e "  Redis服务: ${red_text}未运行${reset}"
                    service_status=0
                fi
        esac
    done

    echo -e "\n----------------------------------------"
    return $service_status  # 返回服务状态
}

# 菜单逻辑
echo "-------------------------------------------------"
echo -e "${green_text}DNS服务${reset}"
echo "-------------------------------------------------"
echo -e "1. ${yellow}Mosdns ${reset}"
echo -e "2. ${yellow}Unbound+Redis DNS${reset}"
echo "------------------------------------------------- "
echo -e "${green_text}Proxy代理 sing-box/mihomo ${reset}"
echo -e "3. ${yellow}sing-box ${reset}"
echo -e "4. ${yellow}mihomo ${reset}"
echo "**************************************************"
echo -e "0. ${red}卸载 Sing-Box | Mihomo | Mosdns | Unbound | Redis${reset}"
echo -e "当前机器地址:${green_text}${local_ip}${reset}"
echo "-------------------------------------------------"
check_core_status
service_status=$?  # 获取服务状态
echo "================================================="
echo -e "请选择:"
read choice
case $choice in
    1) 
    if [ "$service_status" -eq 1 ]; then
        echo "Mosdns 服务已运行，继续安装输入 g <覆盖安装>"
        echo -e "输入任意键进入快捷脚本 * "
        echo -e "返回主菜单输入 n ? "
        read -rp "请输入: " input
        case "$input" in
            g) . $DIRPATH/init.sh mosdns /usr/local/bin/mosdns /etc/mosdns  && . $DIRPATH/mosdns.sh ;;
            n) . $DIRPATH/menu.sh ;;
            *) . $DIRPATH/proxytool.sh ;;
        esac
    elif [ "$service_status" -eq 0 ]; then
        echo "Mosdns 服务未运行，是否启动服务？(y/n)"
        read -rp "请输入: " start_input
        if [ "$start_input" = "y" ]; then
            # 启动服务的逻辑
            systemctl start mosdns
            echo "Mosdns 服务已启动。"
        else
            echo "未启动 Mosdns 服务。"
        fi
    else
        . $DIRPATH/mosdns.sh
    fi
        ;;
    2) 
    if [ "$service_status" -eq 1 ]; then
            echo "Unbound+Redis DNS 服务已运行，继续安装输入 g <覆盖安装>"
            echo -e "输入任意键进入快捷脚本 * "
            echo -e "返回主菜单输入 n ? "
        read -rp "请输入: " input
        case "$input" in
            g)  . $DIRPATH/init.sh unbound /usr/local/bin/unbound* /etc/unbound && 
                . $DIRPATH/init.sh redis /usr/local/bin/redis* /etc/redis && 
                . $DIRPATH/unbound.sh ;;
            n) . $DIRPATH/menu.sh ;;
            *) . $DIRPATH/proxytool.sh ;;
        esac
    elif [ "$service_status" -eq 0 ]; then
        echo "Unbound+Redis DNS 服务未运行，是否启动服务？(y/n)"
        read -rp "请输入: " start_input
        if [ "$start_input" = "y" ]; then
            # 启动服务的逻辑
            systemctl start unbound
            systemctl start redis-server
            echo "Unbound+Redis DNS 服务已启动。"
        else
            echo "未启动 Unbound+Redis DNS 服务。"
        fi
    else
        . $DIRPATH/unbound.sh
    fi
        ;;
    3)
    if [ "$service_status" -eq 1 ]; then
        echo "sing-box 服务已运行，继续安装输入 g <覆盖安装>"
        echo -e "输入任意键进入快捷脚本 * "
        echo -e "返回主菜单输入 n ? "
        read -rp "请输入: " input
        case "$input" in
            g) . $DIRPATH/init.sh sing-box /usr/local/bin/sing-box /etc/sing-box /etc/nftables.conf /etc/systemd/system/tproxy-router.service && 
                . $DIRPATH/sing-box.sh ;;
            n) . $DIRPATH/menu.sh ;;
            *) . $DIRPATH/proxytool.sh ;;
        esac
    elif [ "$service_status" -eq 0 ]; then
        echo "sing-box 服务未运行，是否启动服务？(y/n)"
        read -rp "请输入: " start_input
        if [ "$start_input" = "y" ]; then
            # 启动服务的逻辑
            systemctl start sing-box
            echo "sing-box 服务已启动。"
        else
            echo "未启动 sing-box 服务。"
        fi
    else
        . $DIRPATH/sing-box.sh
    fi
        ;;
    4)
    if [ "$service_status" -eq 1 ]; then
        echo "mihomo 服务已运行，继续安装输入 g <覆盖安装>"
        echo -e "输入任意键进入快捷脚本 * "
        echo -e "返回主菜单输入 n ? "
        read -rp "请输入: " input
        case "$input" in
            g)  . $DIRPATH/init.sh mihomo /usr/local/bin/mihomo /etc/mihomo /etc/nftables /etc/systemd/system/tproxy-router.service && 
                . $DIRPATH/mihomo.sh ;;
            n) . $DIRPATH/menu.sh ;;
            *) . $DIRPATH/proxytool.sh ;;
        esac
    elif [ "$service_status" -eq 0 ]; then
        echo "mihomo 服务未运行，是否启动服务？(y/n)"
        read -rp "请输入: " start_input
        if [ "$start_input" = "y" ]; then
            # 启动服务的逻辑
            systemctl start mihomo
            echo "mihomo 服务已启动。"
        else
            echo "未启动 mihomo 服务。"
        fi
    else
        . $DIRPATH/mihomo.sh
    fi
        ;;
    0) 
        . $DIRPATH/uninstall.sh
        ;;
    *)
        echo "无效的选项，请重新运行脚本并选择有效的选项."
        ;;
esac