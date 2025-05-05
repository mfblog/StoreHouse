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
        read -p "输入Unboud 服务监听端口（默认1053端口）：" ubport
            ubport="${ubport:-1053}"
        clear    
        echo -e "${green_text}您设定的参数：${reset}"
        echo -e "内网 IPv4 地址：${yellow}${lan_ipv4}${reset}"
        echo -e "内网 IPv6 地址：${yellow}${lan_ipv6}${reset}"
        echo -e "Unboud 服务监听端口：${yellow}${ubport}${reset}"
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


setup_service() {
    local service=$1 config_url=$2
    fetch_resource "$config_url" "/etc/systemd/system/$service.service"
    systemctl daemon-reload
    systemctl enable --now "$service" || {
        journalctl -u "$service" -n 20 --no-pager | grep -iC3 error >&2
        die "服务启动失败"
    }
}
fetch_resource() {
    local url=$1 dest=${2:-${url##*/}}
    echo -e "${COLOR[yellow]}» 下载 ${dest}${COLOR[reset]}"
    
    # 强制使用绝对路径
    dest="$(realpath -m "$dest")"
    mkdir -p "$(dirname "$dest")" || die "目录创建失败: $(dirname "$dest")"

    # 增强版下载命令
    if ! wget --quiet --show-progress -O "$dest" \
        "$url"; then       
        die "下载失败: $url (退出码: $?)"
    fi
}

# 修正后的版本获取逻辑
get_unbound_version() {
    local page_content=$(curl -fsSL "https://www.nlnetlabs.nl/downloads/unbound/")
    local ver=$(echo "$page_content" | grep -oP 'href="unbound-\K\d+\.\d+\.\d+(?=\.tar\.gz")' | sort -Vr | head -1)
    [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "版本解析失败"
    echo "$ver"
}


compile_install() {
    local pkg_path="$1"
    
    # 强制转换为绝对路径
    pkg_path="$(realpath "$pkg_path")" || die "文件不存在: $pkg_path"
    echo -e "» 使用源码包: ${COLOR[cyan]}${pkg_path}${COLOR[reset]}"
    
    # 创建带版本号的构建目录
    build_dir="/tmp/build-${pkg_path##*/}"
    mkdir -p "$build_dir" || die "目录创建失败: $build_dir"
    
    (
        echo -e "» 解压到: ${COLOR[cyan]}${build_dir}${COLOR[reset]}"
        tar xzf "${pkg_path}" -C "${build_dir}" --strip-components=0 || die "解压失败"
        
        # 自动进入源码目录
        cd "$build_dir"/*/ || die "无法进入源码目录"
        echo -e "当前工作目录: ${COLOR[cyan]}$(pwd)${COLOR[reset]}"
        
        # 智能编译判断
        if [ -f configure ]; then
            echo -e "${COLOR[yellow]}» 检测到configure脚本${COLOR[reset]}"
            ./configure "${@:2}" && make -j$(nproc) && make install
        elif [ -f Makefile ] || [ -f makefile ]; then
            echo -e "${COLOR[yellow]}» 直接执行make${COLOR[reset]}"
            make -j$(nproc) && make install
        elif [ -f CMakeLists.txt ]; then
            echo -e "${COLOR[yellow]}» 检测到CMake项目${COLOR[reset]}"
            cmake . && make -j$(nproc) && sudo make install
        else
            die "无法识别的编译方式，目录内容：\n$(ls -l)"
        fi
    )
}
# 更新后的 make_unbound 函数
make_unbound() {
    
    # 获取准确版本
    local ver=$(get_unbound_version)
    echo -e "${COLOR[green]}✓ 检测到最新版本: ${ver}${COLOR[reset]}"
    
    # 构建完整下载链接
    local download_url="https://nlnetlabs.nl/downloads/unbound/unbound-${ver}.tar.gz"
    local dest_file="/tmp/unbound-${ver}.tar.gz"
    
    # 执行下载
    fetch_resource "$download_url" "$dest_file"
    compile_install "/tmp/unbound-${ver}.tar.gz" \
        --prefix=/usr/local \
        --sbindir=/usr/local/bin \
        --sysconfdir=/etc \
        --enable-{subnet,cachedb,pie,relro-now,tfo-{client,server},dnscrypt,systemd} \
        --with-{libevent,libhiredis,ssl,libnghttp2}
   
    
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
    fetch_resource \
        "https://raw.githubusercontent.com/herozmy/StoreHouse/refs/heads/latest/config/unbound/unboud.conf" \
        "/etc/unbound/unbound.conf"
    sed -i.orig \
        -e "s|access-control: 10.0.0.0/24 allow|access-control: ${lan_ipv4} allow|" \
        -e "s|access-control: dc00::/64 allow|access-control: ${lan_ipv6} allow|" \
        -e "s|port: 53|port: ${ubport}|" \
        /etc/unbound/unbound.conf

    # 根提示文件
    fetch_resource "https://www.internic.net/domain/named.cache" \
        "/etc/unbound/root.hints"


    # 服务管理
    setup_service unbound \
        "https://raw.githubusercontent.com/herozmy/StoreHouse/refs/heads/latest/config/unbound/unbound.service"
    # 验证端口
   local port=$(ss -Hulpn "sport = :${ubport}" | awk '{print $5}' | cut -d: -f2)
    echo -e "${COLOR[green]}[✓] Unbound 运行正常 (端口: ${port})${COLOR[reset]}"
}

# Redis 安装函数
make_redis() {
    init_environment
    
    # 版本获取
    local ver=$(curl -fsSL "https://download.redis.io/releases/" | \
        grep -oP 'redis-\K\d+\.\d+\.\d+(?=\.tar\.gz")' | sort -Vr | head -1)
    [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "版本解析失败"

    local download_url="https://download.redis.io/releases/redis-${ver}.tar.gz"
    local dest_file="/tmp/redis-${ver}.tar.gz"
    # 下载编译
    fetch_resource "$download_url" "$dest_file"

    compile_install "/tmp/redis-${ver}.tar.gz"

    # 配置文件
    mkdir -p /etc/redis
    fetch_resource \
        "https://raw.githubusercontent.com/herozmy/StoreHouse/refs/heads/latest/config/unbound/redis.conf" \
        "/etc/redis/redis.conf"

    # 服务管理
    setup_service redis \
        "https://raw.githubusercontent.com/herozmy/StoreHouse/refs/heads/latest/config/unbound/redis.service"

    # 版本验证
    echo -e "${COLOR[green]}[✓] Redis 运行正常 (版本: ${ver})${COLOR[reset]}"
}



    quick_check() {
        echo -e "${yellow}查询脚本开始转快速启动...${reset}"
        sleep 2
        wget --quiet --show-progress -O /usr/bin/check https://raw.githubusercontent.com/herozmy/StoreHouse/refs/heads/latest/config/unbound/check.sh
        chmod +x /usr/bin/check
        echo -e "${green_text}查询脚本转快捷启动已完成， shell 界面输入 check 即可调用脚本显示 unboun 和 redis 命中率${reset}"
    }