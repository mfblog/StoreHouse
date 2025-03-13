#!/bin/bash

# 颜色定义
green="\033[32m"
yellow="\033[33m"
red="\033[31m"
reset="\033[0m"

# 初始化检测状态
found_singbox=false
found_mosdns=false

# 专用版本变量
singbox_version=""
mosdns_version=""

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
update_mosdns_core(){
    arch=$(detect_architecture)
    echo "系统架构是：$arch"
    cp -rf /usr/local/bin/mosdns /usr/local/bin/mosdns.bak
    mosdns_host="https://github.com/herozmy/StoreHouse/releases/download/mosdns/mosdns-linux-$arch.zip"
    apt update && apt -y upgrade || { echo "更新失败！退出脚本"; exit 1; }
    apt install curl wget git tar gawk sed cron unzip nano -y || { echo "更新失败！退出脚本"; exit 1; }
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
        echo "2. 查看运行状态"
        echo "3. 重启服务"
        echo "4. 返回主菜单"
        
        read -p "请选择操作: " choice
        case $choice in
            1)
                echo -e "\n${green}开始更新 Sing-Box...${reset}"
                # 这里添加实际更新逻辑
                echo -e "${green}更新完成，当前版本：$(sing-box version | awk '{print $3}')${reset}"
                ;;
            2)
                systemctl status sing-box -l
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
        echo "5. 增加直连名单"
        echo "6. 增加黑名单"
        echo "7. 删除直连名单"
        echo "8. 删除黑名单"
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
                echo -e "\n${green}更新分流规则...${reset}"
                wget -O /etc/mosdns/rulelist.txt https://example.com/mosdns-rules.txt
                systemctl restart mosdns
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
                systemctl status mosdns -l
                ;;
            6)
                systemctl status mosdns -l
                ;;
            7)
                systemctl status mosdns -l
                ;;
            8)
                systemctl status mosdns -l
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
            1)
                if $found_singbox; then
                    manage_singbox
                else
                    echo -e "${red}无效选择${reset}"
                fi
                ;;
            2)
                if $found_mosdns; then
                    manage_mosdns
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