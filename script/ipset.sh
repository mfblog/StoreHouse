#!/bin/bash

# ipset.sh - Debian/Ubuntu网络配置脚本
# 用于配置静态IP地址和恢复DHCP配置

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误: 此脚本需要root权限运行${NC}"
        echo "请使用: sudo $0"
        exit 1
    fi
}



# 获取网络接口数组
get_interface_list() {
    # 使用多种方法获取网络接口
    if command -v ip >/dev/null 2>&1; then
        ip link show 2>/dev/null | grep -E "^[0-9]+:" | grep -v "lo:" | awk -F': ' '{print $2}' | awk '{print $1}'
    elif [ -d "/sys/class/net" ]; then
        # 备用方法：通过sysfs获取
        for iface in /sys/class/net/*; do
            local name=$(basename "$iface")
            [ "$name" != "lo" ] && echo "$name"
        done
    else
        # 最后的备用方法
        ifconfig -a 2>/dev/null | grep -E "^[a-zA-Z0-9]+" | awk '{print $1}' | grep -v "lo" | sed 's/://'
    fi
}

# 显示网络接口列表
show_interfaces() {
    echo -e "${BLUE}可用的网络接口:${NC}"
    echo "=========================="
    local interfaces=($(get_interface_list))
    
    # 调试信息
    if [ "$DEBUG" = "1" ]; then
        echo -e "${YELLOW}调试: 找到 ${#interfaces[@]} 个接口${NC}"
        echo -e "${YELLOW}调试: 接口列表: ${interfaces[*]}${NC}"
    fi
    
    if [ ${#interfaces[@]} -eq 0 ]; then
        echo -e "${RED}未找到可用的网络接口${NC}"
        echo -e "${YELLOW}提示: 尝试运行以下命令来查看所有接口:${NC}"
        echo "  ip link show"
        echo "  ifconfig -a"
        echo "  ls /sys/class/net/"
        return 1
    fi
    
    for i in "${!interfaces[@]}"; do
        local interface="${interfaces[$i]}"
        local status=""
        
        # 尝试获取接口状态
        if command -v ip >/dev/null 2>&1; then
            status=$(ip link show "$interface" 2>/dev/null | grep -o "state [A-Z]*" | awk '{print $2}')
        fi
        
        if [ -z "$status" ] && command -v ifconfig >/dev/null 2>&1; then
            if ifconfig "$interface" 2>/dev/null | grep -q "UP"; then
                status="UP"
            else
                status="DOWN"
            fi
        fi
        
        [ -z "$status" ] && status="UNKNOWN"
        echo "$((i+1)). $interface ($status)"
    done
    
    echo "$((${#interfaces[@]}+1)). 手动输入接口名"
    echo ""
}

# 选择网络接口
select_interface() {
    show_interfaces
    local interfaces=($(get_interface_list))
    
    while true; do
        echo -e "${YELLOW}请选择要配置的网络接口 [1-$((${#interfaces[@]}+1))]:${NC}"
        read -p "> " choice
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le $((${#interfaces[@]}+1)) ]; then
            if [ "$choice" -eq $((${#interfaces[@]}+1)) ]; then
                echo -e "${YELLOW}请输入网络接口名:${NC}"
                read -p "> " INTERFACE
                if [ -z "$INTERFACE" ]; then
                    echo -e "${RED}接口名不能为空${NC}"
                    continue
                fi
            else
                INTERFACE="${interfaces[$((choice-1))]}"
            fi
            
            # 验证接口是否存在
            if ip link show "$INTERFACE" &>/dev/null; then
                echo -e "${GREEN}已选择接口: $INTERFACE${NC}"
                break
            else
                echo -e "${RED}接口 $INTERFACE 不存在${NC}"
                INTERFACE=""
            fi
        else
            echo -e "${RED}无效选择，请重新输入${NC}"
        fi
    done
}

# 验证IPv4地址格式
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        local IFS='.'
        local ip_array=($ip)
        for octet in "${ip_array[@]}"; do
            if [ "$octet" -gt 255 ]; then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# 验证IPv6地址格式
validate_ipv6() {
    local ipv6=$1
    # 基本的IPv6格式检查
    if [[ $ipv6 =~ ^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}$ ]] || \
       [[ $ipv6 =~ ^::$ ]] || \
       [[ $ipv6 =~ ^::([0-9a-fA-F]{0,4}:){0,6}[0-9a-fA-F]{0,4}$ ]] || \
       [[ $ipv6 =~ ^([0-9a-fA-F]{0,4}:){1,6}:$ ]] || \
       [[ $ipv6 =~ ^([0-9a-fA-F]{0,4}:){1,6}:[0-9a-fA-F]{0,4}$ ]]; then
        return 0
    fi
    return 1
}

# 获取网络配置参数
get_network_config() {
    # 获取IP地址
    while true; do
        echo -e "${YELLOW}请输入静态IP地址 [默认: 10.10.10.100]:${NC}"
        read -p "> " IP_ADDRESS
        if [ -z "$IP_ADDRESS" ]; then
            IP_ADDRESS="10.10.10.100"
            echo -e "${GREEN}使用默认IP地址: $IP_ADDRESS${NC}"
            break
        elif validate_ip "$IP_ADDRESS"; then
            break
        else
            echo -e "${RED}无效的IP地址格式，请重新输入${NC}"
        fi
    done
    
    # 获取子网掩码
    while true; do
        echo -e "${YELLOW}请输入子网掩码 (例如: 255.255.255.0 或 CIDR格式如 /24) [默认: /24]:${NC}"
        read -p "> " NETMASK
        if [ -z "$NETMASK" ]; then
            NETMASK="/24"
            break
        elif [[ "$NETMASK" =~ ^/[0-9]{1,2}$ ]]; then
            local cidr=${NETMASK#/}
            if [ "$cidr" -ge 1 ] && [ "$cidr" -le 32 ]; then
                break
            else
                echo -e "${RED}无效的CIDR格式，请输入1-32之间的数字${NC}"
            fi
        elif validate_ip "$NETMASK"; then
            # 转换为CIDR格式
            case "$NETMASK" in
                "255.255.255.0") NETMASK="/24" ;;
                "255.255.0.0") NETMASK="/16" ;;
                "255.0.0.0") NETMASK="/8" ;;
                "255.255.255.128") NETMASK="/25" ;;
                "255.255.255.192") NETMASK="/26" ;;
                "255.255.255.224") NETMASK="/27" ;;
                "255.255.255.240") NETMASK="/28" ;;
                "255.255.255.248") NETMASK="/29" ;;
                "255.255.255.252") NETMASK="/30" ;;
                *) echo -e "${YELLOW}使用自定义子网掩码: $NETMASK${NC}" ;;
            esac
            break
        else
            echo -e "${RED}无效的子网掩码格式${NC}"
        fi
    done
    
    # 获取网关
    while true; do
        echo -e "${YELLOW}请输入网关地址 [默认: 10.10.10.1]:${NC}"
        read -p "> " GATEWAY
        if [ -z "$GATEWAY" ]; then
            GATEWAY="10.10.10.1"
            echo -e "${GREEN}使用默认网关: $GATEWAY${NC}"
            break
        elif validate_ip "$GATEWAY"; then
            break
        else
            echo -e "${RED}无效的网关地址格式，请重新输入${NC}"
        fi
    done
    
    # 获取DNS服务器
    DNS_SERVERS=()
    echo -e "${YELLOW}请输入DNS服务器地址 (可输入多个，按回车确认，输入空行结束):${NC}"
    echo "推荐DNS: 223.5.5.5, 8.8.8.8, 114.114.114.114"
    
    while true; do
        if [ ${#DNS_SERVERS[@]} -eq 0 ]; then
            read -p "DNS 1 [默认: 223.5.5.5]: " dns
        else
            read -p "DNS $((${#DNS_SERVERS[@]}+1)): " dns
        fi
        
        if [ -z "$dns" ]; then
            if [ ${#DNS_SERVERS[@]} -eq 0 ]; then
                DNS_SERVERS=("223.5.5.5")
                echo -e "${GREEN}使用默认DNS: 223.5.5.5${NC}"
            fi
            break
        elif validate_ip "$dns"; then
            DNS_SERVERS+=("$dns")
            echo -e "${GREEN}已添加DNS: $dns${NC}"
        else
            echo -e "${RED}无效的DNS地址格式${NC}"
        fi
    done
    
    # IPv6配置选择
    echo ""
    echo -e "${BLUE}请选择IPv6配置方式:${NC}"
    echo "1. 静态地址配置"
    echo "2. 自动配置 (SLAAC)"
    echo "3. 禁用IPv6"
    echo ""
    
    ENABLE_IPV6=false
    IPV6_METHOD="disabled"
    IPV6_ADDRESS=""
    IPV6_PREFIX=""
    IPV6_GATEWAY=""
    IPV6_DNS_SERVERS=()
    
    while true; do
        read -p "请选择 [1-3]: " ipv6_choice
        
        case "$ipv6_choice" in
            1)
                ENABLE_IPV6=true
                IPV6_METHOD="static"
                echo -e "${GREEN}已选择: 静态地址配置${NC}"
                break
                ;;
            2)
                ENABLE_IPV6=true
                IPV6_METHOD="auto"
                echo -e "${GREEN}已选择: 自动配置 (SLAAC)${NC}"
                break
                ;;
            3)
                ENABLE_IPV6=false
                IPV6_METHOD="disabled"
                echo -e "${YELLOW}已选择: 禁用IPv6${NC}"
                break
                ;;
            *)
                echo -e "${RED}无效选择，请输入1-3${NC}"
                ;;
        esac
    done
        
    # 如果选择静态配置，获取具体配置参数
    if [ "$IPV6_METHOD" = "static" ]; then
        # 获取IPv6地址
        while true; do
            echo -e "${YELLOW}请输入IPv6地址 [默认: dc00::8888]:${NC}"
            read -p "> " IPV6_ADDRESS
            if [ -z "$IPV6_ADDRESS" ]; then
                IPV6_ADDRESS="dc00::8888"
                echo -e "${GREEN}使用默认IPv6地址: $IPV6_ADDRESS${NC}"
                break
            elif validate_ipv6 "$IPV6_ADDRESS"; then
                break
            else
                echo -e "${RED}无效的IPv6地址格式，请重新输入${NC}"
            fi
        done
        
        # 获取IPv6前缀长度
        while true; do
            echo -e "${YELLOW}请输入IPv6前缀长度 (例如: /64) [默认: /64]:${NC}"
            read -p "> " IPV6_PREFIX
            if [ -z "$IPV6_PREFIX" ]; then
                IPV6_PREFIX="/64"
                break
            elif [[ "$IPV6_PREFIX" =~ ^/[0-9]{1,3}$ ]]; then
                local prefix=${IPV6_PREFIX#/}
                if [ "$prefix" -ge 1 ] && [ "$prefix" -le 128 ]; then
                    break
                else
                    echo -e "${RED}无效的前缀长度，请输入1-128之间的数字${NC}"
                fi
            else
                echo -e "${RED}无效的前缀格式，请使用 /数字 格式${NC}"
            fi
        done
        
        # 获取IPv6网关
        echo -e "${YELLOW}请输入IPv6网关地址 [默认: dc00::1] (直接回车跳过):${NC}"
        read -p "> " IPV6_GATEWAY
        if [ -z "$IPV6_GATEWAY" ]; then
            IPV6_GATEWAY="dc00::1"
            echo -e "${GREEN}使用默认IPv6网关: $IPV6_GATEWAY${NC}"
        elif ! validate_ipv6 "$IPV6_GATEWAY"; then
            echo -e "${RED}无效的IPv6网关地址格式，将跳过网关配置${NC}"
            IPV6_GATEWAY=""
        fi
    fi
    
    # 对于所有启用IPv6的配置方式，都可以设置DNS服务器
    if [ "$ENABLE_IPV6" = true ]; then
        echo ""
        echo -e "${BLUE}IPv6 DNS配置:${NC}"
        echo -e "${YELLOW}默认情况下，IPv6将使用已配置的IPv4 DNS服务器${NC}"
        echo -e "${YELLOW}是否要设置专用的IPv6 DNS服务器? 默认N [y/N]:${NC}"
        read -p "> " set_ipv6_dns
        
        if [[ "$set_ipv6_dns" =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}请输入IPv6 DNS服务器地址 (可输入多个，按回车确认，输入空行结束):${NC}"
            echo "常用IPv6 DNS: 2001:4860:4860::8888, 2001:4860:4860::8844, 2606:4700:4700::1111"
            
            while true; do
                read -p "IPv6 DNS $((${#IPV6_DNS_SERVERS[@]}+1)): " ipv6_dns
                if [ -z "$ipv6_dns" ]; then
                    break
                elif validate_ipv6 "$ipv6_dns"; then
                    IPV6_DNS_SERVERS+=("$ipv6_dns")
                    echo -e "${GREEN}已添加IPv6 DNS: $ipv6_dns${NC}"
                else
                    echo -e "${RED}无效的IPv6 DNS地址格式${NC}"
                fi
            done
        else
            echo -e "${GREEN}将使用IPv4 DNS服务器处理IPv6域名解析${NC}"
        fi
        
        case "$IPV6_METHOD" in
            "static")
                echo -e "${GREEN}IPv6静态配置已设置${NC}"
                ;;
            "auto")
                echo -e "${GREEN}IPv6自动配置 (SLAAC) 已设置${NC}"
                ;;
        esac
    fi
}

# 备份现有配置
backup_config() {
    local backup_dir="/etc/netplan/backup_$(date +%Y%m%d_%H%M%S)"
    echo -e "${BLUE}备份现有网络配置到: $backup_dir${NC}"
    
    mkdir -p "$backup_dir"
    
    # 备份netplan配置
    if [ -d "/etc/netplan" ]; then
        cp -r /etc/netplan/*.yaml "$backup_dir/" 2>/dev/null || true
    fi
    
    # 备份NetworkManager配置
    if [ -d "/etc/NetworkManager/system-connections" ]; then
        mkdir -p "$backup_dir/NetworkManager"
        cp -r /etc/NetworkManager/system-connections/* "$backup_dir/NetworkManager/" 2>/dev/null || true
    fi
    
    # 备份resolv.conf
    cp /etc/resolv.conf "$backup_dir/" 2>/dev/null || true
    
    echo -e "${GREEN}备份完成${NC}"
}

# 检测网络配置方式
detect_network_manager() {
    if systemctl is-active --quiet NetworkManager; then
        echo "NetworkManager"
    elif systemctl is-active --quiet systemd-networkd; then
        echo "systemd-networkd"
    elif [ -d "/etc/netplan" ] && ls /etc/netplan/*.yaml &>/dev/null; then
        echo "netplan"
    else
        echo "interfaces"
    fi
}

# 使用Netplan配置网络
configure_netplan() {
    local config_file="/etc/netplan/01-static.yaml"
    
    echo -e "${BLUE}使用Netplan配置网络...${NC}"
    
    # 删除现有的netplan配置
    rm -f /etc/netplan/*.yaml
    
    # 创建新的配置文件
    cat > "$config_file" << EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $INTERFACE:
      dhcp4: false
EOF

    # 配置IPv6
    if [ "$ENABLE_IPV6" = true ]; then
        case "$IPV6_METHOD" in
            "static")
                echo "      dhcp6: false" >> "$config_file"
                echo "      accept-ra: false" >> "$config_file"
                ;;
            "auto")
                echo "      dhcp6: false" >> "$config_file"
                echo "      accept-ra: true" >> "$config_file"
                ;;
        esac
    else
        echo "      dhcp6: false" >> "$config_file"
        echo "      accept-ra: false" >> "$config_file"
        echo "      link-local: []" >> "$config_file"
    fi
    
    # 添加IPv4地址
    echo "      addresses:" >> "$config_file"
    echo "        - $IP_ADDRESS$NETMASK" >> "$config_file"
    
    # 添加IPv6静态地址（如果是静态配置）
    if [ "$ENABLE_IPV6" = true ] && [ "$IPV6_METHOD" = "static" ]; then
        echo "        - $IPV6_ADDRESS$IPV6_PREFIX" >> "$config_file"
    fi
    
    # 添加网关
    echo "      gateway4: $GATEWAY" >> "$config_file"
    if [ "$ENABLE_IPV6" = true ] && [ "$IPV6_METHOD" = "static" ] && [ -n "$IPV6_GATEWAY" ]; then
        echo "      gateway6: $IPV6_GATEWAY" >> "$config_file"
    fi
    
    # 添加DNS配置
    echo "      nameservers:" >> "$config_file"
    echo "        addresses:" >> "$config_file"
    
    # 添加IPv4 DNS服务器
    for dns in "${DNS_SERVERS[@]}"; do
        echo "          - $dns" >> "$config_file"
    done
    
    # 添加IPv6 DNS服务器（如果有）
    if [ "$ENABLE_IPV6" = true ] && [ ${#IPV6_DNS_SERVERS[@]} -gt 0 ]; then
        for ipv6_dns in "${IPV6_DNS_SERVERS[@]}"; do
            echo "          - $ipv6_dns" >> "$config_file"
        done
    fi
    
    # 如果IPv6启用但没有专用DNS，添加注释说明
    if [ "$ENABLE_IPV6" = true ] && [ ${#IPV6_DNS_SERVERS[@]} -eq 0 ]; then
        echo "      # IPv6将使用IPv4 DNS服务器进行域名解析" >> "$config_file"
    fi
    
    # 如果禁用IPv6，添加sysctl参数
    if [ "$ENABLE_IPV6" = false ]; then
        cat >> "$config_file" << EOF
      match:
        driver: "*"
      parameters:
        ipv6.disable: 1
EOF
    fi
    
    echo -e "${GREEN}Netplan配置文件已创建: $config_file${NC}"
    
    # 应用配置
    echo -e "${BLUE}应用网络配置...${NC}"
    netplan apply
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}网络配置应用成功${NC}"
        
        # 如果禁用IPv6，额外设置sysctl参数
        if [ "$ENABLE_IPV6" = false ]; then
            echo -e "${BLUE}禁用IPv6...${NC}"
            echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.conf
            echo "net.ipv6.conf.default.disable_ipv6 = 1" >> /etc/sysctl.conf
            echo "net.ipv6.conf.$INTERFACE.disable_ipv6 = 1" >> /etc/sysctl.conf
            sysctl -p >/dev/null 2>&1
        fi
    else
        echo -e "${RED}网络配置应用失败${NC}"
        return 1
    fi
}

# 使用传统interfaces文件配置网络
configure_interfaces() {
    local config_file="/etc/network/interfaces"
    
    echo -e "${BLUE}使用传统interfaces文件配置网络...${NC}"
    
    # 备份原配置
    cp "$config_file" "${config_file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # 创建新配置
    cat > "$config_file" << EOF
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface - IPv4
auto $INTERFACE
iface $INTERFACE inet static
    address $IP_ADDRESS$NETMASK
    gateway $GATEWAY
EOF

    # 添加IPv6配置（如果启用）
    if [ "$ENABLE_IPV6" = true ]; then
        case "$IPV6_METHOD" in
            "static")
                cat >> "$config_file" << EOF

# IPv6 static configuration for $INTERFACE
iface $INTERFACE inet6 static
    address $IPV6_ADDRESS$IPV6_PREFIX
EOF
                # 添加IPv6网关（如果有）
                if [ -n "$IPV6_GATEWAY" ]; then
                    echo "    gateway $IPV6_GATEWAY" >> "$config_file"
                fi
                
                # 添加IPv6启用命令
                cat >> "$config_file" << EOF
    up echo 0 > /proc/sys/net/ipv6/conf/$INTERFACE/disable_ipv6
    up echo 0 > /proc/sys/net/ipv6/conf/all/disable_ipv6
    up echo 0 > /proc/sys/net/ipv6/conf/default/disable_ipv6
EOF
                ;;
            "auto")
                cat >> "$config_file" << EOF

# IPv6 auto configuration (SLAAC) for $INTERFACE
iface $INTERFACE inet6 auto
    up echo 0 > /proc/sys/net/ipv6/conf/$INTERFACE/disable_ipv6
    up echo 0 > /proc/sys/net/ipv6/conf/all/disable_ipv6
    up echo 0 > /proc/sys/net/ipv6/conf/default/disable_ipv6
    up echo 2 > /proc/sys/net/ipv6/conf/$INTERFACE/accept_ra
    up echo 1 > /proc/sys/net/ipv6/conf/$INTERFACE/autoconf
EOF
                ;;
        esac
    else
        # 禁用IPv6
        cat >> "$config_file" << EOF

# Disable IPv6 for $INTERFACE
iface $INTERFACE inet6 static
    up echo 1 > /proc/sys/net/ipv6/conf/$INTERFACE/disable_ipv6
    up echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6
    up echo 1 > /proc/sys/net/ipv6/conf/default/disable_ipv6
EOF
    fi
    
    # 配置DNS
    cat > /etc/resolv.conf << EOF
# Generated by ipset.sh
# IPv4 DNS服务器
EOF
    
    # 添加IPv4 DNS服务器
    for dns in "${DNS_SERVERS[@]}"; do
        echo "nameserver $dns" >> /etc/resolv.conf
    done
    
    # 添加IPv6 DNS服务器（如果有）
    if [ "$ENABLE_IPV6" = true ] && [ ${#IPV6_DNS_SERVERS[@]} -gt 0 ]; then
        echo "# IPv6 DNS服务器" >> /etc/resolv.conf
        for ipv6_dns in "${IPV6_DNS_SERVERS[@]}"; do
            echo "nameserver $ipv6_dns" >> /etc/resolv.conf
        done
    elif [ "$ENABLE_IPV6" = true ]; then
        echo "# IPv6将使用上述IPv4 DNS服务器进行域名解析" >> /etc/resolv.conf
    fi
    
    # 如果禁用IPv6，设置sysctl参数
    if [ "$ENABLE_IPV6" = false ]; then
        echo -e "${BLUE}配置IPv6禁用参数...${NC}"
        cat >> /etc/sysctl.conf << EOF
# Disable IPv6 - added by ipset.sh
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.$INTERFACE.disable_ipv6 = 1
EOF
    fi
    
    echo -e "${GREEN}网络配置文件已更新: $config_file${NC}"
    

    
    # 应用sysctl设置
    if [ "$ENABLE_IPV6" = false ]; then
        sysctl -p >/dev/null 2>&1
    elif [ "$ENABLE_IPV6" = true ]; then
        # 确保IPv6已启用
        echo 0 > /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || true
        echo 0 > /proc/sys/net/ipv6/conf/default/disable_ipv6 2>/dev/null || true
        echo 0 > /proc/sys/net/ipv6/conf/$INTERFACE/disable_ipv6 2>/dev/null || true
    fi
    
    # 验证配置文件语法
    echo -e "${BLUE}验证网络配置文件语法...${NC}"
    if ! ifup --no-act -a >/dev/null 2>&1; then
        echo -e "${RED}配置文件语法错误！${NC}"
        echo -e "${YELLOW}错误详情:${NC}"
        ifup --no-act -a 2>&1 | head -10
        echo ""
        echo -e "${YELLOW}恢复备份配置...${NC}"
        if [ -f "${config_file}.backup."* ]; then
            local backup_file=$(ls -t "${config_file}.backup."* | head -1)
            cp "$backup_file" "$config_file"
            echo -e "${GREEN}已恢复备份配置${NC}"
        fi
        return 1
    fi
    
    # 重启网络服务
    echo -e "${BLUE}重启网络服务...${NC}"
    systemctl restart networking
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}网络服务重启成功${NC}"
    else
        echo -e "${RED}网络服务重启失败${NC}"
        echo -e "${YELLOW}查看错误详情:${NC}"
        systemctl status networking.service --no-pager -l | tail -10
        echo ""
        echo -e "${YELLOW}查看日志:${NC}"
        journalctl -xeu networking.service --no-pager -l | tail -10
        echo ""
        echo -e "${YELLOW}恢复备份配置...${NC}"
        if [ -f "${config_file}.backup."* ]; then
            local backup_file=$(ls -t "${config_file}.backup."* | head -1)
            cp "$backup_file" "$config_file"
            systemctl restart networking
            echo -e "${GREEN}已恢复备份配置${NC}"
        fi
        return 1
    fi
}

# 使用NetworkManager配置网络
configure_networkmanager() {
    echo -e "${BLUE}使用NetworkManager配置网络...${NC}"
    
    # 删除现有连接
    nmcli connection delete "$INTERFACE" 2>/dev/null || true
    
    # 准备IPv6配置参数
    local ipv6_method="disabled"
    local ipv6_addresses=""
    local ipv6_gateway=""
    local ipv6_dns=""
    
    if [ "$ENABLE_IPV6" = true ]; then
        case "$IPV6_METHOD" in
            "static")
                ipv6_method="manual"
                ipv6_addresses="$IPV6_ADDRESS$IPV6_PREFIX"
                [ -n "$IPV6_GATEWAY" ] && ipv6_gateway="$IPV6_GATEWAY"
                ;;
            "auto")
                ipv6_method="auto"
                ;;
        esac
        
        if [ ${#IPV6_DNS_SERVERS[@]} -gt 0 ]; then
            ipv6_dns="$(IFS=,; echo "${IPV6_DNS_SERVERS[*]}")"
        fi
    fi
    
    # 构建nmcli命令
    local nmcli_cmd="nmcli connection add type ethernet con-name '$INTERFACE' ifname '$INTERFACE'"
    nmcli_cmd="$nmcli_cmd ipv4.method manual"
    nmcli_cmd="$nmcli_cmd ipv4.addresses '$IP_ADDRESS$NETMASK'"
    nmcli_cmd="$nmcli_cmd ipv4.gateway '$GATEWAY'"
    nmcli_cmd="$nmcli_cmd ipv4.dns '$(IFS=,; echo "${DNS_SERVERS[*]}")'"
    nmcli_cmd="$nmcli_cmd ipv6.method '$ipv6_method'"
    
    if [ "$ENABLE_IPV6" = true ]; then
        # 只有静态配置才需要设置地址和网关
        if [ "$IPV6_METHOD" = "static" ]; then
            nmcli_cmd="$nmcli_cmd ipv6.addresses '$ipv6_addresses'"
            [ -n "$ipv6_gateway" ] && nmcli_cmd="$nmcli_cmd ipv6.gateway '$ipv6_gateway'"
        fi
        
        # DNS可以为所有IPv6配置方式设置
        [ -n "$ipv6_dns" ] && nmcli_cmd="$nmcli_cmd ipv6.dns '$ipv6_dns'"
    fi
    
    # 执行配置命令
    echo -e "${BLUE}执行NetworkManager配置...${NC}"
    eval "$nmcli_cmd"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}NetworkManager配置成功${NC}"
        
        # 如果禁用IPv6，设置额外的sysctl参数
        if [ "$ENABLE_IPV6" = false ]; then
            echo -e "${BLUE}禁用IPv6...${NC}"
            echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.conf
            echo "net.ipv6.conf.default.disable_ipv6 = 1" >> /etc/sysctl.conf
            echo "net.ipv6.conf.$INTERFACE.disable_ipv6 = 1" >> /etc/sysctl.conf
            sysctl -p >/dev/null 2>&1
        fi
        
        # 激活连接
        nmcli connection up "$INTERFACE"
    else
        echo -e "${RED}NetworkManager配置失败${NC}"
        return 1
    fi
}

# 主配置函数
configure_network() {
    local manager=$(detect_network_manager)
    
    echo -e "${BLUE}检测到网络管理器: $manager${NC}"
    
    case "$manager" in
        "netplan")
            configure_netplan
            ;;
        "NetworkManager")
            configure_networkmanager
            ;;
        "interfaces")
            configure_interfaces
            ;;
        *)
            echo -e "${YELLOW}未检测到网络管理器，使用默认配置方式${NC}"
            configure_interfaces
            ;;
    esac
}

# 显示配置摘要
show_config_summary() {
    echo ""
    echo -e "${GREEN}网络配置摘要:${NC}"
    echo "=========================="
    echo "接口: $INTERFACE"
    echo "IPv4地址: $IP_ADDRESS$NETMASK"
    echo "IPv4网关: $GATEWAY"
    echo "IPv4 DNS: ${DNS_SERVERS[*]}"
    
    if [ "$ENABLE_IPV6" = true ]; then
        echo "IPv6启用: 是"
        case "$IPV6_METHOD" in
            "static")
                echo "IPv6配置: 静态地址"
                echo "IPv6地址: $IPV6_ADDRESS$IPV6_PREFIX"
                [ -n "$IPV6_GATEWAY" ] && echo "IPv6网关: $IPV6_GATEWAY"
                ;;
            "auto")
                echo "IPv6配置: 自动配置 (SLAAC)"
                ;;
        esac
        if [ ${#IPV6_DNS_SERVERS[@]} -gt 0 ]; then
            echo "IPv6 DNS: ${IPV6_DNS_SERVERS[*]}"
        else
            echo "IPv6 DNS: 使用IPv4 DNS服务器"
        fi
    else
        echo "IPv6启用: 否 (将被禁用)"
    fi
    echo "=========================="
}



# 显示当前网络状态
show_current_status() {
    local interface=$1
    echo -e "${BLUE}当前网络状态 ($interface):${NC}"
    
    # 检测配置类型
    local config_type="未知"
    if check_dhcp_status "$interface" 2>/dev/null; then
        config_type="${YELLOW}DHCP${NC}"
    else
        config_type="${BLUE}静态${NC}"
    fi
    echo -e "  配置类型: $config_type"
    
    # 显示IP地址
    local ipv4_addr=$(ip -4 addr show "$interface" 2>/dev/null | grep inet | awk '{print $2}' | head -1)
    if [ -n "$ipv4_addr" ]; then
        echo -e "  IPv4: ${GREEN}$ipv4_addr${NC}"
    else
        echo -e "  IPv4: ${RED}未配置${NC}"
    fi
    
    # 显示IPv6地址
    local ipv6_addr=$(ip -6 addr show "$interface" 2>/dev/null | grep inet6 | grep -v "scope link" | awk '{print $2}' | head -1)
    if [ -n "$ipv6_addr" ]; then
        echo -e "  IPv6: ${GREEN}$ipv6_addr${NC}"
    else
        echo -e "  IPv6: ${RED}未配置/已禁用${NC}"
    fi
    
    # 显示网关
    local gateway=$(ip route show default 2>/dev/null | awk '{print $3}' | head -1)
    if [ -n "$gateway" ]; then
        echo -e "  网关: ${GREEN}$gateway${NC}"
    else
        echo -e "  网关: ${RED}未配置${NC}"
    fi
    
    # 显示DNS
    local dns_servers=$(cat /etc/resolv.conf 2>/dev/null | grep "^nameserver" | awk '{print $2}' | tr '\n' ' ')
    if [ -n "$dns_servers" ]; then
        echo -e "  DNS: ${GREEN}$dns_servers${NC}"
    else
        echo -e "  DNS: ${RED}未配置${NC}"
    fi
    echo ""
}

# 主菜单
main_menu() {
    while true; do
        echo ""
        echo -e "${BLUE}Debian/Ubuntu网络配置工具${NC}"
        echo "=========================="
        
        # 获取第一个可用的网络接口来显示状态
        local first_interface=$(get_interface_list | head -1)
        if [ -n "$first_interface" ]; then
            show_current_status "$first_interface"
        fi
        
        echo "1. 配置静态网络"
        echo "2. 恢复DHCP配置"
        echo "3. 退出"
        echo "i. 显示详细网络信息"
        echo ""
        
        read -p "请选择操作 [1-3/i]: " choice
        
        case $choice in
            1)
                echo -e "${BLUE}开始配置静态网络...${NC}"
                select_interface
                
                # 显示选中接口的当前状态
                echo ""
                echo -e "${BLUE}选中接口 $INTERFACE 的当前状态:${NC}"
                show_current_status "$INTERFACE"
                
                get_network_config
                show_config_summary
                
                echo ""
                echo -e "${YELLOW}确认要应用这些设置吗? [y/N]:${NC}"
                read -p "> " confirm
                
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    backup_config
                    configure_network
                    echo -e "${GREEN}网络配置完成${NC}"
                else
                    echo -e "${YELLOW}配置已取消${NC}"
                fi
                ;;
            2)
                restore_dhcp
                ;;
            3)
                echo -e "${GREEN}退出程序${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选择，请重新输入${NC}"
                ;;
        esac
    done
}

# 恢复DHCP配置 - Netplan方式
restore_dhcp_netplan() {
    local interface=$1
    local config_file="/etc/netplan/01-dhcp.yaml"
    
    echo -e "${BLUE}使用Netplan恢复DHCP配置...${NC}"
    
    # 删除现有的静态配置
    rm -f /etc/netplan/*.yaml
    
    # 创建DHCP配置文件
    cat > "$config_file" << EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $interface:
      dhcp4: true
      dhcp6: false
EOF
    
    echo -e "${GREEN}Netplan DHCP配置文件已创建: $config_file${NC}"
    
    # 应用配置
    echo -e "${BLUE}应用DHCP配置...${NC}"
    netplan apply
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}DHCP配置应用成功${NC}"
        return 0
    else
        echo -e "${RED}DHCP配置应用失败${NC}"
        return 1
    fi
}

# 恢复DHCP配置 - NetworkManager方式
restore_dhcp_networkmanager() {
    local interface=$1
    
    echo -e "${BLUE}使用NetworkManager恢复DHCP配置...${NC}"
    
    # 删除现有连接
    nmcli connection delete "$interface" 2>/dev/null || true
    
    # 创建新的DHCP连接
    nmcli connection add type ethernet \
        con-name "$interface" \
        ifname "$interface" \
        ipv4.method auto \
        ipv6.method auto
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}NetworkManager DHCP配置成功${NC}"
        # 激活连接
        nmcli connection up "$interface"
        return 0
    else
        echo -e "${RED}NetworkManager DHCP配置失败${NC}"
        return 1
    fi
}

# 恢复DHCP配置 - 传统interfaces方式
restore_dhcp_interfaces() {
    local interface=$1
    local config_file="/etc/network/interfaces"
    
    echo -e "${BLUE}使用传统interfaces文件恢复DHCP配置...${NC}"
    
    # 备份原配置
    cp "$config_file" "${config_file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # 创建DHCP配置
    cat > "$config_file" << EOF
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface - DHCP
auto $interface
iface $interface inet dhcp
EOF
    
    echo -e "${GREEN}网络配置文件已更新为DHCP: $config_file${NC}"
    
    # 重启网络服务
    echo -e "${BLUE}重启网络服务...${NC}"
    systemctl restart networking
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}网络服务重启成功${NC}"
        return 0
    else
        echo -e "${RED}网络服务重启失败${NC}"
        return 1
    fi
}

# 恢复DHCP配置主函数
restore_dhcp_config() {
    local interface=$1
    local manager=$(detect_network_manager)
    
    echo -e "${BLUE}检测到网络管理器: $manager${NC}"
    echo -e "${BLUE}为接口 $interface 恢复DHCP配置...${NC}"
    
    case "$manager" in
        "netplan")
            restore_dhcp_netplan "$interface"
            ;;
        "NetworkManager")
            restore_dhcp_networkmanager "$interface"
            ;;
        "interfaces")
            restore_dhcp_interfaces "$interface"
            ;;
        *)
            echo -e "${YELLOW}未检测到网络管理器，使用默认方式${NC}"
            restore_dhcp_interfaces "$interface"
            ;;
    esac
}

# 检查接口是否已经是DHCP配置
check_dhcp_status() {
    local interface=$1
    local manager=$(detect_network_manager)
    
    case "$manager" in
        "netplan")
            if [ -f "/etc/netplan/01-dhcp.yaml" ] || grep -q "dhcp4: true" /etc/netplan/*.yaml 2>/dev/null; then
                return 0
            fi
            ;;
        "NetworkManager")
            if nmcli connection show "$interface" 2>/dev/null | grep -q "ipv4.method.*auto"; then
                return 0
            fi
            ;;
        "interfaces")
            if grep -q "iface $interface inet dhcp" /etc/network/interfaces 2>/dev/null; then
                return 0
            fi
            ;;
    esac
    return 1
}

# 恢复DHCP功能主流程
restore_dhcp() {
    echo -e "${BLUE}恢复DHCP配置${NC}"
    echo "=========================="
    
    # 选择要恢复的网络接口
    show_interfaces
    local interfaces=($(get_interface_list))
    
    if [ ${#interfaces[@]} -eq 0 ]; then
        echo -e "${RED}未找到可用的网络接口${NC}"
        return 1
    fi
    
    local selected_interface=""
    
    while true; do
        echo -e "${YELLOW}请选择要恢复DHCP的网络接口 [1-$((${#interfaces[@]}+1))]:${NC}"
        read -p "> " choice
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le $((${#interfaces[@]}+1)) ]; then
            if [ "$choice" -eq $((${#interfaces[@]}+1)) ]; then
                echo -e "${YELLOW}请输入网络接口名:${NC}"
                read -p "> " selected_interface
                if [ -z "$selected_interface" ]; then
                    echo -e "${RED}接口名不能为空${NC}"
                    continue
                fi
            else
                selected_interface="${interfaces[$((choice-1))]}"
            fi
            
            # 验证接口是否存在
            if ip link show "$selected_interface" &>/dev/null; then
                echo -e "${GREEN}已选择接口: $selected_interface${NC}"
                
                # 显示选中接口的当前状态
                echo ""
                show_current_status "$selected_interface"
                
                # 检查是否已经是DHCP配置
                if check_dhcp_status "$selected_interface"; then
                    echo -e "${YELLOW}注意: 接口 $selected_interface 似乎已经配置为DHCP${NC}"
                fi
                break
            else
                echo -e "${RED}接口 $selected_interface 不存在${NC}"
                selected_interface=""
            fi
        else
            echo -e "${RED}无效选择，请重新输入${NC}"
        fi
    done
    
    # 显示当前接口配置
    echo ""
    echo -e "${BLUE}当前接口 $selected_interface 的配置:${NC}"
    echo "=========================="
    ip addr show "$selected_interface" 2>/dev/null || echo "无法显示接口信息"
    echo ""
    
    # 确认恢复DHCP
    echo -e "${YELLOW}确认要将接口 $selected_interface 恢复为DHCP配置吗? [y/N]:${NC}"
    read -p "> " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        # 备份当前配置
        backup_config
        
        # 释放当前IP地址（如果有的话）
        echo -e "${BLUE}释放当前IP地址...${NC}"
        dhclient -r "$selected_interface" 2>/dev/null || true
        ip addr flush dev "$selected_interface" 2>/dev/null || true
        
        # 恢复DHCP配置
        restore_dhcp_config "$selected_interface"
        
        if [ $? -eq 0 ]; then
            echo ""
            echo -e "${GREEN}DHCP配置恢复成功${NC}"
            
            # 手动触发DHCP请求
            echo -e "${BLUE}触发DHCP请求...${NC}"
            if command -v dhclient >/dev/null 2>&1; then
                dhclient "$selected_interface" 2>/dev/null &
            elif command -v dhcpcd >/dev/null 2>&1; then
                dhcpcd "$selected_interface" 2>/dev/null &
            fi
            
            # 等待一段时间让DHCP生效
            echo -e "${BLUE}等待DHCP获取IP地址...${NC}"
            sleep 8
            
            # 显示新的网络配置
            echo ""
            echo -e "${BLUE}新的网络配置:${NC}"
            echo "=========================="
            ip addr show "$selected_interface" 2>/dev/null || echo "无法显示接口信息"
            
            # 测试网络连接
            echo ""
            test_network
        else
            echo -e "${RED}DHCP配置恢复失败${NC}"
        fi
    else
        echo -e "${YELLOW}DHCP恢复已取消${NC}"
    fi
}





# 主程序
main() {
    # 检查是否启用调试模式
    if [ "$1" = "--debug" ] || [ "$1" = "-d" ]; then
        export DEBUG=1
        shift
        echo -e "${YELLOW}调试模式已启用${NC}"
    fi
    
    check_root
    
    # 如果有命令行参数，直接执行
    if [ $# -gt 0 ]; then
        case "$1" in
            "restore-dhcp"|"dhcp")
                restore_dhcp
                ;;
            *)
                echo "用法: $0 [--debug] [命令]"
                echo "命令:"
                echo "  restore-dhcp  - 恢复DHCP配置"
                echo "  (无参数)      - 进入交互模式"
                echo ""
                echo "IPv6配置选项:"
                echo "  1. 静态地址配置   - 手动设置IPv6地址、网关"
                echo "  2. 自动配置(SLAAC) - 通过路由器广告自动配置"
                echo "  3. 禁用IPv6      - 完全禁用IPv6功能"
                echo ""
                echo "默认地址段:"
                echo "  IPv4: 10.10.10.0/24 (默认IP: 10.10.10.100, 网关: 10.10.10.1, DNS: 223.5.5.5)"
                echo "  IPv6: dc00::/64 (默认IP: dc00::8888, 网关: dc00::1, DNS: 使用IPv4 DNS)"
                echo ""
                echo "选项:"
                echo "  --debug, -d   - 启用调试模式"
                ;;
        esac
    else
        main_menu
    fi
}

# 运行主程序
main "$@"
