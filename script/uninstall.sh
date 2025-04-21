#!/bin/bash

    yellow='\033[1;33m'
    green_text='\033[1;32m'
    red_text='\033[1;31m'
    reset='\033[0m'

        echo -e "卸载Sing-Box | Mihomo | Mosdns | Unbound | Redis"
        found_files=$(find /usr/local/bin/ -type f \( -name "mihomo" -o -name "sing-box" -o -name "mosdns" -o -name "unbound" -o -name "redis-server" \))
        if [ -z "$found_files" ]; then
            echo -e "${yellow}[检测结果] 未找到任何已安装的核心程序${reset}"
            return 0
        fi

        # 构建已安装程序数组
        declare -a installed_programs
        echo -e "${yellow}检测到已安装以下核心：${reset}"
        i=1
        for file in $found_files; do
            program=$(basename "$file")
            installed_programs+=("$program")
            echo -e "  ${green_text}$i${reset}) $program"
            ((i++))
        done
        echo -e "  ${green_text}0${reset}) 卸载所有"
        echo -e "  ${green_text}q${reset}) 退出"

        # 获取用户选择
        read -p "请选择要卸载的程序 (0-$((i-1))/q): " choice
        case $choice in
            q|Q) 
                echo "取消卸载"
                return 0
                ;;
            0)  # 卸载所有
                read -p "确认卸载所有程序？(y/n) " confirm
                [[ $confirm != "y" ]] && return 0
                programs_to_uninstall=("${installed_programs[@]}")
                ;;
            [1-9])  # 卸载单个程序
                if [ $choice -le ${#installed_programs[@]} ]; then
                    read -p "确认卸载 ${installed_programs[$((choice-1))]}？(y/n) " confirm
                    [[ $confirm != "y" ]] && return 0
                    programs_to_uninstall=("${installed_programs[$((choice-1))]}")
                else
                    echo -e "${red_text}无效的选项${reset}"
                    return 1
                fi
                ;;
            *)
                echo -e "${red_text}无效的选项${reset}"
                return 1
                ;;
        esac

        # 执行卸载操作
        for program in "${programs_to_uninstall[@]}"; do
            echo -e "${yellow}正在卸载 $program...${reset}"
            case "$program" in
                "mosdns")
                    systemctl disable mosdns > /dev/null 2>&1
                    systemctl stop mosdns  > /dev/null 2>&1
                    rm -rf /etc/mosdns
                    rm -rf /usr/local/bin/mosdns
                    rm -rf /etc/systemd/system/mosdns.service
                    ;;
                "sing-box"|"mihomo")
                    systemctl disable $program  > /dev/null 2>&1
                    systemctl stop $program > /dev/null 2>&1
                    systemctl disable tproxy-router  > /dev/null 2>&1
                    systemctl stop tproxy-router
                    # 如果是最后一个代理程序，清理防火墙规则
                    if ! [ -f "/usr/local/bin/sing-box" ] && ! [ -f "/usr/local/bin/mihomo" ]; then
                        echo " " > "/etc/nftables.conf"
                        nft flush ruleset  > /dev/null 2>&1
                        nft -f /etc/nftables.conf  > /dev/null 2>&1
                    fi
                    rm -rf /etc/$program
                    rm -rf /usr/local/bin/$program
                    rm -rf /etc/systemd/system/$program.service
                    rm -rf /etc/systemd/system/tproxy-router.service
                    ;;
                "unbound")
                    systemctl disable unbound > /dev/null 2>&1
                    systemctl stop unbound > /dev/null 2>&1
                    rm -rf /etc/unbound
                    rm -rf /usr/local/bin/unbound*
                    rm -rf /etc/systemd/system/unbound.service
                    ;;
                "redis-server")
                    systemctl disable redis-server > /dev/null 2>&1
                    systemctl stop redis-server > /dev/null 2>&1
                    rm -rf /etc/redis
                    rm -rf /usr/local/bin/redis-*
                    rm -rf /etc/systemd/system/redis-server.service
            esac
            echo -e "${green_text}$program 已卸载完成${reset}"
        done

        systemctl daemon-reload
        echo -e "${green_text}卸载完成${reset}"
    