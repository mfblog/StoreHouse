# !/bin/bash
green_text="\033[32m"
yellow_text="\033[33m"
red_text="\033[31m"
reset="\033[0m" 
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
die() {
    echo -e "${COLOR[red]}错误: $1${COLOR[reset]}" >&2
    exit 1
}
############################################################################################
    unbound_customize_settings() {
        echo -e "${yellow}自定义设置（以下设置可直接回车使用默认值）${reset}"
        read -p "输入内网 IPv4 地址：（默认10.10.10.0/24）：" lan_ipv4
            lan_ipv4="${lan_ipv4:-10.10.10.0/24}"
        read -p "输入内网 IPv6 地址：（默认dc00::/64）：" lan_ipv6
            lan_ipv6="${lan_ipv6:-dc00::/64}"   
        echo -e "${yellow}请设置Unboud端口"
        echo -e "${yellow}默认 53 端口，不嵌套mosdns"
        echo -e "${yellow}如果需要嵌套mosdns，请输入其他端口"
        read -p "输入Unboud 服务监听端口（默认53端口）：" ubport
            ubport="${ubport:-53}"
        echo -e "${yellow}cpu核心数设置"
        read -p "输入cpu核心数（默认1核心）：" cpu_cores
            cpu_cores="${cpu_cores:-1}"

        clear    
        echo -e "${green_text}您设定的参数：${reset}"
        echo -e "内网 IPv4 地址：${yellow}${lan_ipv4}${reset}"
        echo -e "内网 IPv6 地址：${yellow}${lan_ipv6}${reset}"
        echo -e "Unboud 服务监听端口：${yellow}${ubport}${reset}"
        echo -e "cpu核心数：${yellow}${cpu_cores}${reset}"
    }    

    unbound_settings(){
        echo -e "${yellow}配置基础设置并安装依赖...${reset}"
        sleep 1
        apt-get update -y && apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" || { echo -e "${red_text}环境更新失败！退出脚本${reset}"; exit 1; }
        echo -e "${green_text}环境更新成功${reset}"
        echo -e "${yellow}时区 NTP设置${reset}"
        timedatectl set-timezone Asia/Shanghai || { echo -e "${red_text}时区设置失败！退出脚本${reset}"; exit 1; }
        ntp_config="NTP=ntp.aliyun.com"
        echo "$ntp_config" | tee -a /etc/systemd/timesyncd.conf > /dev/null
        systemctl daemon-reload
        systemctl restart systemd-timesyncd
        echo -e "${green_text}时区 NTP 设置成功${reset}"
        check_resolved
        if apt install -y build-essential libssl-dev libexpat1-dev libsodium-dev libevent-dev libhiredis-dev libnghttp2-dev unbound-anchor bison flex libsystemd-dev libjemalloc-dev tcl gcc make dos2unix; then
        echo -e "${green_text}依赖安装成功${reset}"
        else
        echo -e "${red_text}依赖安装失败，请检查网络连接和软件包${reset}"
        exit 1
        fi
    }
# 修正后的版本获取逻辑
get_unbound_version() {
    local page_content=$(curl -fsSL "https://www.nlnetlabs.nl/downloads/unbound/")
    local ver=$(echo "$page_content" | grep -oP 'href="unbound-\K\d+\.\d+\.\d+(?=\.tar\.gz")' | sort -Vr | head -1)
    [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "版本解析失败"
    echo "$ver"
}

# 更新后的 make_unbound 函数
make_unbound() {
    
    # 获取准确版本
    local ver=$(get_unbound_version)
    echo -e "${green_text}✓ 检测到最新版本: ${ver}${reset}"
    
    # 构建完整下载链接
    local download_url="https://nlnetlabs.nl/downloads/unbound/unbound-${ver}.tar.gz"
    
    # 执行下载
    wget --quiet --show-progress -O "unbound-${ver}.tar.gz" "$download_url"
    tar -xzf "unbound-${ver}.tar.gz"
    cd "unbound-${ver}"
    # 编译器优化配置
 export CFLAGS="-flto" 
 export CXXFLAGS="-flto"

        ./configure \
        --prefix=/usr/local \
        --sbindir=/usr/local/bin \
        --sysconfdir=/etc \
        --enable-{subnet,cachedb,pie,relro-now,tfo-{client,server},dnscrypt,systemd} \
        --with-{libevent,libhiredis,ssl,libnghttp2}

    make -j$(nproc)
    make install   
    # 系统配置
    if adduser --system --group --no-create-home --disabled-login unbound; then
        echo -e "${green_text}Unbound 用户创建成功${reset}"
    else
        echo -e "${red_text}创建 Unbound 用户失败${reset}"
        exit 1
    fi
    sleep 1
    if unbound-control-setup; then
        echo -e "${green_text}Unbound 控制初始化成功${reset}"
    else
        echo -e "${red_text}初始化 Unbound 控制失败${reset}"
        
    fi
    unbound-anchor > /dev/null 2>&1
    # 配置文件
    echo " " > /etc/unbound/unbound.conf
    if ! wget --quiet --show-progress -O "/etc/unbound/unbound.conf" "https://raw.githubusercontent.com/herozmy/StoreHouse/refs/heads/latest/config/unbound/unboud.conf"; then
        echo -e "${red_text}Unbound 配置文件下载失败${reset}"
        exit 1
    fi
    echo -e "${green_text}Unbound 配置文件下载成功${reset}"
    echo -e "${yellow}开始修正unbound配置文件${reset}"
    sleep 1
    sed -i.orig \
        -e "s|access-control: 10.0.0.0/24 allow|access-control: ${lan_ipv4} allow|" \
        -e "s|access-control: dc00::/64 allow|access-control: ${lan_ipv6} allow|" \
        -e "s|port: 53|port: ${ubport}|" \
        -e "s|num-threads: 1|num-threads: ${cpu_cores}|" \
        /etc/unbound/unbound.conf
    echo -e "${green_text}Unbound 配置文件修正成功${reset}"
    # 根提示文件
    if ! wget --quiet --show-progress -O "/etc/unbound/root.hints" "https://www.internic.net/domain/named.cache"; then
        echo -e "${red_text}根提示文件下载失败${reset}"
        exit 1
    fi
    echo -e "${green_text}根提示文件下载成功${reset}"

    # 服务管理
    cp /root/unbound-${ver}/contrib/unbound.service /etc/systemd/system/
    echo -e "${green_text}Unbound 自启动服务文件配置成功${reset}"
    mkdir -p /etc/systemd/system/unbound.service.d > /dev/null 2>&1
    touch /etc/systemd/system/unbound.service.d/override.conf > /dev/null 2>&1
    cat <<EOF > /etc/systemd/system/unbound.service.d/override.conf
[Unit]
After=network-online.target redis-server.service

[Service]
LimitNOFILE=65536
RuntimeDirectoryMode=777
EOF
    systemctl daemon-reexec
    systemctl daemon-reload
    systemctl enable unbound.service

    echo -e "${green_text}Unbound 自启动服务文件配置成功${reset}"

}
get_redis_version() {
    local ver=$(curl -fsSL "https://download.redis.io/releases/" | \
        grep -oP 'redis-\K\d+\.\d+\.\d+(?=\.tar\.gz")' | sort -Vr | head -1)
    [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "版本解析失败"
    echo "$ver"
}

# Redis 安装函数
make_redis() {
    cd ~
    # 版本获取
    local ver=$(get_redis_version)
    echo -e "${green_text}✓ 检测到最新版本: ${ver}${reset}"

    local download_url="https://download.redis.io/releases/redis-${ver}.tar.gz"
    # 下载编译
    if ! wget --quiet --show-progress -O "redis-${ver}.tar.gz" "$download_url"; then
        echo -e "${red_text}Redis 下载失败${reset}"
        exit 1
    fi
    tar -xzf "redis-${ver}.tar.gz"
    cd "redis-${ver}"
    make -j$(nproc)
    make install
    # 配置文件
    mkdir -p /etc/redis
    cp redis.conf /etc/redis/redis.conf
    #
# 配置参数列表（参数名:期望值）
declare -A PARAMS=(
    ["maxmemory"]="128mb"
    ["maxmemory-policy"]="allkeys-lru"
    ["save"]='""'
    ["appendonly"]="no"
    ["lazyfree-lazy-eviction"]="yes"
    ["lazyfree-lazy-expire"]="yes"
    ["lazyfree-lazy-server-del"]="yes"
    ["replica-lazy-flush"]="yes"
    ["lazyfree-lazy-user-del"]="yes"
    ["unixsocket"]="/run/redis/redis.sock"
    ["unixsocketperm"]="777"
)

# 创建临时文件
cp /etc/redis/redis.conf /etc/redis/redis.conf.bak > /dev/null 2>&1
process_parameter() {
    local param="$1"
    local value="$2"
    local found=0

    # 处理已存在的参数
    awk -v param="$param" -v value="$value" '
    {
        # 匹配注释或未注释的参数
        if ($0 ~ "^#?[[:space:]]*" param "[[:space:]]") {
            # 提取当前值
            current_val = $0
            sub(/^#?[[:space:]]*" param "[[:space:]]+/, "", current_val)
            
            # 值正确且未注释
            if (current_val == value && $0 !~ /^#/) {
                print $0
                found = 1
                next
            }
            
            # 值正确但被注释
            if (current_val == value && $0 ~ /^#/) {
                print param " " value
                found = 1
                next
            }
            
            # 值不正确
            print param " " value
            found = 1
            next
        }
        print $0
    } END {
        if (!found) {
            print param " " value
        }
    }' /etc/redis/redis.conf > /etc/redis/redis.conf.new
    
    mv /etc/redis/redis.conf.new /etc/redis/redis.conf
}

# 处理所有参数
for param in "${!PARAMS[@]}"; do
    process_parameter "$param" "${PARAMS[$param]}"
done
cp /etc/redis/redis.conf /etc/redis/redis.conf.bak > /dev/null 2>&1

    # 服务管理
    wget --quiet --show-progress -O /etc/systemd/system/redis.service "https://raw.githubusercontent.com/herozmy/StoreHouse/refs/heads/latest/config/unbound/redis.service"
    mkdir -p /etc/systemd/system/redis.service.d
    touch /etc/systemd/system/redis.service.d/override.conf
    cat <<EOF > /etc/systemd/system/redis.service.d/override.conf
    [Service]
LimitNOFILE=65536
EOF
    systemctl daemon-reload
    systemctl enable redis.service
    echo -e "${green_text}Redis 自启动服务文件配置成功${reset}"
}
unbound_logrotate(){
    cat <<EOF > /etc/logrotate.d/unbound
/etc/unbound/unbound.log {
        copytruncate
        rotate 3
        daily
        missingok
        notifempty
        compress
}
EOF
echo "57 23 * * * /usr/sbin/logrotate -f /etc/logrotate.d/unbound" >> /etc/crontab
}
    quick_check() {
        echo -e "${yellow}查询脚本开始转快速启动...${reset}"
        sleep 2
        wget --quiet --show-progress -O /usr/bin/check https://raw.githubusercontent.com/herozmy/StoreHouse/refs/heads/latest/config/unbound/check.sh
        chmod +x /usr/bin/check
        echo -e "${green_text}查询脚本转快捷启动已完成， shell 界面输入 check 即可调用脚本显示 unboud 和 redis 命中率${reset}"
    }
    custom_settings(){
        echo -e "\n自定义设置（以下设置可直接回车使用默认值）"
        read -p "输入sing-box/mihomo入站地址（默认10.10.10.147:6666）：" uiport
        uiport="${uiport:-10.10.10.147:6666}"
        echo -e "已设置sing-box/mihomo入站地址：\e[36m$uiport\e[0m"
        echo "
        proxy_ip.txt填写10.0.0.10  ，则客户端返回真实ip，包括国内外也是真实ip。
        fake_ip.txt填写10.0.0.11  ，则客户端国内域名返回真实ip，国外域名返回fake-ip。
        不在这两个表内的客户端，    则客户端国内域名返回真实ip，国外域名返回nxmodian。
        切记同一个ip只能填到其中一个表。
        优先级说明： proxy_ip.txt > fake_ip.txt  如只需要fake模式请在fake_ip.txt表填入0.0.0.0/0 proxy_ip.txt表请留空。
        "
        echo -e "${yellow}本脚本默认使用fake模式${reset}"
        read -p "输入fake_ip.txt文件内容（默认0.0.0.0/0）：" fake_ip
        fake_ip="${fake_ip:-0.0.0.0/0}"
        echo "$fake_ip" > /etc/mosdns/config/fake_ip.txt
        echo -e "${green_text}已设置fake_ip内容：\e[36m$fake_ip${reset}"
    }
    unbound_customize_settings
    unbound_settings
    make_unbound
    make_redis
    if [ "$ubport" != "53" ]; then
        echo -e "${yellow}Unbound 服务监听端口不是 53 端口，则默认启动mosdns嵌套${reset}"
        read -p "是否继续启动mosdns嵌套？（y/n）：" mosdns_choice
        if [ "$mosdns_choice" == "y" ]; then
            echo -e "${green_text}安装mosdns嵌套${reset}"
            . $DIRPATH/mosdns.sh cn_mosdns
            echo -e "${green_text}mosdns嵌套安装成功${reset}"
            sleep 1
            custom_settings
            echo -e "${yellow}修正mosdns嵌套规则${reset}"
            sleep 1
            sed -i "s/8053/$ubport/g" /etc/mosdns/config.yaml
            sed -i "s/- addr: \"10.0.0.6:53\"/- addr: \"${uiport}\"/g" /etc/mosdns/config.yaml
            echo -e "${green_text}mosdns嵌套规则修正成功${reset}"
            . $DIRPATH/mosdns.sh get_mosdns_rule
            systemctl restart mosdns.service
            . $DIRPATH/mosdns.sh mosdns_logrotate
        fi
    fi
    systemctl start redis.service
    systemctl start unbound.service
    quick_check