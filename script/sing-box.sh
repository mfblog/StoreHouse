#!/bin/bash
green_text="\033[32m"
yellow_text="\033[33m"
red_text="\033[31m"
reset="\033[0m" 
sub_host="https://sub-singbox.herozmy.com"
json_file="&file=https://raw.githubusercontent.com/herozmy/StoreHouse/refs/heads/latest/config/sing-box/sing-box.json"
local_ip=$(hostname -I | awk '{print $1}')
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
## 更新并安装依赖
    update_version(){

            apt update && apt -y upgrade || { 
                echo "更新失败！退出脚本"; 
                exit 1; 
            }
            apt -y install curl git gawk build-essential libssl-dev libevent-dev zlib1g-dev gcc-mingw-w64 nftables || { 
                echo "软件包安装失败！退出脚本"; 
                exit 1; 
            }
            echo -e "\n设置时区为Asia/Shanghai"
            timedatectl set-timezone Asia/Shanghai || { 
                echo -e "\e[31m时区设置失败！退出脚本\e[0m"; 
                exit 1; 
            }
            echo -e "\e[32m时区设置成功\e[0m"
    }
######编译sing-box 官核
    singbox_install_make(){
    echo -e "编译Sing-Box 最新版本"
        sleep 1
        echo -e "开始编译Sing-Box 最新版本"
        rm -rf /root/go/bin/*
        # 获取 Go 版本
        Go_Version=$(curl -s https://github.com/golang/go/tags | grep '/releases/tag/go' | head -n 1 | gawk -F/ '{print $6}' | gawk -F\" '{print $1}')
        if [[ -z "$Go_Version" ]]; then
            echo "获取 Go 版本失败！退出脚本"
            exit 1
        fi
        # 判断 CPU 架构
        arch=$(detect_architecture)
        echo "系统架构是：$arch"
        wget -O ${Go_Version}.linux-$arch.tar.gz https://go.dev/dl/${Go_Version}.linux-$arch.tar.gz || { 
            echo "下载 Go 版本失败！退出脚本"; 
            exit 1; 
        }
        tar -C /usr/local -xzf ${Go_Version}.linux-$arch.tar.gz || { 
            echo "解压 Go 文件失败！退出脚本"; 
            exit 1; 
        }
        rm -f ${Go_Version}.linux-$arch.tar.gz  # 清理下载的文件

        # 设置 Go 环境变量
        echo 'export PATH=$PATH:/usr/local/go/bin' > /etc/profile.d/golang.sh
        source /etc/profile.d/golang.sh  # 立即生效

        # 编译 Sing-Box
        if ! go install -v -tags with_quic,with_grpc,with_dhcp,with_wireguard,with_ech,with_utls,with_reality_server,with_clash_api,with_gvisor,with_v2ray_api,with_lwip,with_acme github.com/sagernet/sing-box/cmd/sing-box@latest; then
            echo -e "Sing-Box 编译失败！退出脚本"
            exit 1
        fi
        echo -e "编译完成"
        sleep 1
    }

## singbox二进制安装
    singbox_install_core(){
        # 替换原有架构判断
        arch=$(detect_architecture)       
        VERSION=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep tag_name | cut -d ":" -f2 | sed 's/[\",v ]//g')
        curl -Lo sing-box.tar.gz "https://github.com/SagerNet/sing-box/releases/download/v${VERSION}/sing-box-${VERSION}-linux-${arch}.tar.gz"
        tar -zxvf sing-box.tar.gz > /dev/null 2>&1
        cd sing-box-${VERSION}-linux-${arch} || { echo "进入解压目录失败！"; exit 1; }
        mv sing-box ../ || { echo "移动 sing-box 失败！"; exit 1; }
        cd ..
        rm -rf sing-box-${VERSION}-linux-${arch} sing-box.tar.gz
        rm -rf sing-box.tar.gz
    }
    # p核
    singbox_p_install(){
        arch=$(detect_architecture)
        download_url="https://github.com/herozmy/StoreHouse/releases/download/sing-box/sing-box-puernya-linux-${arch}.tar.gz"


        echo -e "${yellow}开始下载Puer喵佬核心...${reset}"
        if ! wget -O sing-box.tar.gz $download_url; then
            echo -e "${yellow}下载失败，请检查网络连接${reset}"
            exit 1
        fi
        
        echo -e "${green_text}下载完成，开始安装${reset}"
        tar -zxvf sing-box.tar.gz
        rm -f sing-box.tar.gz
    }
    # s核
    singbox_s_install(){
        arch=$(detect_architecture)
        download_url="https://github.com/herozmy/StoreHouse/releases/download/sing-box-yelnoo/sing-box-yelnoo-linux-${arch}.tar.gz"
        echo -e "${yellow}开始下载S佬Y核心...${reset}"
        if ! wget -O sing-box.tar.gz $download_url; then
            echo -e "${yellow}下载失败，请检查网络连接${reset}"
            exit 1
        fi
        
        echo -e "${green_text}下载完成，开始安装${reset}"
        tar -zxvf sing-box.tar.gz > /dev/null 2>&1
        rm -f sing-box.tar.gz
    }

    # 完善曦灵X核心安装函数
    singbox_x_install(){
        arch=$(detect_architecture)
        download_url="https://github.com/herozmy/StoreHouse/releases/download/sing-box-x/sing-box-x.tar.gz"
        echo -e "${yellow}开始下载曦灵X核心...${reset}"
        if ! wget -O sing-box.tar.gz $download_url; then
            echo -e "${yellow}下载失败，请检查网络连接${reset}"
            exit 1
        fi
        
        echo -e "${green_text}下载完成，开始安装${reset}"
        tar -zxvf sing-box.tar.gz > /dev/null 2>&1
        mv sing-box_linux_amd64 sing-box

        rm -f sing-box.tar.gz
    }

##安装配置文件
    ### 自定义设置
    customize_settings() {
        local retry_count=0
        local max_retries=3
        local suburl=""
        get_subscription_url 
    # 检查订阅地址是否为空
        if [ -z "$suburl" ]; then
            echo -e "${yellow}未提供订阅地址，跳过配置文件生成${reset}"
            return 0  # 直接退出函数，不执行后续操作
        fi

        while [ $retry_count -lt $max_retries ]; do

            # 生成配置文件
            generate_config  # 新增配置文件生成函数
            
            # 验证配置文件
            if check_config; then
                return 0
            else
                retry_count=$((retry_count+1))
                remaining=$((max_retries - retry_count))
                echo -e "${yellow}剩余尝试次数: ${remaining}${reset}"
            fi
        
        
        echo -e "${red}连续3次生成配置文件失败，请检查订阅地址有效性${reset}"
        exit 1
        done

  
    }

    # 新增订阅地址获取函数
    get_subscription_url() {
        echo -e "是否选择生成配置？(y/n) ${green_text}生成配置文件需要添加机场订阅，如自建vps请选择n${reset}"
        read choice
        if [ "$choice" = "y" ]; then
            read -p "输入订阅连接：" suburl
            suburl="${suburl:-https://}"
            echo "已设置订阅连接地址：$suburl"
        else
            echo "请手动编写config配置文件,默认模版仓库地址：https://github.com/herozmy/StoreHouse/tree/main/config"
            
        fi
        check_interfaces
    }

    # 新增配置文件生成函数
    generate_config() {

        echo -e "${yellow}正在生成配置文件...${reset}"

        curl -o config.json "${sub_host}/config/${suburl}${json_file}" || {
            echo -e "${red}配置文件下载失败${reset}"
            return 1
        }
    }

    # 修改后的配置检查函数
    check_config() {
        local config_file="config.json"
        
        if [ ! -f "$config_file" ]; then
            echo -e "${red}配置文件不存在${reset}"
            return 1
        fi

        line_count=$(wc -l < "$config_file")
        
        if [ "$line_count" -gt 10 ]; then
            echo -e "${green}配置文件检测通过 (${line_count}行)${reset}"
        # return 0
        else
            echo -e "${red}配置文件不完整 (仅${line_count}行)${reset}"
            return 1
        fi
    }

    ### 安装配置文件
    install_josn_config(){
    ###官方内核配置文件
    if [[ "$core_choice" == "1" ]]; then
    customize_settings
        # 仅在订阅地址有效时生成配置
        if [ -n "$suburl" ]; then
         
            mkdir -p /etc/sing-box
            if [ -f "config.json" ]; then
                mv config.json /etc/sing-box/config.json || {
                    echo -e "${red}配置文件移动失败${reset}"
                    exit 1
                }
            fi        
        # 无订阅地址时的处理
       fi
        echo -e "${green_text}Sing-box配置文件写入成功！${reset}"
    ###Puer喵佬核心配置文件
        elif [[ "$core_choice" == "2" ]]; then
            get_subscription_url
            mkdir -p /etc/sing-box
            mkdir -p /etc/sing-box/providers
            mkdir -p /etc/sing-box/rule
            if curl -o /etc/sing-box/config.json https://raw.githubusercontent.com/herozmy/StoreHouse/refs/heads/latest/config/sing-box/sing-box-p.json; then
                echo -e "${green_text} 配置文件下载成功${reset}"
                sed -i "s|\"download_url\": \"机场订阅\"|\"download_url\": \"$suburl\"|g" /etc/sing-box/config.json
            else
                echo -e "${red}配置文件下载失败${reset}"
                exit 1
            fi
            wget -O /etc/sing-box/p_rule.tar.gz https://d.herozmy.com/public/Routing/Config/sing-box/p_rule.tar.gz
            tar --strip-components=1 -zxvf /etc/sing-box/p_rule.tar.gz -C /etc/sing-box/rule
            rm -f /etc/sing-box/p_rule.tar.gz
    ###曦灵X核心配置文件
        elif [[ "$core_choice" == "3" ]]; then
            get_subscription_url
            mkdir -p /etc/sing-box
            if curl -o /etc/sing-box/config.json https://raw.githubusercontent.com/herozmy/StoreHouse/refs/heads/latest/config/sing-box/sing-box-x.json; then
                echo -e "${green_text} 配置文件下载成功${reset}"
                sed -i "s|\"download_url\": \"机场订阅\"|\"download_url\": \"$suburl\"|g" /etc/sing-box/config.json
            else
                echo -e "${red}配置文件下载失败${reset}"
                exit 1
            fi
    ###S佬Y核心配置文件
        elif [[ "$core_choice" == "4" ]]; then
            get_subscription_url
            mkdir -p /etc/sing-box
            if curl -o /etc/sing-box/config.json https://raw.githubusercontent.com/herozmy/StoreHouse/refs/heads/latest/config/sing-box/sing-box-y.json; then
                echo -e "${green_text} 配置文件下载成功${reset}"
                sed -i "s|\"url\": \"机场订阅\"|\"url\": \"$suburl\"|g" /etc/sing-box/config.json
            else
                echo -e "${red}配置文件下载失败${reset}"
                exit 1
            fi
            fi
    }
    # 拉取sing-box UI管理界面
        ###检测ui是否存在
    check_ui(){
        found_files=$(find /usr/local/bin/ -type f \( -name "mihomo" -o -name "sing-box" \))
        if [ -n "$found_files" ]; then
        for file in $found_files; do
            filename=$(basename "$file")
        done
        fi  
        if [ -d "/etc/${filename}/ui" ]; then
            echo "更新 WEBUI..."
            rm -rf /etc/${filename}/ui
            git_ui
        else
            git_ui
        fi
    }
    git_ui(){
        if git clone https://github.com/Zephyruso/zashboard.git -b gh-pages /etc/${filename}/ui; then
            echo -e "UI 源码拉取${green_text}成功${reset}。"
        else
            echo "拉取源码失败，请手动下载源码并解压至 /etc/${filename}/ui."
            echo "地址: https://github.com/metacubex/metacubexd"
        fi
    }
    check_interfaces() {
        interfaces=$(ip -o link show | awk -F': ' '{print $2}')
        # 输出物理网卡名称
        for interface in $interfaces; do
            # 检查是否为物理网卡（不包含虚拟、回环等），并排除@符号及其后面的内容
            if [[ $interface =~ ^(en|eth).* ]]; then
                interface_name=$(echo "$interface" | awk -F'@' '{print $1}')  # 去掉@符号及其后面的内容
                echo -e "您的网卡是：${yellow}$interface_name${reset}"
                valid_interfaces+=("$interface_name")  # 存储有效的网卡名称
            fi
        done
        # 提示用户选择
        
        #read -p "脚本自行检测的是否是您要的网卡？(y/n): " confirm_interface
        #if [ "$confirm_interface" = "y" ]; then
            #selected_interface="$interface_name"
            #echo -e "您选择的网卡是: ${green_text}$selected_interface${reset}"
        #elif [ "$confirm_interface" = "n" ]; then
            #read -p "请自行输入您的网卡名称: " selected_interface
            #echo -e "您输入的网卡名称是: ${green_text}$selected_interface${reset}"
        #else
            #echo "无效的选择"
        #fi
    }
    check_aio() {
        local NEED_ADJUST=0
        local NFT_RULESET="/etc/nftables.conf"
        
        # 定义核心二进制检测路径数组
        local MOSDNS_PATHS="/usr/local/bin/mosdns"
        
        local PROXY_PATHS=(
            "/usr/local/bin/mihomo"
            "/usr/local/bin/sing-box"
        )

        # 增强型二进制检测函数
        check_binary() {
            local paths=("$@")
            for path in "${paths[@]}"; do
                if [ -x "$path" ] && file "$path" | grep -qE "ELF.*executable"; then
                    return 0
                fi
            done
            return 1
        }

        # 检测组件存在性
        local HAS_MOSDNS=0
        local HAS_PROXY=0
        
        check_binary "${MOSDNS_PATHS[@]}" && HAS_MOSDNS=1
        check_binary "${PROXY_PATHS[@]}" && HAS_PROXY=1

        echo -e "${yellow}=== 组件检测结果 ===${reset}"
        echo -e "MosDNS 存在: $([ $HAS_MOSDNS -eq 1 ] && 
            echo "${green_text}是✓${reset}" || 
            echo "${red}否✗${reset}")"
            
        echo -e "代理核心存在: $([ $HAS_PROXY -eq 1 ] && 
            echo "${green_text}是✓${reset}" || 
            echo "${red}否✗${reset}")"

        # 判断调整条件
        if [ $HAS_MOSDNS -eq 1 ] && [ $HAS_PROXY -eq 1 ]; then
            NEED_ADJUST=1
            echo -e "${yellow}检测到DNS与代理核心共存，需要调整防火墙规则${reset}"
        else
            echo -e "${green_text}未检测到需要调整的组合${reset}"
        fi

        # 应用规则调整
        if [ $NEED_ADJUST -eq 1 ]; then
            # 定义要添加的IPv4/IPv6地址
            local ADD_IPV4=("223.5.5.5/32" "223.6.6.6/32")
            local ADD_IPV6=("2400:3200::1/128" "2400:3200:baba::1/128")
            
            # 处理IPv4规则
            for ip in "${ADD_IPV4[@]}"; do
                if ! grep -q "$ip" "$NFT_RULESET"; then
                    echo -e "${yellow}添加IPv4 $ip...${reset}"
                    sed -i "/10.0.0.0\/8,/a\      $ip," "$NFT_RULESET"
                fi
            done
            
            # 处理IPv6规则
            for ip in "${ADD_IPV6[@]}"; do
                if ! grep -q "$ip" "$NFT_RULESET"; then
                    echo -e "${yellow}添加IPv6 $ip...${reset}"
                    sed -i "/100::\/64,/a\      $ip," "$NFT_RULESET" 
                fi
            done
            
            # 统一验证配置
            if nft -c -f "$NFT_RULESET"; then
                # 刷新防火墙规则
                echo -e "${yellow}正在刷新防火墙...${reset}"
                nft flush ruleset    # 清空现有规则
                nft -f "$NFT_RULESET"  # 重新加载配置
                sleep 1
                echo -e "${green_text}防火墙规则已生效${reset}"
                #[ -f /usr/local/bin/sing-box -o -f /usr/local/bin/mihomo ] && systemctl stop "$([ -f /usr/local/bin/sing-box ] && echo 'sing-box' || echo 'mihomo')-router"; [ -f /usr/local/bin/sing-box -o -f /usr/local/bin/mihomo ] systemctl start "$([ -f /usr/local/bin/sing-box ] && echo 'sing-box' || echo 'mihomo')-router"
            else
                echo -e "${red_text}配置错误，回滚修改${reset}"
                sed -i '/\(223.5.5.5\/32\|223.6.6.6\/32\|2400:3200::1\/128\|2400:3200:baba::1\/128\),/d' "$NFT_RULESET"
            fi
        fi
    }
######选择安装sing-box 核心
    choose_singbox(){
        echo -e "请选择${green_text}程序${reset}"
        echo -e "${yellow}1. Sing-box官核 ${reset}${green_text}<vps自建推荐>${reset}"
        echo -e "${yellow}2. Sing-boxPuer喵佬核心${reset} <支持订阅> ${green_text}停更${reset}"
        echo -e "${yellow}3. Sing-box曦灵X核心${reset} <支持订阅> ${green_text}停更${reset}"
        echo -e "${yellow}4. Sing-box S佬Y核心${reset} <支持订阅> ${green_text}推荐${reset}"
        echo -e "${yellow}0. 返回主菜单${reset}"
        read -p "请输入选择 (1/2/3/4/0): " core_choice
        case "$core_choice" in
            1)
                echo -e "当前选择: ${green_text}Sing-BOX${reset}官方核心"        
                echo -e "请选择: ${green_text}Sing-BOX${reset}官方核心安装方式"  
                choose_install_singbox
                ;;
            2)
                echo -e "当前选择: ${green_text} Sing-BOX ${reset}Puer喵佬核心"
                update_version &&singbox_p_install
               
                ;;
            3)
                echo -e "当前选择: ${green_text}Sing-BOX${reset}曦灵X核心"
                update_version && singbox_x_install 
                ;;
            4)
                echo -e "当前选择: ${green_text}Sing-BOX${reset}S佬Y核心"
                update_version && singbox_s_install
                ;;
            0)
                main
                ;;
            *)
                echo -e "无效选择，退出脚本"
                exit 1
                ;;
        esac
    }
    install_core(){
        mv sing-box /usr/local/bin/sing-box || { echo "移动 sing-box 失败！"; exit 1; }
        chmod +x /usr/local/bin/sing-box       
    }
#############sing-box官方核心
    choose_install_singbox(){
        echo -e "请选择${green_text}程序${reset}"
        echo -e "${yellow}1. Sing-box编译安装${reset}"
        echo -e "${yellow}2. Sing-box二进制安装${reset}"
        echo -e "${yellow}0. 返回核心选择主菜单${reset}"
        read -p "请输入选择 (1/2/0): " choice
        case "$choice" in
            1)
                echo -e "当前选择: ${green_text}Sing-BOX${reset}编译安装"              
                update_version
                singbox_install_make
                cp "$(go env GOPATH)/bin/sing-box" /usr/local/bin/ || { echo "复制文件失败！退出脚本"; exit 1; }
                chmod +x /usr/local/bin/sing-box 
                echo -e "${green_text}Sing-Box 编译安装完成${reset}" 
                ;;
            2)
                echo -e "当前选择: ${green_text} Sing-BOX ${reset}二进制安装"
                update_version
                singbox_install_core
                install_core
                echo -e "${green_text}Sing-Box 二进制安装完成${reset}"
                ;;
            0)
                main
                ;;
            *)
                echo -e "无效选择，退出脚本"
                exit 1
                ;;
        esac
    }
    choose_singbox
    install_core
    install_josn_config
    check_resolved
    sleep 1
    echo -e "${yellow}配置系统服务文件${reset}"
    sleep 1
    cp $DIRPATH/sing-box.service /etc/systemd/system/
    echo -e "${green_text}sing-box 服务创建完成${reset}"
    echo -e "${yellow}配置tproxy${reset}"
    sleep 1
    echo -e "${yellow}创建系统转发${reset}"
    # 判断是否已存在 net.ipv4.ip_forward=1
    if ! grep -q '^net.ipv4.ip_forward=1$' /etc/sysctl.conf; then
        echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
    fi

    # 判断是否已存在 net.ipv6.conf.all.forwarding = 1
    #    if ! grep -q '^net.ipv6.conf.all.forwarding = 1$' /etc/sysctl.conf; then
    #       echo 'net.ipv6.conf.all.forwarding = 1' >> /etc/sysctl.conf
    #   fi
    sleep 1
    echo -e "${green_text}系统转发创建完成${reset}"
    sleep 1
    cp $DIRPATH/tproxy-router.service /etc/systemd/system/
    sleep 1
    echo -e "${green_text}tproxy-router 服务创建完成"
    sleep 1
    sleep 1
    ####写入nftables
    echo "" > "/etc/nftables.conf"
    cat $DIRPATH/nft-tproxy.conf >> "/etc/nftables.conf"
    check_interfaces
    echo -e "修正nftables规则"
    sed -i "s/eth0/${interface_name}/g" "/etc/nftables.conf"
    echo -e "${green_text}nftables 规则写入完成${reset}"
    sleep 1
    echo -e "拉取sing-box UI管理界面"
    check_ui
    check_aio
    echo -e "${green_text}启用相关服务${reset}"
    systemctl enable --now sing-box  > /dev/null 2>&1
    sleep 2
    systemctl enable --now tproxy-router > /dev/null 2>&1
    nft flush ruleset > /dev/null 2>&1
    nft -f /etc/nftables.conf > /dev/null 2>&1
    systemctl enable --now nftables > /dev/null 2>&1
    echo "=================================================================="
    echo -e "\t\t\tSing-box 安装完毕"
    echo -e "\t\t\tPowered by www.herozmy.com 2025"
    echo -e "\n"
    echo -e "${green_text}请使用${reset} ${yellow_text}proxytool${reset} ${green_text}管理sing-box${reset}"
    echo -e "Sing-box运行目录为/etc/sing-box"
    echo -e "Sing-box WebUI地址:${green_text}http://${local_ip}:9090${reset}"
    echo -e "本脚本仅适用于学习与研究等个人用途，请勿用于任何违反国家法律的活动！"
    echo "=================================================================="
    echo -e "${green_text}请使用${reset} ${yellow_text}systemctl start sing-box${reset} ${green_text}启动服务${reset}"
    echo -e "${green_text}请使用${reset} ${yellow_text}systemctl enable sing-box${reset} ${green_text}设置开机自启${reset}"
    echo -e "${green_text}请使用${reset} ${yellow_text}systemctl status sing-box${reset} ${green_text}查看服务状态${reset}"
    echo -e "${green_text}请使用${reset} ${yellow_text}systemctl restart sing-box${reset} ${green_text}重启服务${reset}"
    echo -e "${green_text}请使用${reset} ${yellow_text}systemctl stop sing-box${reset} ${green_text}停止服务${reset}"
    echo -e "${green_text}请使用${reset} ${yellow_text}systemctl disable sing-box${reset} ${green_text}禁用开机自启${reset}"
    echo -e "${green_text}请使用${reset} ${yellow_text}systemctl restart nftables${reset} ${green_text}重启nftables${reset}"
    echo -e "${green_text}请使用${reset} ${yellow_text}systemctl status nftables${reset} ${green_text}查看nftables状态${reset}"
    echo -e "${green_text}请使用${reset} ${yellow_text}systemctl restart tproxy-router${reset} ${green_text}重启路由${reset}"
    echo -e "${green_text}请使用${reset} ${yellow_text}systemctl status tproxy-router${reset} ${green_text}查看路由状态${reset}" 
	echo -----------------------------------------------
	echo -e "${green_text}请使用${reset} ${yellow_text}proxytool${reset} ${green_text}管理sing-box${reset}"
	echo ----------------------------------------------- 
    

