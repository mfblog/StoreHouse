    #!/bin/bash


    # 定义全局颜色变量
    green_text="\033[32m"
    yellow="\033[33m"
    reset="\033[0m"
    red='\033[1;31m'
    sub_host="https://sub-singbox.herozmy.com"
    json_file="&file=https://raw.githubusercontent.com/herozmy/StoreHouse/refs/heads/latest/config/sing-box/sing-box.json"
    local_ip=$(hostname -I | awk '{print $1}')
    found_singbox=false
    found_mosdns=false
    found_mihomo=false

    check_installed() {
        programs=("sing-box" "mosdns" "mihomo")    
        for program in "${programs[@]}"; do
            if [ -f "/usr/local/bin/$program" ]; then
                case "$program" in
                    "sing-box") found_singbox=true ;;
                    "mosdns") found_mosdns=true ;;
                    "mihomo") found_mihomo=true ;;
                esac
                echo -e "${green_text}当前系统已安装${reset}"
                echo -e "  ${green_text}✔${reset} $program"
            fi
        done
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

    check_singbox(){

        # 统一检测所有可能的核心服务
        if [[ -f /usr/local/bin/mihomo ]] || 
        [[ -f /usr/local/bin/sing-box ]]; then
            echo -e "${green_text}[信息] 核心已安装，请选择是否升级${reset}"
            echo -e "${yellow}1. 升级${reset}"
            echo -e "${yellow}2. 跳过${reset}"
            read -rp "请输入选择 (1/2): " choice
            case "$choice" in
                1)
                    echo -e "${yellow}开始升级核心...${reset}"
                    # 检测已安装的核心类型
                if [[ "$core_choice" == "4" ]]; then
                    if [[ -f /usr/local/bin/mihomo ]]; then
                        echo -e "${green_text}检测到已安装Mihomo核心，开始升级...${reset}"
                        systemctl stop mihomo-router.service
                        systemctl stop nftables
                        mihomo_install
                        mv mihomo /usr/local/bin/mihomo
                        chmod +x /usr/local/bin/mihomo
                        systemctl restart mihomo.service
                        systemctl restart mihomo-router.service
                        systemctl restart nftables

                        echo -e "${green_text}Mihomo 升级完成${reset}"
                        exit 0
                    fi
                fi
                    if [[ -f /usr/local/bin/sing-box ]]; then
                        echo -e "${green_text}检测到已安装Sing-Box核心，开始升级...${reset}"
                        # 无法自动判断时让用户选择
                        echo -e "${yellow}无法自动识别核心版本，请手动选择：${reset}"
                        echo -e "1. 官方核心\n2. Puer喵佬核心\n3. 曦灵X核心"
                        read -rp "请输入选择 (1/2/3): " core_choice
                        case "$core_choice" in
                            1) 
                            choose_install_singbox
                            ;;
                            2) 
                            systemctl stop sing-box-router.service
                            systemctl stop nftables 
                            singbox_p_install
                            mv sing-box /usr/local/bin/ || { echo "移动 sing-box 失败！"; exit 1; }
                            chmod +x /usr/local/bin/sing-box 
                            systemctl restart sing-box.service
                            systemctl restart sing-box-router.service
                            systemctl restart nftables
                            echo -e "${green_text}Puer喵佬核心升级完成${reset}"
                            exit 0
                            ;;
                            3) 
                            systemctl stop sing-box-router.service
                            systemctl stop nftables 
                            singbox_x_install
                            mv sing-box /usr/local/bin/ || { echo "移动 sing-box 失败！"; exit 1; }
                            chmod +x /usr/local/bin/sing-box 
                            systemctl restart sing-box.service
                            systemctl restart sing-box-router.service
                            systemctl restart nftables
                            echo -e "${green_text}曦灵X核心升级完成${reset}"
                            exit 0
                            ;;
                            *) 
                                echo -e "${yellow}无效选择，退出脚本${reset}"
                                exit 1
                                ;;
                        esac
                    fi  # 新增的
                
                    ;;
                2)
                    echo -e "${yellow}已跳过升级${reset}"
                    exit 1
                    ;;
            esac  
        else
            echo -e "${yellow}[信息] 开始安装核心...${reset}"
            # 调用安装函数
        fi
    }
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
    check_enter(){

        if [[ "$core_choice" == "1" ]]; then
            export core_service="sing-box"
            update_version
            singbox_install_make
            cp "$(go env GOPATH)/bin/sing-box" /usr/local/bin/ || { echo "复制文件失败！退出脚本"; exit 1; }
            chmod +x /usr/local/bin/sing-box
            echo -e "${green_text}Sing-Box 安装完成${reset}"
        elif [[ "$core_choice" == "2" ]]; then
            export core_service="sing-box"
            update_version
            singbox_p_install
            mv sing-box /usr/local/bin/sing-box || { echo "移动 sing-box 失败！"; exit 1; }
            chmod +x /usr/local/bin/sing-box
            echo -e "${green_text}Puer喵佬核心安装完成${reset}"
        elif [[ "$core_choice" == "3" ]]; then
            export core_service="sing-box"
            update_version
            singbox_x_install       
            mv sing-box /usr/local/bin/sing-box || { echo "移动 sing-box 失败！"; exit 1; }
            chmod +x /usr/local/bin/sing-box
            echo -e "${green_text}曦灵X核心安装完成${reset}"
            
        elif [[ "$core_choice" == "4" ]]; then
            export core_service="mihomo"
            update_version
            mihomo_install
            mv mihomo /usr/local/bin/mihomo
            chmod +x /usr/local/bin/mihomo
            echo -e "${green_text}Mihomo 安装完成${reset}"

        elif [[ "$core_choice" == "5" ]]; then
            export core_service="sing-box"
            update_version
            singbox_s_install
            mv sing-box /usr/local/bin/sing-box
            chmod +x /usr/local/bin/sing-box
            echo -e "${green_text}S佬Y核心安装完成${reset}"
        else
            echo "无效的选择，退出脚本"
            exit 1
        fi

    }
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

    singbox_install_core(){
        set -e -o pipefail
        # 替换原有架构判断
        arch=$(detect_architecture)
        
        VERSION=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep tag_name | cut -d ":" -f2 | sed 's/[\",v ]//g')
        curl -Lo sing-box.tar.gz "https://github.com/SagerNet/sing-box/releases/download/v${VERSION}/sing-box-${VERSION}-linux-${arch}.tar.gz"
        tar -zxvf sing-box.tar.gz
        cd sing-box-${VERSION}-linux-${arch} || { echo "进入解压目录失败！"; exit 1; }
        mv sing-box ../ || { echo "移动 sing-box 失败！"; exit 1; }
        cd ..
        rm -rf sing-box-${VERSION}-linux-${arch} sing-box.tar.gz
        rm -rf sing-box.tar.gz
    }

    mihomo_install(){
        arch=$(detect_architecture)
        download_url="https://github.com/herozmy/StoreHouse/releases/download/mihomo/mihomo-meta-linux-${arch}.tar.gz
    "
        echo -e "${yellow}开始下载Mihomo核心...${reset}"
        if ! wget -O mihomo.tar.gz $download_url; then
            echo -e "${yellow}下载失败，请检查网络连接${reset}"
            exit 1
        fi
        
        echo -e "${green_text}下载完成，开始安装${reset}"
        tar -zxvf mihomo.tar.gz
        rm -f mihomo.tar.gz
    }

    choose_install_singbox(){
    
        echo -e "请选择${green_text}程序${reset}"
        echo -e "${yellow}1. Sing-box编译安装${reset}"
        echo -e "${yellow}2. Sing-box二进制安装${reset}"
        echo -e "${yellow}0. 返回主菜单${reset}"
        read -p "请输入选择 (1/2/0): " choice
        case "$choice" in
            1)
                echo -e "当前选择: ${green_text}Sing-BOX${reset}编译安装"              
                if [[ -f /usr/local/bin/sing-box ]]; then 
                systemctl stop sing-box-route.service  
                systemctl stop nftables        
                singbox_install_make
                cp "$(go env GOPATH)/bin/sing-box" /usr/local/bin/ || { echo "复制文件失败！退出脚本"; exit 1; }
                chmod +x /usr/local/bin/sing-box 
                echo -e "${green_text}Sing-Box 升级编译完成${reset}"
                exit 0
                else
                export core_service="sing-box"
                update_version
                singbox_install_make
                cp "$(go env GOPATH)/bin/sing-box" /usr/local/bin/ || { echo "复制文件失败！退出脚本"; exit 1; }
                chmod +x /usr/local/bin/sing-box 
                echo -e "${green_text}Sing-Box 编译安装完成${reset}"
                fi  
                ;;
            2)
                echo -e "当前选择: ${green_text} Sing-BOX ${reset}二进制安装"
                systemctl stop sing-box-route.service
                systemctl stop nftables 
                export core_service="sing-box"
                if [[ -f /usr/local/bin/sing-box ]]; then  
                singbox_install_core
                mv sing-box /usr/local/bin/ || { echo "复制文件失败！退出脚本"; exit 1; }
                chmod +x /usr/local/bin/sing-box
                echo -e "${green_text}Sing-Box 升级二进制安装完成${reset}"
                exit 0
                else
                update_version
                singbox_install_core
                mv sing-box /usr/local/bin/ || { echo "复制文件失败！退出脚本"; exit 1; }
                chmod +x /usr/local/bin/sing-box
                echo -e "${green_text}Sing-Box 二进制安装完成${reset}"
                fi
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
        download_url="https://github.com/herozmy/StoreHouse/releases/download/sing-box-yelnoo/sing-box-yelnoo-dev-linux-${arch}.tar.gz"


        echo -e "${yellow}开始下载S佬Y核心...${reset}"
        if ! wget -O sing-box.tar.gz $download_url; then
            echo -e "${yellow}下载失败，请检查网络连接${reset}"
            exit 1
        fi
        
        echo -e "${green_text}下载完成，开始安装${reset}"
        tar -zxvf sing-box.tar.gz
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
        tar -zxvf sing-box.tar.gz
        mv sing-box_linux_amd64 sing-box

        rm -f sing-box.tar.gz
    }

    ### 自定义设置
    customize_settings() {
        local retry_count=0
        local max_retries=3
        local suburl=""
        
        while [ $retry_count -lt $max_retries ]; do
            # 获取订阅地址
            get_subscription_url  # 新增函数处理订阅地址输入
            
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
        done
        
        echo -e "${red}连续3次生成配置文件失败，请检查订阅地址有效性${reset}"
        exit 1
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
            mkdir -p /etc/sing-box
            mv config.json /etc/sing-box/config.json || {
                echo -e "${red}配置文件移动失败${reset}"
                exit 1
            }
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
    ###Mihomo核心配置文件
        elif [[ "$core_choice" == "4" ]]; then
            get_subscription_url
            mkdir -p /etc/mihomo
            wget -O /etc/mihomo/config.yaml https://github.com/herozmy/sing-box-mosdns-fakeip/raw/refs/heads/main/config/clash-fake-ip.yaml
            sed -i "s|url: '机场订阅'|url: '$suburl'|" /etc/mihomo/config.yaml
            sed -i "s|interface-name: eth0|interface-name: $interface_name|" /etc/mihomo/config.yaml

    ###S佬Y核心配置文件
        elif [[ "$core_choice" == "5" ]]; then
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

    #####sing-box自启动脚本

    install_core_service(){
        check_resolved
        sleep 1
        echo -e "${yellow}配置系统服务文件${reset}"
        sleep 1
        core_service_file="/etc/systemd/system/${core_service}.service"
    cat << EOF > "$core_service_file"
    [Unit]
    Description=$core_service service

    [Service]
    CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
    AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
    ExecStart=/usr/local/bin/${core_service} run -c /etc/${core_service}/config.json
    Restart=on-failure
    RestartSec=1800s
    LimitNOFILE=infinity

    [Install]
    WantedBy=multi-user.target
    EOF
        if [ "$core_service" = "mihomo" ]; then
            sed -i '/CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE/,/LimitNOFILE=infinity/c\Type=simple\nExecStart=/usr/local/bin/mihomo -d /etc/mihomo/' "$core_service_file"
        
        fi
        echo -e "${green_text}${core_service} 服务创建完成${reset}"
        systemctl daemon-reload
        systemctl enable ${core_service}
    }
    install_singbox_tproxy(){
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
        # 写入tproxy rule  
        echo -e "${yellow}写入路由 rule${reset}"
            cat <<EOF > "/etc/systemd/system/${core_service}-router.service"
    [Unit]
    Description=${core_service} TProxy Rules
    After=network.target
    Wants=network.target

    [Service]
    User=root
    Type=oneshot
    RemainAfterExit=yes
    # there must be spaces before and after semicolons
    ExecStart=/sbin/ip rule add fwmark 1 table 100 ; /sbin/ip route add local default dev lo table 100 ; /sbin/ip -6 rule add fwmark 1 table 101 ; /sbin/ip -6 route add local ::/0 dev lo table 101
    ExecStop=/sbin/ip rule del fwmark 1 table 100 ; /sbin/ip route del local default dev lo table 100 ; /sbin/ip -6 rule del fwmark 1 table 101 ; /sbin/ip -6 route del local ::/0 dev lo table 101

    [Install]
    WantedBy=multi-user.target
    EOF
    echo -e "${green_text}${core_service}-router 服务创建完成"
    sleep 1
    ####写入nftables
    echo "" > "/etc/nftables.conf"
    cat <<EOF > "/etc/nftables.conf"
    #!/usr/sbin/nft -f
    flush ruleset
    table inet $core_service {
    set local_ipv4 {
        type ipv4_addr
        flags interval
        elements = {
        10.0.0.0/8,
        127.0.0.0/8,
        169.254.0.0/16,
        172.16.0.0/12,
        192.168.0.0/16,
        240.0.0.0/4
        }
    }

    set local_ipv6 {
        type ipv6_addr
        flags interval
        elements = {
        ::ffff:0.0.0.0/96,
        64:ff9b::/96,
        100::/64,
        2001::/32,
        2001:10::/28,
        2001:20::/28,
        2001:db8::/32,
        2002::/16,
        fc00::/7,
        fe80::/10
        }
    }

    chain ${core_service}-tproxy {
        fib daddr type { unspec, local, anycast, multicast } return
        ip daddr @local_ipv4 return
        ip6 daddr @local_ipv6 return
        udp dport { 123 } return
        meta l4proto { tcp, udp } meta mark set 1 tproxy to :7896 accept
    }

    chain ${core_service}-mark {
        fib daddr type { unspec, local, anycast, multicast } return
        ip daddr @local_ipv4 return
        ip6 daddr @local_ipv6 return
        udp dport { 123 } return
        meta mark set 1
    }

    chain mangle-output {
        type route hook output priority mangle; policy accept;
        meta l4proto { tcp, udp } skgid != 1 ct direction original goto ${core_service}-mark
    }

    chain mangle-prerouting {
        type filter hook prerouting priority mangle; policy accept;
        iifname { wg0, lo, $interface_name } meta l4proto { tcp, udp } ct direction original goto ${core_service}-tproxy
    }
    }
    EOF
        echo -e "${green_text}nftables规则写入完成${reset}"
        sleep 1

    }
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
        if git clone https://github.com/metacubex/metacubexd.git -b gh-pages /etc/${filename}/ui; then
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

    home_config(){
    cat << EOF > /root/go_home.json
    {
        "log": {
            "level": "info",
            "timestamp": false
        },
        "dns": {
            "servers": [
                {
                    "tag": "dns_proxy",
                    "address": "tls://8.8.8.8:853",
                    "detour": "proxy",
                    "client_subnet": "2409:891f:e44::1"
                },
                {
                    "tag": "dns_direct",
                    "address": "https://223.5.5.5/dns-query",
                    "detour": "direct"
                },
                {
                    "tag": "dns_resolver",
                    "address": "223.5.5.5",
                    "detour": "direct"
                },
                {
                    "tag": "dns_success",
                    "address": "rcode://success"
                },
                {
                    "tag": "dns_refused",
                    "address": "rcode://refused"
                },
                {
                    "tag": "block",
                    "address": "rcode://success"
                },
                {
                    "tag": "dns_fakeip",
                    "address": "fakeip"
                }
            ],
            "rules": [
                {
                    "rule_set": "geosite-category-ads-all",
                    "server": "block",
                    "action": "route-options",
                    "disable_cache": true
                },
                {
                    "domain_regex": "^-cn-ssl.ls.apple.com",
                    "domain_suffix": [
                        "${domain}",
                        "office365.com",
                        "office.com",
                        "push-apple.com.akadns.net",
                        "push.apple.com",
                        "time.apple.com",
                        "gs-loc-cn.apple.com",
                        "iphone-ld.apple.com",
                        "lcdn-locator.apple.com",
                        "lcdn-registration.apple.com"
                    ],
                    "domain": [
                        "gs-loc-cn.apple.com",
                        "gsp10-ssl-cn.ls.apple.com",
                        "gsp12-cn.ls.apple.com",
                        "gsp13-cn.ls.apple.com",
                        "gsp4-cn.ls.apple.com.edgekey.net.globalredir.akadns.net",
                        "gsp4-cn.ls.apple.com.edgekey.net",
                        "gsp4-cn.ls.apple.com",
                        "gsp5-cn.ls.apple.com",
                        "gsp85-cn-ssl.ls.apple.com",
                        "gspe19-2-cn-ssl.ls.apple.com",
                        "gspe19-cn-ssl.ls.apple.com",
                        "gspe19-cn.ls-apple.com.akadns.net",
                        "gspe19-cn.ls.apple.com",
                        "gspe79-cn-ssl.ls.apple.com",
                        "cl2-cn.apple.com",
                        "cl4-cn.apple.com"
                    ],
                    "server": "dns_direct",
                    "disable_cache": true
                },
                {
                    "rule_set": "geosite-cn",
                    "query_type": [
                        "A",
                        "AAAA"
                    ],
                    "server": "dns_direct"
                },
                {
                    "rule_set": "geosite-cn",
                    "query_type": [
                        "CNAME"
                    ],
                    "server": "dns_direct"
                },
                {
                    "rule_set": "geosite-geolocation-!cn",
                    "query_type": [
                        "A",
                        "AAAA"
                    ],
                    "server": "dns_fakeip"
                },
                {
                    "rule_set": "geosite-geolocation-!cn",
                    "query_type": [
                        "CNAME"
                    ],
                    "server": "dns_proxy"
                },
                {
                    "query_type": [
                        "A",
                        "AAAA",
                        "CNAME"
                    ],
                    "invert": true,
                    "server": "dns_refused",
                    "action": "route-options",
                    "disable_cache": true
                }
            ],
            "final": "dns_proxy",
            "independent_cache": true,
            "fakeip": {
                "enabled": true,
                "inet4_range": "198.18.0.0/15",
                "inet6_range": "fc00::/18"
            }
        },
        "route": {
            "rule_set": [
                {
                    "tag": "geosite-category-ads-all",
                    "type": "remote",
                    "format": "binary",
                    "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ads-all.srs",
                    "download_detour": "proxy"
                },
                {
                    "tag": "geosite-netflix",
                    "type": "remote",
                    "format": "binary",
                    "url": "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/netflix.srs",
                    "download_detour": "proxy"
                },
                {
                    "tag": "geosite-cn",
                    "type": "remote",
                    "format": "binary",
                    "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs",
                    "download_detour": "proxy"
                },
                {
                    "tag": "geosite-geolocation-!cn",
                    "type": "remote",
                    "format": "binary",
                    "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-geolocation-!cn.srs",
                    "download_detour": "proxy"
                },
                {
                    "tag": "geoip-cn",
                    "type": "remote",
                    "format": "binary",
                    "url": "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs",
                    "download_detour": "proxy"
                }
            ],
            "rules": [
                {
                    "inbound": "tun-in",
                    "action": "sniff"
                },
                {
                    "protocol": "dns",
                    "action": "hijack-dns"
                },
                {
                    "ip_cidr": [
                        "${ip_cidr}"
                    ],
                    "outbound": "home"
                },
                {
                    "network": "udp",
                    "port": 443,
                    "action": "reject"
                },
                {
                    "rule_set": "geosite-category-ads-all",
                    "action": "reject"
                },
                {
                    "domain_suffix": [
                        ".cn"
                    ],
                    "outbound": "direct"
                },
                {
                    "domain_suffix": [
                        "office365.com",
                        "office.com"
                    ],
                    "outbound": "direct"
                },
                {
                    "domain_regex": "^-cn-ssl.ls.apple.com",
                    "domain_suffix": [
                        "push.apple.com",
                        "push-apple.com.akadns.net",
                        "time.apple.com",
                        "gs-loc-cn.apple.com",
                        "iphone-ld.apple.com",
                        "lcdn-locator.apple.com",
                        "lcdn-registration.apple.com"
                    ],
                    "domain": [
                        "gs-loc-cn.apple.com",
                        "gsp10-ssl-cn.ls.apple.com",
                        "gsp12-cn.ls.apple.com",
                        "gsp13-cn.ls.apple.com",
                        "gsp4-cn.ls.apple.com.edgekey.net.globalredir.akadns.net",
                        "gsp4-cn.ls.apple.com.edgekey.net",
                        "gsp4-cn.ls.apple.com",
                        "gsp5-cn.ls.apple.com",
                        "gsp85-cn-ssl.ls.apple.com",
                        "gspe19-2-cn-ssl.ls.apple.com",
                        "gspe19-cn-ssl.ls.apple.com",
                        "gspe19-cn.ls-apple.com.akadns.net",
                        "gspe19-cn.ls.apple.com",
                        "gspe79-cn-ssl.ls.apple.com",
                        "cl2-cn.apple.com",
                        "cl4-cn.apple.com"
                    ],
                    "outbound": "direct"
                },
                {
                    "rule_set": "geosite-cn",
                    "outbound": "direct"
                },
                {
                    "rule_set": "geosite-geolocation-!cn",
                    "outbound": "proxy"
                },
                {
                    "rule_set": "geoip-cn",
                    "outbound": "direct"
                },
                {
                    "ip_is_private": true,
                    "outbound": "direct"
                }
            ],
            "final": "proxy",
            "auto_detect_interface": true
        },
        "inbounds": [
            {
                "type": "tun",
                "tag": "tun-in",
                "address": [
                    "172.16.0.1/30",
                    "fd00::1/126"
                ],
                "mtu": 1500,
                "auto_route": true,
                "strict_route": true,
                "stack": "system"
            }
        ],
        "outbounds": [
            {
                "tag": "proxy",
                "type": "selector",
                "outbounds": [
                    "home-hy2",
                    "vless-test"
                ]
            },
            {
                "tag": "home",
                "type": "selector",
                "outbounds": [
                    "home-hy2"
                ]
            },
            {
                "type": "hysteria2",
                "server": "${domain}",       
                "server_port": ${hyport}, 
                "tag": "home-hy2", 
                "up_mbps": 50,
                "down_mbps": 500,
                "password": "${password}",
                "tls": {
                "enabled": true,
                "server_name": "bing.com",   
                "insecure": true,
                "alpn": [
                "h3"
                ]
                }
            },
            {
                "type": "vless",
                "tag": "vless-test",
                "uuid": "9b1cxxxx-c886-48e8-xxxx-ed683bf2cced",
                "packet_encoding": "xudp",
                "server": "110.110.110.110",
                "server_port": 54320,
                "flow": "",
                "tls": {
                    "enabled": true,
                    "server_name": "test.vless.com",
                    "utls": {
                        "enabled": true,
                        "fingerprint": "chrome"
                    },
                    "reality": {
                        "enabled": true,
                        "public_key": "hxxxWtU2rWjU9uowFtYE5UgYbvyv8enY5ikdKIRt4kE",
                        "short_id": "41axxx5e51c6138a"
                    }
                },
                "multiplex": {
                    "enabled": true,
                    "protocol": "h2mux",
                    "max_connections": 1,
                    "min_streams": 2,
                    "padding": true,
                    "brutal": {
                        "enabled": true,
                        "up_mbps": 200,
                        "down_mbps": 200
                    }
                }
            },
            {
                "type": "direct",
                "tag": "direct"
            }
        ],
        "experimental": {
            "cache_file": {
                "enabled": true,
                "path": "cache.db",
                "store_fakeip": true,
                "store_rdrc": true
            }
        }
    }
    EOF
        echo -e "${green}客户端配置生成完成${reset}"
        echo -e "${yellow}客户端配置生成路径为: /root/go_home.json${reset}"
        echo -e "${yellow}请自行复制至客户端${reset}"

    }
    hy2-gohome(){
        echo -e "${yellow}是否安装hy2回家配置 y/n${reset}"
        read -p "请输入选择 (y/n): " hy2_choice
        case "${hy2_choice}" in
            y)
                echo -e "${green_text}安装hy2回家配置${reset}"
                install_hy2-gohome
                ;;
            n)
                echo -e "${yellow}不安装hy2回家配置${reset}"
                ;;
            *)
                echo -e "${red}无效选择，退出脚本${reset}"
                exit 1
                ;;
        esac

    }


    ph_home_config(){
        echo -e "${yellow}请输入：mosdns地址 例如：10.10.10.53${reset}"
        read -p "DNS地址: " mosdns_address
        mosdns_address="${mosdns_address:-10.10.10.53}"
        echo -e "${yellow}请输入：家里wifi bssid 例如：e8:9f:80:8b:9c:59 <用于回家直连，请自行获取>${reset}"
        read -p "家里wifi bssid: " wifi_bssid
        wifi_bssid="${wifi_bssid:-e8:9f:80:8b:9c:59}"
    cat << EOF >  "/root/go_home.json"
    {   
        "log": {   
            "level": "error",   
            "timestamp": true   
        },   
        "dns": {   
            "servers": [   
                {   
                    "tag": "dnsdirect",    
                    "address": "udp://${mosdns_address}:53", 
                    "detour": "direct"   
                },  
                {   
                    "tag": "dnshome",   
                    "address": "udp://${mosdns_address}:53",   
                    "detour": "home"   
                },  
                {  
                "tag": "block",  
                "address": "rcode://success"  
                },
                {  
                    "tag": "nodedns",  
                    "address": "223.5.5.5",  
                    "detour": "direct"  
                }  
            ],  
            "rules": [  
                {  
                    "outbound": "any",  
                    "server": "nodedns"
                },
                { 
                    "query_type": [
                    "HTTPS",
                    "AAAA", 
                    "PTR",
                    "SVCB" 
                    ], 
                    "server": "block", 
                    "disable_cache": true 
                }, 
                {   
                    "wifi_bssid": "${wifi_bssid}",    
                    "server": "dnsdirect"   
                }
            ],   
            "independent_cache": true, 
            "disable_expire": false, 
            "final": "dnshome"   
        },  
        "route": {   
            "rules": [   
                {  
                    "protocol": "dns",  
                    "action": "hijack-dns"
                },    
                {   
                    "wifi_bssid": "${wifi_bssid}",    
                    "outbound": "direct"   
                }, 
                {  
                "ip_cidr": [ 
                    "${ip_cidr}", 
                    "192.168.1.0/24",
                    "28.0.0.1/8", 
                    "74.125.39.0/24", 
                    "216.239.36.0/24",  
                    "91.108.56.0/22",  
                    "91.108.4.0/22",  
                    "91.108.8.0/22",  
                    "91.108.16.0/22",  
                    "91.108.12.0/22",  
                    "149.154.160.0/20",  
                    "91.105.192.0/23",  
                    "91.108.20.0/22", 
                    "95.161.64.0/20",  
                    "185.76.151.0/24", 
                    "120.131.0.0/16", 
                    "111.202.0.0/16", 
                    "58.254.0.0/16", 
                    "120.92.0.0/16"  
                ],  
                    "outbound": "home"  
                } 
            ],   
            "final": "direct",   
            "auto_detect_interface": true   
        },  
        "inbounds": [   
            {  
                "type": "tun",  
                "tag": "tun-in",  
                "address": "172.16.0.1/30", 
                "mtu": 9000,  
                "auto_route": true,  
                "strict_route": true,  
                "stack": "system",  
                "sniff": true,  
                "sniff_override_destination": false  
            }   
        ],   
        "outbounds": [   
            {
                "type": "hysteria2",
                "server": "${domain}",       
                "server_port": ${hyport}, 
                "tag": "home", 
                "up_mbps": 50,
                "down_mbps": 500,
                "password": "${password}",
                "tls": {
                "enabled": true,
                "server_name": "bing.com",   
                "insecure": true,
                "alpn": [
                "h3"
                ]
                }
            },
            {   
                "type": "direct",   
                "tag": "direct"   
            }
        ],   
        "experimental": {   
            "cache_file": {   
                "enabled": true,   
                "path": "cache.db"   
            }   
        }   
    }
    EOF
        echo -e "${green}客户端配置生成完成${reset}"
        echo -e "${yellow}客户端配置生成路径为: /root/go_home.json${reset}"
        echo -e "${yellow}请自行复制至客户端${reset}"

    }



    install_hy2-gohome(){
        echo -e "hysteria2 回家 自签证书"
        echo -e "开始创建证书存放目录"
        mkdir -p /root/hysteria 
        echo -e "自签bing.com证书100年"
        openssl ecparam -genkey -name prime256v1 -out /root/hysteria/private.key && openssl req -new -x509 -days 36500 -key /root/hysteria/private.key -out /root/hysteria/cert.pem -subj "/CN=bing.com"
        while true; do
            # 提示用户输入域名
            read -p "请输入家庭DDNS域名: " domain
            # 检查域名格式是否正确
            if [[ $domain =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                break
            else
                echo "域名格式不正确，请重新输入"
            fi
        done  
        # 输入端口号
        while true; do
            read -p "请输入hy2协议端口号: " hyport

            # 检查端口号是否为数字
            if [[ $hyport =~ ^[0-9]+$ ]]; then
                break
            else
                echo "端口号格式不正确，请重新输入"
            fi
        done
        read -p "请输入密码: " password
        echo "您输入的域名是: $domain"
        echo "您输入的端口号是: $hyport"
        echo "您输入的密码是: $password"
        read -p "内网段: " ip_cidr
        ip_cidr="${ip_cidr:-10.10.10.0/24}"
        echo "您输入的内网段是: $ip_cidr"
        sleep 2
        echo "开始生成配置文件"
        # 检查sb配置文件是否存在
        config_file="/etc/sing-box/config.json"
        if [ ! -f "$config_file" ]; then
            echo "错误：配置文件 $config_file 不存在"
            echo "请配置singbox或者Puer喵佬核或者X核的singbox config.json脚本"
            
            exit 1
        fi   
        hy_config='{
        "type": "hysteria2",
        "tag": "hy2-in",
        "listen": "::",
        "listen_port": '"${hyport}"',
        "sniff": true,
        "sniff_override_destination": false,
        "sniff_timeout": "100ms",
        "users": [
            {
            "password": "'"${password}"'"
            }
        ],
        "ignore_client_bandwidth": true,
        "tls": {
            "enabled": true,
            "alpn": [
            "h3"
            ],
            "certificate_path": "/root/hysteria/cert.pem",
            "key_path": "/root/hysteria/private.key"
        }
        },
    '
    line_num=$(grep -n 'inbounds' /etc/sing-box/config.json | cut -d ":" -f 1)
    # 如果找到了行号，则在其后面插入 JSON 字符串，否则不进行任何操作
    if [ ! -z "$line_num" ]; then
        # 将文件分成两部分，然后在中间插入新的 JSON 字符串
        head -n "$line_num" /etc/sing-box/config.json > tmpfile
        echo "$hy_config" >> tmpfile
        tail -n +$(($line_num + 1)) /etc/sing-box/config.json >> tmpfile
        mv tmpfile /etc/sing-box/config.json
    fi
        echo "HY2回家配置写入完成"
        echo "开始重启sing-box"
        systemctl restart sing-box
        echo "开始生成sing-box回家-手机配置"
        echo -e "请选择生成sing-box回家-客户端配置"
        echo -e "${yellow}1. 全回家分流 <PH佬规则>${reset}"
        echo -e "${yellow}2. 客户端规则分流 <O佬规则> 注意：需自行添加飞机节点${reset}"
        read -p "请输入选择 (1/2/0): " hy2_config
        case "${hy2_config}" in
        1)
            echo "开始生成sing-box回家-全回家分流 <PH佬规则>"
            ph_home_config
            ;;
        2)
            echo "开始生成sing-box回家-规则分流 <O佬规则> 注意：需自行添加飞机节点"
            home_config
            ;;
        *)
            echo -e "无效选择，退出脚本"
            exit 1
            ;;
        esac

    }

    install_over() {
        echo -e "${green_text}启用相关服务${reset}"
        systemctl enable --now ${core_service} 
        sleep 2
        systemctl enable --now ${core_service}-router
        nft flush ruleset
        nft -f /etc/nftables.conf
        systemctl enable --now nftables
    echo "=================================================================="
    echo -e "\t\t\t${core_service} 安装完毕"
    echo -e "\t\t\tPowered by www.herozmy.com 2025"
    echo -e "\n"
    echo -e "${core_service}运行目录为/etc/${core_service}"
    echo -e "${core_service} WebUI地址:http://${local_ip}:9090"
    echo -e "本脚本仅适用于学习与研究等个人用途，请勿用于任何违反国家法律的活动！"
    echo "=================================================================="
        echo -e "${green_text}请使用${reset} ${yellow}systemctl start ${core_service}${reset} ${green_text}启动服务${reset}"
        echo -e "${green_text}请使用${reset} ${yellow}systemctl enable ${core_service}${reset} ${green_text}设置开机自启${reset}"
        echo -e "${green_text}请使用${reset} ${yellow}systemctl status ${core_service}${reset} ${green_text}查看服务状态${reset}"
        echo -e "${green_text}请使用${reset} ${yellow}systemctl restart ${core_service}${reset} ${green_text}重启服务${reset}"
        echo -e "${green_text}请使用${reset} ${yellow}systemctl stop ${core_service}${reset} ${green_text}停止服务${reset}"
        echo -e "${green_text}请使用${reset} ${yellow}systemctl disable ${core_service}${reset} ${green_text}禁用开机自启${reset}"
        echo -e "${green_text}请使用${reset} ${yellow}systemctl restart nftables${reset} ${green_text}重启nftables${reset}"
        echo -e "${green_text}请使用${reset} ${yellow}systemctl status nftables${reset} ${green_text}查看nftables状态${reset}"
        echo -e "${green_text}请使用${reset} ${yellow}systemctl restart ${core_service}-router${reset} ${green_text}重启路由${reset}"
        echo -e "${green_text}请使用${reset} ${yellow}systemctl status ${core_service}-router${reset} ${green_text}查看路由状态${reset}" 


    }
    install_over_mosdns(){
    echo "=================================================================="
    echo -e "\t\t\tMosdns 安装完毕"
    echo -e "\t\t\tPowered by www.herozmy.com 2025"
    echo -e "\n"
    echo -e "Mosdns运行目录为/etc/mosdns"
    echo -e "Mosdns 如果使用mosdns-ph版，则WebUI地址:http://${local_ip}:9099"
    echo -e "本脚本仅适用于学习与研究等个人用途，请勿用于任何违反国家法律的活动！"
    echo "=================================================================="
        echo -e "${green_text}请使用${reset} ${yellow}systemctl start mosdns${reset} ${green_text}启动服务${reset}"
        echo -e "${green_text}请使用${reset} ${yellow}systemctl enable mosdns${reset} ${green_text}设置开机自启${reset}"
        echo -e "${green_text}请使用${reset} ${yellow}systemctl status mosdns${reset} ${green_text}查看服务状态${reset}"
        echo -e "${green_text}请使用${reset} ${yellow}systemctl restart mosdns${reset} ${green_text}重启服务${reset}"
        echo -e "${green_text}请使用${reset} ${yellow}systemctl stop mosdns${reset} ${green_text}停止服务${reset}"
        echo -e "${green_text}请使用${reset} ${yellow}systemctl disable mosdns${reset} ${green_text}禁用开机自启${reset}"
    }
    ###################################################################Mosdns


    check_existing_core(){ 
        if $found_singbox || $found_mihomo; then
            echo -e "${yellow}检测到已安装其他核心程序："
            $found_singbox && echo "  ▶ Sing-Box (已存在)"
            $found_mihomo && echo "  ▶ Mihomo (已存在)"
            $found_mosdns && echo "  ▶ Mosdns (已存在)"
            echo -e "${reset}"
            return 0
        else
            return 1
        fi
    }
    check_mosdns_core(){
    # check_existing_core
    # 主逻辑
        if $found_mosdns; then
            echo -e "${green_text}当前 MosDNS 版本：$(mosdns version | head -n1)${reset}"
            echo -e "${yellow}请选择操作：${reset}"
            PS3="请输入选项："
            select option in "升级版本" "更新规则" "返回菜单"; do
                case $option in
                    "升级版本")
                        echo -e "${green}开始升级 MosDNS...${reset}"
                        install_mosdns
                        read -p "升级后是否更新规则？[Y/n] " update
                        if [[ ${update:-Y} =~ [Yy] ]]; then
                            echo -e "${green}正在更新规则...${reset}"
                            mv /etc/mosdns/ /etc/mosdnsbak
                            install_mosdns_config
                            exit 0
                        fi
                        break
                        ;;
                    "更新规则")
                        echo -e "${green}正在更新规则...${reset}"
                            mv /etc/mosdns/ /etc/mosdnsbak/
                            install_mosdns_config
                            exit 0
                        break
                        ;;
                    "返回菜单")
                        return 0
                        ;;
                    *)
                        echo -e "${red}无效选择，请重新输入${reset}"
                        ;;
                esac
            done
        else
            check_existing_core &&
            {
                read -p "检测到其他核心，是否继续安装 MosDNS？[Y/n] " confirm
                [[ ${confirm:-Y} =~ [Nn] ]] && {
                    echo -e "${red}安装已取消${reset}"
                    return 0
                }
            }
                [ -f /usr/local/bin/sing-box -o -f /usr/local/bin/mihomo ] && systemctl stop "$([ -f /usr/local/bin/sing-box ] && echo 'sing-box' || echo 'mihomo')-router"
                time_zone
                install_mosdns
                
                
        fi

    }

    time_zone(){
        echo -e "\n设置时区为Asia/Shanghai"
        timedatectl set-timezone Asia/Shanghai || { echo -e "\e[31m时区设置失败！退出脚本\e[0m"; exit 1; }
        echo -e "\e[32m时区设置成功\e[0m"
    }

    install_mosdns(){


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
    }


    install_mosdns_config(){   
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
    1. O佬分流规则
    2. PH佬分流规则
    "
        rm -rf .git
        echo && read -p "请输入选择 [0-2]: " num
        case "${num}" in
        0)
            exit 0
            ;;
        1)
            (
                wget -O mosdns.zip https://github.com/herozmy/StoreHouse/raw/refs/heads/latest/config/mosdns/o/mosdns.zip &&
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
                wget -O mosdns.zip https://github.com/herozmy/StoreHouse/raw/refs/heads/latest/config/mosdns/ph/mosdns2025302.zip &&
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
        check_aio

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
                [ -f /usr/local/bin/sing-box -o -f /usr/local/bin/mihomo ] && systemctl stop "$([ -f /usr/local/bin/sing-box ] && echo 'sing-box' || echo 'mihomo')-router"; [ -f /usr/local/bin/sing-box -o -f /usr/local/bin/mihomo ] && systemctl start "$([ -f /usr/local/bin/sing-box ] && echo 'sing-box' || echo 'mihomo')-router"
            else
                echo -e "${red_text}配置错误，回滚修改${reset}"
                sed -i '/\(223.5.5.5\/32\|223.6.6.6\/32\|2400:3200::1\/128\|2400:3200:baba::1\/128\),/d' "$NFT_RULESET"
            fi
        fi
    }

    uninstall_all(){
        echo -e "卸载Sing-Box | Mihomo | Mosdns"
        found_files=$(find /usr/local/bin/ -type f \( -name "mihomo" -o -name "sing-box" -o -name "mosdns" \))
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
                    systemctl disable mosdns
                    systemctl stop mosdns
                    rm -rf /etc/mosdns
                    rm -rf /usr/local/bin/mosdns
                    rm -rf /etc/systemd/system/mosdns.service
                    ;;
                "sing-box"|"mihomo")
                    systemctl disable $program
                    systemctl stop $program
                    systemctl disable $program-router
                    systemctl stop $program-router
                    # 如果是最后一个代理程序，清理防火墙规则
                    if ! [ -f "/usr/local/bin/sing-box" ] && ! [ -f "/usr/local/bin/mihomo" ]; then
                        echo " " > "/etc/nftables.conf"
                        nft flush ruleset
                        nft -f /etc/nftables.conf
                    fi
                    rm -rf /etc/$program
                    rm -rf /usr/local/bin/$program
                    rm -rf /etc/systemd/system/$program.service
                    rm -rf /etc/systemd/system/$program-router.service
                    ;;
            esac
            echo -e "${green_text}$program 已卸载完成${reset}"
        done

        systemctl daemon-reload
        echo -e "${green_text}卸载完成${reset}"
    }
    check_core_status() {
        echo -e "\n${yellow}检查服务状态...${reset}"
        echo -e "----------------------------------------"
        
        # 查找已安装的程序
        found_files=$(find /usr/local/bin/ -type f \( -name "mihomo" -o -name "sing-box" -o -name "mosdns" \))
        
        if [ -z "$found_files" ]; then
            echo -e "${yellow}未检测到已安装的程序${reset}"
            return
        fi
        
        # 遍历检查每个已安装的程序
        for file in $found_files; do
            program=$(basename "$file")
            echo -e "\n${program}:"
            case "$program" in
                "sing-box"|"mihomo")
                    if systemctl is-active --quiet ${program}-router; then
                        echo -e "  路由服务: ${green_text}运行中${reset}"
                    else
                        echo -e "  路由服务: ${red_text}未运行${reset}"
                    fi
                    ;;
                "mosdns")
                    if systemctl is-active --quiet mosdns; then
                        echo -e "  DNS服务: ${green_text}运行中${reset}"
                    else
                        echo -e "  DNS服务: ${red_text}未运行${reset}"
                    fi
                    ;;
            esac
        done
        
        echo -e "\n----------------------------------------"
    }
    choose_singbox(){
        echo -e "请选择${green_text}程序${reset}"
        echo -e "${yellow}1. Sing-box官核 ${reset}${green_text}<vps自建推荐>${reset}"
        echo -e "${yellow}2. Sing-boxPuer喵佬核心${reset} <支持订阅> ${green_text}推荐${reset}"
        echo -e "${yellow}3. Sing-box曦灵X核心${reset} <支持订阅> ${green_text}推荐${reset}"
        echo -e "${yellow}4. Mihomo核心${reset}"
        echo -e "${yellow}5. Sing-box S佬Y核心${reset} <支持订阅> ${green_text}推荐${reset}"
        echo -e "${yellow}0. 返回主菜单${reset}"
        read -p "请输入选择 (1/2/3/4/5/0): " core_choice
    
        case "$core_choice" in
            1)
                echo -e "当前选择: ${green_text}Sing-BOX${reset}官方核心"        
                echo -e "请选择: ${green_text}Sing-BOX${reset}官方核心安装方式"  
                check_singbox
                choose_install_singbox
                install_josn_config
                check_ui
                install_core_service
                install_singbox_tproxy
                hy2-gohome
                install_over
                check_core_status
                ;;
            2)
                echo -e "当前选择: ${green_text} Sing-BOX ${reset}Puer喵佬核心"
                check_singbox
                check_enter
                install_josn_config
                check_ui
                install_core_service
                install_singbox_tproxy
                hy2-gohome
                check_aio
                install_over
                check_core_status
                ;;
            3)
                echo -e "当前选择: ${green_text}Sing-BOX${reset}曦灵X核心"
                check_singbox
                check_enter
                install_josn_config
                check_ui
                install_core_service
                install_singbox_tproxy  
                hy2-gohome
                check_aio
                install_over
                check_core_status
                ;;
            4)
                echo -e "当前选择: ${green_text}Mihomo${reset}核心"
                check_singbox
                check_enter
                install_josn_config
                check_ui
                install_core_service
                install_singbox_tproxy
                check_aio
                install_over
                check_core_status
                ;;
            5)
                echo -e "当前选择: ${green_text}Sing-BOX${reset}S佬Y核心"
                check_singbox
                check_enter
                install_josn_config
                check_ui
                install_core_service
                install_singbox_tproxy  
                hy2-gohome
                check_aio
                install_over
                check_core_status
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
    main(){
    echo "-------------------------------------------------"
    echo -e "${green_text}软路由透明代理方案 sing-box/mihomo + Mosdns${reset}"
    echo "-------------------------------------------------"
    echo -e "1. ${yellow}TProxy Sing-Box | Mihomo Fake-ip ${reset}${green_text}<官方内核|喵佬P核|曦灵X核|S佬Y核|Mihomo内核>${reset}"
    echo -e "2. ${yellow}Mosdns Fake-ip分流${reset}"
    echo -e "3. ${yellow}卸载 Sing-Box | Mihomo | Mosdns${reset}"
    echo "------------------------------------------------- "
    echo -e "当前机器地址:${green_text}${local_ip}${reset}"
    echo "----------------------------------------"
    check_installed
    check_core_status
    echo "========================================"
    echo -e "请选择:"
    read choice
    case $choice in
        1) 
            choose_singbox  # 先选择核心类型
            ;;
        2) 
            check_mosdns_core
            install_mosdns_config
            check_core_status
            ;;
        3) 
            uninstall_all
            ;;
        *)
            echo "无效的选项，请重新运行脚本并选择有效的选项."
        ;;
    esac
    }
    main
