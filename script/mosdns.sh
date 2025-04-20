#!/bin/bash
#####
green_text="\033[32m"
yellow_text="\033[33m"
red_text="\033[31m"
reset="\033[0m" 
sub_host="https://sub-singbox.herozmy.com"
json_file="&file=https://raw.githubusercontent.com/herozmy/StoreHouse/refs/heads/latest/config/sing-box/sing-box.json"
local_ip=$(hostname -I | awk '{print $1}')
DIRPATH="/usr/local/bin/tools/"

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

    check_resolved(){
        if [ -f /etc/systemd/resolved.conf ]; then
            # 检测是否有未注释的 DNSStubListener 行
            dns_stub_listener=$(grep "^DNSStubListener=" /etc/systemd/resolved.conf)
            if [ -z "$dns_stub_listener" ]; then
                # 如果没有找到未注释的 DNSStubListener 行，检查是否有被注释的 DNSStubListener
                commented_dns_stub_listener=$(grep "^#DNSStubListener=" /etc/systemd/resolved.conf)
                if [ -n "$commented_dns_stub_listener" ]; then
                    # 如果找到被注释的 DNSStubListener，取消注释并改为 no
                    sed -i 's/^#DNSStubListener=.*/DNSStubListener=no/' /etc/systemd/resolved.conf
                    systemctl restart systemd-resolved.service
                    green "53端口占用已解除"
                else
                    green "未找到53端口占用配置，无需操作"
                fi
            elif [ "$dns_stub_listener" = "DNSStubListener=yes" ]; then
                # 如果找到 DNSStubListener=yes，则修改为 no
                sed -i 's/^DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf
                systemctl restart systemd-resolved.service
                green "53端口占用已解除"
            elif [ "$dns_stub_listener" = "DNSStubListener=no" ]; then
                # 如果 DNSStubListener 已为 no，提示用户无需修改
                echo -e "${yellow}53端口未被占用，无需操作${reset}"
            fi
        else
            echo -e "${yellow} /etc/systemd/resolved.conf 不存在，无需操作${reset}"
        fi

    }
######主安装脚本
        arch=$(detect_architecture)
        echo "系统架构是：$arch"
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
        echo -e "\n设置时区为Asia/Shanghai"
        timedatectl set-timezone Asia/Shanghai || { echo -e "\e[31m时区设置失败！退出脚本\e[0m"; exit 1; }
        echo -e "\e[32m时区设置成功\e[0m"
        echo -e "\n自定义设置（以下设置可直接回车使用默认值）"
        read -p "输入sing-box/mihomo入站地址（默认10.10.10.147:6666）：" uiport
        uiport="${uiport:-10.10.10.147:6666}"
        echo -e "已设置sing-box/mihomo入站地址：\e[36m$uiport\e[0m"
        check_resolved
        echo "配置mosdns规则"
        sleep 1
        echo -e "请选择Mosdns规则"
        echo -e "
    分流规则:
    0. 退出脚本
    ————————————————
    1. O佬分流规则 <经典稳定>
    2. PH佬分流规则 <越用越快>
    "
        rm -rf .git
        echo && read -p "请输入选择 [0-2]: " num
        case "${num}" in
        0)
            exit 0
            ;;
        1)
            (
                wget --quiet --show-progress -O mosdns.zip https://github.com/herozmy/StoreHouse/raw/refs/heads/latest/config/mosdns/o/mosdns.zip &&
                mkdir -p /etc/mosdns/ &&
                unzip mosdns.zip -d /etc/mosdns/ &&
                rm -f mosdns.zip
            ) || {
                echo "下载或解压失败，请检查网络连接和目标目录权限。"
                exit 1
            }
            ;;
        2)
            (
                wget --quiet --show-progress -O mosdns.zip https://github.com/herozmy/StoreHouse/raw/refs/heads/latest/config/mosdns/ph/mosdns2025302.zip &&
                mkdir -p /etc/mosdns/ &&
                unzip mosdns.zip -d /etc/mosdns/ &&
                mv /etc/mosdns/config_leak.yaml /etc/mosdns/config.yaml &&
                
                rm -f mosdns.zip
            ) || {
                echo "下载或解压失败，请检查网络连接和目标目录权限。"
                exit 1
            }
            ;;
        *)
            echo "请输入正确的数字 [0-2]"
            ;;
        esac
        echo -e "${green_text}Mosdns规则拉取成功${reset}"
        echo -e "${yellow}配置mosdns${reset}"
        sed -i "s/- addr: 10.10.10.147:6666/- addr: ${uiport}/g" /etc/mosdns/config.yaml
        echo -e "${yellow}设置mosdns开机自启动${reset}"
        mosdns service install -d /etc/mosdns -c /etc/mosdns/config.yaml
        echo -e "${green_text}mosdns开机启动完成${reset}"
        sleep 1
        systemctl restart mosdns
