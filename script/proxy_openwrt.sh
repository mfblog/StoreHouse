#!/bin/bash

# 获取当前IP地址
local_ip=$(hostname -I | awk '{print $1}')

# 定义全局颜色变量
green="\033[32m"
yellow="\033[33m"
reset="\033[0m"
red='\033[1;31m'
SERVICES="openclash homeproxy sing-box shadowsocks shadowsocksr v2ray xray smartdns mosdns nikki"
StoreHouse_url="https://raw.githubusercontent.com/herozmy/StoreHouse/refs/heads/latest"
core_url="https://github.com/herozmy/StoreHouse/releases/download"
cus_url="https://raw.githubusercontent.com/herozmy/StoreHouse/refs/heads/latest/config/openwrt/cus.zip"
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
cus_core() {
    wget -O /tmp/cus.zip ${cus_url} || {
        echo -e "${red}下载cus失败${reset}"
        exit 1
    }
    unzip -oq /tmp/cus.zip -d /etc/cus || {
        echo -e "${red}解压cus失败${reset}" 
        exit 1
    }
}

proxy_menu() {
    echo -e "${green}1. 设置代理${reset}"
    echo -e "${green}2. 取消代理${reset}"
    echo -e "${green}3. 查看代理状态${reset}"
    echo -e "${green}4. 退出${reset}"
    read -p "请选择操作: " choice
    case $choice in
        1)
            set_proxy
            ;;
        2)
            unset_proxy
            ;;
        3)
            check_proxy
            ;;
        4)
            exit 0
            ;;
        *)
            echo -e "${red}无效选项${reset}"
            proxy_menu
            ;;
    esac
}

check_firewall_type() {
    # 优先检测nftables
    if command -v nft >/dev/null 2>&1 && [ -x /usr/sbin/nft ]; then
        echo "nftables"
        return 0
    fi

    # 最后检测常规iptables
    if command -v iptables >/dev/null 2>&1; then
        echo "iptables"
        return 0
    fi

    echo "unknown"
    return 1
}

tree_firewall() {
FW_TYPE=$(check_firewall_type)

case "$FW_TYPE" in
    "nftables")
        echo -e "${green}检测到nftables，使用现代防火墙规则${reset}"
        chmod +x /etc/cus/fw/nftables.conf
        nft -f /etc/cus/fw/nftables.conf
        ;;
    "iptables")
        echo -e "${yellow}使用传统iptables规则${reset}"
        # iptables规则设置
        chmod +x /etc/cus/fw/ipset.routerproxy
        chmod +x /etc/cus/fw/ipset.routerproxyv6
        chmod +x /etc/cus/fw/ipset.singboxset
        chmod +x /etc/cus/fw/ipset.singboxset6
        sh /etc/cus/fw/tproxy.sh
        ;;
    *)
        echo -e "${red}未找到可用的防火墙工具！${reset}"
        exit 1
        ;;
    esac
}


## 禁用相关代理服务
disable_proxy_services() {
    echo -e "${YELLOW}正在扫描目标服务...${RESET}"
    for service in $SERVICES; do
        check_service $service
    done
    
    read -p "是否要禁用所有上述服务？[y/N] " confirm
    case $confirm in
        [Yy]* )
            for service in $SERVICES; do
                disable_service $service
            done
            echo -e "\n${GREEN}操作完成！建议：${RESET}"
            echo "1. 重启设备确认效果"
            echo "2. 检查防火墙规则: nft list ruleset"
            echo "3. 验证端口占用: netstat -tuln"
            ;;
        * )
            echo "操作已取消"
            exit 0
            ;;
    esac

}

# 检查服务状态
check_service() {
    local service=$1
    if [ -f "/etc/init.d/$service" ]; then
        if pgrep -f "/etc/init.d/$service" >/dev/null; then
            echo -e "${RED}■${RESET} $service 运行中"
        else
            echo -e "${YELLOW}□${RESET} $service 已安装未运行"
        fi
    else
        echo -e "${GREEN}✓${RESET} $service 未安装"
    fi
}

# 禁用服务
disable_service() {
    local service=$1
    echo -e "\n${YELLOW}处理服务: $service${RESET}"
    
    # 停止运行中的服务
    if [ -f "/etc/init.d/$service" ]; then
        echo "停止服务..."
        /etc/init.d/$service stop 2>/dev/null
            
        # 禁用开机启动
        echo "移除开机启动..."
        /etc/init.d/$service disable 2>/dev/null
        
        # 重命名启动脚本
        mv "/etc/init.d/$service" "/etc/init.d/$service.bak" 2>/dev/null && \
        echo "启动脚本已重命名"
    fi

}
proxy_init() {

    cp /etc/cus/init/* /etc/init.d/
    chmod +x /etc/init.d/mosdns
    chmod +x /etc/init.d/sb
    # 设置开机启动
    /etc/init.d/mosdns enable
    /etc/init.d/sb enable

}
    
 wget_core() {
    mkdir -p /cus/bin
    mkdir -p /cus/singbox
    mkdir -p /cus/mosdns
    arch=$(detect_architecture)

    # 安装mosdns
    echo -e "${yellow}下载mosdns...${reset}"
    wget -O /tmp/mosdns.zip ${core_url}/mosdns/mosdns-linux-$arch.zip || {
        echo -e "${red}mosdns下载失败${reset}"
        exit 1
    }

    unzip -oq /tmp/mosdns.zip -d /tmp/mosdns || {
        echo -e "${red}解压mosdns失败${reset}"
        rm -f /tmp/mosdns.zip
        exit 1
    }

    mv /tmp/mosdns/mosdns /cus/bin/mosdns || {
        echo -e "${red}移动mosdns失败${reset}"
        rm -rf /tmp/mosdns /tmp/mosdns.zip
        exit 1
    }

    chmod +x /cus/bin/mosdns
    rm -rf /tmp/mosdns /tmp/mosdns.zip
    #下载mosdns规则
    unzip -oq /etc/cus/mosdns-openwrt-20250319.zip -d /cus/mosdns
    # 安装sing-box yelnoo核心
    echo -e "${yellow}下载sing-box...${reset}"
    wget -O /tmp/singbox.tar.gz ${core_url}/sing-box-yelnoo/sing-box-yelnoo-linux-${arch}.tar.gz || {
        echo -e "${red}sing-box下载失败${reset}"
        exit 1
    }
    #解压sing-box
    tar -zxvf /tmp/singbox.tar.gz
    mv sing-box /cus/bin/sing-box || {
        echo -e "${red}移动sing-box失败${reset}"
        rm -rf /tmp/singbox /tmp/singbox.tar.gz
        exit 1
    }

    chmod +x /cus/bin/sing-box
    rm -rf /tmp/singbox /tmp/singbox.tar.gz

    #下载sing-box配置
    unzip -oq /etc/cus/singbox-openwrt.zip -d /cus/singbox

 }   


#####主函数
set_proxy() {
#检测代理
check_proxy
#禁用相关代理服务
disable_proxy_services
#下载核心
wget_core
#下载init.d自启动脚本
proxy_init
#设置防火墙
tree_firewall
#设置代理
cp /etc/config/network /etc/config/network.bak
cat /etc/cus/fw/network >> /etc/config/network
}

delete_firewall() {
FW_TYPE=$(check_firewall_type)

case "$FW_TYPE" in
    "nftables")
        nft delete table inet singbox 2>/dev/null
        ;;
    "iptables")
        echo -e "${yellow}使用传统iptables规则${reset}"
        # iptables规则设置
        sh /cus/fw/cleanipt.sh
        ;;
    *)
        echo -e "${red}未找到可用的防火墙工具！${reset}"
        exit 1
        ;;
    esac
}
unset_proxy(){

    mv /etc/config/network.bak /etc/config/network
    delete_firewall
}
proxy_menu

