#!/bin/bash

    yellow='\033[1;33m'
    green_text='\033[1;32m'
    red_text='\033[1;31m'
    blue_text='\033[1;34m'
    reset='\033[0m'

# 系统优化卸载函数
uninstall_system_optimization() {
    local script_path="/usr/local/bin/tools/mosdns_sysctl.sh"
    if [[ -f "$script_path" ]]; then
        bash "$script_path" uninstall
    else
        echo -e "${red_text}错误: 找不到系统优化卸载脚本 $script_path${reset}"
    fi
}

        echo -e "卸载Sing-Box | Mihomo | Mosdns | Unbound | Redis | 系统优化"

        # 检查 sing-box 和 mihomo 是否同时安装 (用于后续判断是否清理公共规则)
        is_singbox_initial_installed=false
        is_mihomo_initial_installed=false

        if find /usr/local/bin/ -type f -name "sing-box" | grep -q .; then
            is_singbox_initial_installed=true
        fi

        if find /usr/local/bin/ -type f -name "mihomo" | grep -q .; then
            is_mihomo_initial_installed=true
        fi

        # 查找所有已安装的核心程序
        found_files=$(find /usr/local/bin/ -type f \( -name "mihomo" -o -name "sing-box" -o -name "mosdns" -o -name "unbound" -o -name "redis-server" \))
        
        # 检查系统优化是否已安装
        sysctl_optimization_installed=false
        if [[ -f "/etc/sysctl.d/99-sysctl.conf" ]] && grep -q "MosDNS 系统优化配置" "/etc/sysctl.d/99-sysctl.conf" 2>/dev/null; then
            sysctl_optimization_installed=true
        fi
        
        if [ -z "$found_files" ] && [ "$sysctl_optimization_installed" = false ]; then
            echo -e "${yellow}[检测结果] 未找到任何已安装的核心程序或系统优化${reset}"
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
        
        # 添加系统优化选项
        if [ "$sysctl_optimization_installed" = true ]; then
            installed_programs+=("system-optimization")
            echo -e "  ${green_text}$i${reset}) 系统优化配置 (BBR + sysctl)"
            ((i++))
        fi
        
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

        # ----------------------------------------------------
        # 判断是否需要清理 tproxy-router.service 和 nft 规则
        # 只有在 sing-box 和 mihomo 都不再存在时才清理
        # ----------------------------------------------------
        clean_proxy_related=false

        # 检查卸载操作后 sing-box 是否仍将保留
        will_singbox_remain=false
        if $is_singbox_initial_installed && ! [[ " ${programs_to_uninstall[@]} " =~ " sing-box " ]]; then
            will_singbox_remain=true
        fi

        # 检查卸载操作后 mihomo 是否仍将保留
        will_mihomo_remain=false
        if $is_mihomo_initial_installed && ! [[ " ${programs_to_uninstall[@]} " =~ " mihomo " ]]; then
            will_mihomo_remain=true
        fi

        # 如果 sing-box 和 mihomo 在卸载后都不再存在，则标记为需要清理代理相关服务和规则
        if ! $will_singbox_remain && ! $will_mihomo_remain; then
            clean_proxy_related=true
            #echo -e "${yellow}检测到所有代理核心都将被卸载或已不存在，将清理 Tproxy 路由和 NFTables 规则.${reset}"
        else
            echo -e "${yellow}检测到至少一个代理核心仍将保留，不清理 Tproxy 路由和 NFTables 规则.${reset}"
        fi

        # 执行卸载操作 (不包含 tproxy/nft 的清理)
        for program in "${programs_to_uninstall[@]}"; do
            echo -e "${yellow}正在卸载 $program...${reset}"
            case "$program" in
                "mosdns")
                    systemctl disable mosdns > /dev/null 2>&1
                    systemctl stop mosdns  > /dev/null 2>&1
                    crontab -l | grep -Fv "/usr/sbin/logrotate -f /etc/logrotate.d/mosdns" | crontab -
                    rm -rf /etc/mosdns
                    rm -rf /usr/local/bin/mosdns
                    rm -rf /etc/systemd/system/mosdns.service
                    ;;
                "sing-box"|"mihomo")
                    # 此处只负责卸载 sing-box 或 mihomo 自身，不处理 tproxy/nft
                    systemctl disable $program  > /dev/null 2>&1
                    systemctl stop $program > /dev/null 2>&1
                    rm -rf /etc/$program
                    rm -rf /usr/local/bin/$program
                    rm -rf /etc/systemd/system/$program.service
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
                    ;;
                "system-optimization")
                    echo -e "${yellow}正在卸载系统优化配置...${reset}"
                    uninstall_system_optimization
                    ;;
            esac
            echo -e "${green_text}$program 已卸载完成${reset}"
        done

        # 最后统一处理 tproxy-router 和 nftables 的清理 (如果需要的话)
        if $clean_proxy_related; then
            #echo -e "${yellow}正在清理 Tproxy 路由和 NFTables 规则...${reset}"
            systemctl disable tproxy-router > /dev/null 2>&1
            systemctl stop tproxy-router > /dev/null 2>&1
            echo " " > "/etc/nftables.conf" # 清空 nftables 规则文件
            nft flush ruleset > /dev/null 2>&1 # 立即刷新内存中的规则
            nft -f /etc/nftables.conf > /dev/null 2>&1 # 从清空的规则文件重新加载
            rm -rf /etc/systemd/system/tproxy-router.service
            #echo -e "${green_text}Tproxy 路由和 NFTables 规则清理完成${reset}"
        fi

        systemctl daemon-reload
        echo -e "${green_text}所有选定程序卸载完成${reset}"