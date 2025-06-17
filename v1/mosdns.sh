#!/bin/bash
#####
green_text="\033[32m"
yellow_text="\033[33m"
red_text="\033[31m"
reset="\033[0m" 
sub_host="https://sub-singbox.herozmy.com"
json_file="&file=https://raw.githubusercontent.com/herozmy/StoreHouse/refs/heads/latest/config/sing-box/sing-box.json"
local_ip=$(hostname -I | awk '{print $1}')
DIRPATH="/usr/local/bin/tools"

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
    get_mosdns_rule(){
    MOSDNS_INSTALL_DIR="/opt/mosdns_install"
    RULESET_URLS=(
    "https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/direct-list.txt geosite_cn.txt"
    "https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/proxy-list.txt geosite_no_cn.txt"
    "https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/gfw.txt gfw.txt"
    "https://file.bairuo.net/iplist/output/Aggregated_ChinaAllNetwork_IPv4.txt ChinaAllNetwork_IPv4.txt"
    "https://file.bairuo.net/iplist/output/Aggregated_ChinaAllNetwork_IPv6.txt ChinaAllNetwork_IPv6.txt"
    "https://file.bairuo.net/iplist/output/Aggregated_ChinaEducation_IPv4.txt ChinaEducation_IPv4.txt"
    "https://file.bairuo.net/iplist/output/Aggregated_ChinaEducation_IPv6.txt ChinaEducation_IPv6.txt"
    "https://file.bairuo.net/iplist/output/Aggregated_ChinaMobile_IPv4.txt ChinaMobile_IPv4.txt"
    "https://file.bairuo.net/iplist/output/Aggregated_ChinaMobile_IPv6.txt ChinaMobile_IPv6.txt"
    "https://file.bairuo.net/iplist/output/Aggregated_ChinaSciences_IPv4.txt ChinaSciences_IPv4.txt"
    "https://file.bairuo.net/iplist/output/Aggregated_ChinaSciences_IPv6.txt ChinaSciences_IPv6.txt"
    "https://file.bairuo.net/iplist/output/Aggregated_ChinaTelecom_IPv4.txt ChinaTelecom_IPv4.txt"
    "https://file.bairuo.net/iplist/output/Aggregated_ChinaTelecom_IPv6.txt ChinaTelecom_IPv6.txt"
    "https://file.bairuo.net/iplist/output/Aggregated_ChinaUnicom_IPv4.txt ChinaUnicom_IPv4.txt"
    "https://file.bairuo.net/iplist/output/Aggregated_ChinaUnicom_IPv6.txt ChinaUnicom_IPv6.txt"
)

# 创建安装目录
install -d -m 755 "$MOSDNS_INSTALL_DIR" || {
    echo "无法创建目录: $MOSDNS_INSTALL_DIR" >&2
    exit 1
}

# 下载文件函数
download_files() {
    local retry_count=3
    for entry in "${RULESET_URLS[@]}"; do
        local url="${entry%% *}"
        local filename="${entry##* }"
        
        for ((i=1; i<=retry_count; i++)); do
            if curl -sSfL --connect-timeout 30 --retry 2 -o "$MOSDNS_INSTALL_DIR/$filename" "$url"; then
                if [ -s "$MOSDNS_INSTALL_DIR/$filename" ]; then
                    echo "[成功] 下载: $filename"
                    break
                else
                    echo "[警告] 空文件: $filename" >&2
                    rm -f "$MOSDNS_INSTALL_DIR/$filename"
                fi
            else
                if [ $i -eq $retry_count ]; then
                    echo "[错误] 下载失败: $filename" >&2
                    return 1
                fi
                sleep 1
            fi
        done
    done
}

# 验证文件完整性
validate_files() {
    local ipv4_files=()
    local ipv6_files=()
    
    while IFS= read -r file; do
        if grep -qE '^[0-9]{1,3}(\.[0-9]{1,3}){3}(/[0-9]+)?$' "$file"; then
            ipv4_files+=("$file")
        elif grep -qE '^[0-9a-fA-F:]+(/[0-9]+)?$' "$file"; then
            ipv6_files+=("$file")
        else
            echo "[错误] 无效IP文件: $(basename "$file")" >&2
            return 1
        fi
    done < <(find "$MOSDNS_INSTALL_DIR" -maxdepth 1 -type f \( -name "*IPv4.txt" -o -name "*IPv6.txt" \))

    if [ ${#ipv4_files[@]} -lt 6 ] || [ ${#ipv6_files[@]} -lt 6 ]; then
        echo "[错误] 缺少必要的IP文件" >&2
        return 1
    fi
}

# 合并IP文件
merge_ip_files() {
    cat "$MOSDNS_INSTALL_DIR/"*IPv4.txt > "$MOSDNS_INSTALL_DIR/geoip_cn.txt"
    cat "$MOSDNS_INSTALL_DIR/"*IPv6.txt >> "$MOSDNS_INSTALL_DIR/geoip_cn.txt"
    
    if [ -s "$MOSDNS_INSTALL_DIR/geoip_cn.txt" ]; then
        echo "[成功] 生成geoip_cn.txt"
    else
        echo "[错误] 生成geoip文件失败" >&2
        return 1
    fi
}

    echo "=== 开始更新MosDNS规则集 ==="
    
    if ! download_files; then
        echo "下载失败，请检查网络连接" >&2
        exit 1
    fi
    
    if ! validate_files; then
        echo "文件验证失败" >&2
        exit 2
    fi
    
    if ! merge_ip_files; then
        exit 3
    fi
    
    # 复制非IP文件
    find "$MOSDNS_INSTALL_DIR" -maxdepth 1 -type f \( -not -name "*IPv4*" -and -not -name "*IPv6*" \) \
        -exec cp -v {} /etc/mosdns \;    
    echo "=== 更新完成 ==="
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
               # [ -f /usr/local/bin/sing-box -o -f /usr/local/bin/mihomo ] && systemctl stop "$([ -f /usr/local/bin/sing-box ] && echo 'sing-box' || echo 'mihomo')-router"; [ -f /usr/local/bin/sing-box -o -f /usr/local/bin/mihomo ] && systemctl start "$([ -f /usr/local/bin/sing-box ] && echo 'sing-box' || echo 'mihomo')-router"
            else
                echo -e "${red_text}配置错误，回滚修改${reset}"
                sed -i '/\(223.5.5.5\/32\|223.6.6.6\/32\|2400:3200::1\/128\|2400:3200:baba::1\/128\),/d' "$NFT_RULESET"
            fi
        fi
    }
cn_mosdns_install(){
    echo -e "${green_text}安装cn佬mosdns嵌套规则${reset}"
    mkdir -p /etc/systemd/system/mosdns.service.d
    touch /etc/systemd/system/mosdns.service.d/override.conf
    cat <<EOF > /etc/systemd/system/mosdns.service.d/override.conf
[Service]
LimitNOFILE=65536
EOF
    systemctl daemon-reexec
    systemctl daemon-reload
    wget --quiet --show-progress -O mosdns.zip https://github.com/herozmy/StoreHouse/raw/refs/heads/latest/config/mosdns/cn_mosdns/cn_mosdns.zip &&
    mkdir -p /etc/mosdns/ &&
    unzip mosdns.zip -d /etc/mosdns/
    rm -f mosdns.zip
}
mosdns_logrotate(){
    cat <<EOF > /etc/logrotate.d/mosdns
/etc/mosdns/mosdns.log {
        copytruncate
        rotate 3
        daily
        missingok
        notifempty
        compress
}
EOF
echo "57 23 * * * /usr/sbin/logrotate -f /etc/logrotate.d/mosdns" >> /etc/crontab
}
######主安装脚本
mosdns_install(){
        arch=$(detect_architecture)
        echo "系统架构是：$arch"
        mosdns_host="https://github.com/herozmy/StoreHouse/releases/download/mosdns/mosdns-linux-$arch.zip"
        apt update && apt -y upgrade || { echo "更新失败！退出脚本"; exit 1; }
        apt install curl wget git tar gawk sed cron unzip nano -y || { echo "更新失败！退出脚本"; exit 1; }
        wget "${mosdns_host}" || { echo -e "\e[31m下载失败！退出脚本\e[0m"; exit 1; }
        echo "开始解压"
        unzip -o ./mosdns-linux-$arch.zip 
        sleep 1
        mv -v ./mosdns /usr/local/bin/
        rm -rf mosdns-linux-$arch.zip
        chmod 0777 /usr/local/bin/mosdns 
        echo -e "\n设置时区为Asia/Shanghai"
        timedatectl set-timezone Asia/Shanghai || { echo -e "\e[31m时区设置失败！退出脚本\e[0m"; exit 1; }
        echo -e "\e[32m时区设置成功\e[0m"
}
mosdns_rule(){
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
                wget --quiet --show-progress -O mosdns.zip https://github.com/herozmy/StoreHouse/raw/refs/heads/latest/config/mosdns/ph/mosdns20250401.zip &&
                mkdir -p /etc/mosdns/ &&
                unzip mosdns.zip -d /etc/mosdns/
                echo -e "${green_text}请选择：20250401规则版本${reset}"
                echo "
                ————————————————
                1. leak版  <默认>
                2. noleak版
                "
                read -p "请输入选择 [1-2] 回车默认1: " num
                case "${num}" in
                1)
                    mv /etc/mosdns/config_leak.yaml /etc/mosdns/config.yaml
                    ;;
                2)
                    mv /etc/mosdns/config_noleak.yaml /etc/mosdns/config.yaml
                    ;;
                *)
                    mv /etc/mosdns/config_leak.yaml /etc/mosdns/config.yaml
                    ;;
                esac
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
}
mosdns_service(){
        echo -e "${yellow}设置mosdns开机自启动${reset}"
        mosdns service install -d /etc/mosdns -c /etc/mosdns/config.yaml
        echo -e "${green_text}mosdns开机启动完成${reset}"
        sleep 1
        systemctl restart mosdns
        check_aio
        echo -----------------------------------------------
        echo -e "${green_text}请使用${reset} ${yellow_text}systemctl restart mosdns${reset} ${green_text}重启mosdns${reset}"
        echo -e "${green_text}请使用${reset} ${yellow_text}systemctl stop mosdns${reset} ${green_text}停止mosdns${reset}"
        echo -e "${green_text}请使用${reset} ${yellow_text}systemctl enable mosdns${reset} ${green_text}设置开机自启动${reset}"
        echo -e "${green_text}请使用${reset} ${yellow_text}systemctl disable mosdns${reset} ${green_text}禁用开机自启动${reset}"
        echo -----------------------------------------------
        echo -e "${green_text}请使用${reset} ${yellow_text}proxytool${reset} ${green_text}快速管理mosdns${reset}"
}
case "$1" in
    cn_mosdns)
        mosdns_install && cn_mosdns_install
        return 0
        ;;
    get_mosdns_rule)
        get_mosdns_rule
        return 0
        ;;
    mosdns_logrotate)
        mosdns_logrotate
        return 0
        ;;
    mosdns_service)
        mosdns_service
        return 0
        ;;
esac
mosdns_install
mosdns_rule
mosdns_logrotate
mosdns_service