#! /bin/bash
########################################################
# 代理方案选择脚本
# 作者: herozmy
# 版本: 1.0
# 日期: 2025-04-13
########################################################

################################################# 颜色定义
green_text="\033[32m"
yellow_text="\033[33m"
red_text="\033[31m"
reset="\033[0m" 
DIRPATH="/usr/local/bin/tools/"
red() {
    echo -e "\e[31m$1\e[0m"
}

green() {
    echo -e "\e[32m$1\e[0m"
}

yellow() {
    echo -e "\e[33m$1\e[0m"
}
################################################# 变量定义
local_ip=$(hostname -I | awk '{print $1}')
url="https://raw.githubusercontent.com/herozmy/StoreHouse/latest/"
#url="https://d.herozmy.com/"
#cn_url='https://fastly.jsdelivr.net/gh/herozmy/StoreHouse@latest'

    check_core_status() {
       # echo -e "\n${yellow}检查服务状态...${reset}"
        #echo -e "----------------------------------------"
        # 查找已安装的程序
        found_files=$(find /usr/local/bin/ -type f \( -name "mihomo" -o -name "sing-box" -o -name "mosdns"  -o -name "unbound"  -o -name "redis-server" \))
        
        if [ -z "$found_files" ]; then
            return
        fi        
        # 遍历检查每个已安装的程序
        for file in $found_files; do
            program=$(basename "$file")
            echo -e "\n${program}:"
            case "$program" in
                "sing-box"|"mihomo")
                    if systemctl is-active --quiet ${program}; then
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
                "unbound")
                    if systemctl is-active --quiet unbound; then
                        echo -e "  DNS服务: ${green_text}运行中${reset}"
                    else
                        echo -e "  DNS服务: ${red_text}未运行${reset}"
                    fi
                    ;;
                "redis-server")
                    if systemctl is-active --quiet redis; then
                        echo -e "  Redis服务: ${green_text}运行中${reset}"
                    else
                        echo -e "  Redis服务: ${red_text}未运行${reset}"
                    fi
            esac
        done
        
        echo -e "\n----------------------------------------"
    }

download(){
### 参考shellcrash 所写函数
	#参数【$1】代表下载目录，【$2】代表在线地址
	#参数【$3】代表输出显示，【$4】不启用重定向
	if curl --version >/dev/null 2>&1; then
		[ "$3" = "echooff" ] && progress='-s' || progress='-#'
		[ -z "$4" ] && redirect='-L' || redirect=''
		result=$(curl -w %{http_code} --connect-timeout 5 $progress $redirect -ko $1 $2)
		[ -n "$(echo $result | grep -e ^2)" ] && result="200"
	else
		if wget --version >/dev/null 2>&1; then
			[ "$3" = "echooff" ] && progress='-q' || progress='-q --show-progress'
			[ "$4" = "rediroff" ] && redirect='--max-redirect=0' || redirect=''
			certificate='--no-check-certificate'
			timeout='--timeout=3'
		fi
		[ "$3" = "echoon" ] && progress=''
		[ "$3" = "echooff" ] && progress='-q'
		wget $progress $redirect $certificate $timeout -O $1 $2
		[ $? -eq 0 ] && result="200"
	fi
}

error_download(){
    echo -e "${red_text}下载失败，请检查网络连接或稍后再试。${reset}"
}
get_script(){
    # 下载脚本
    download tmp/StoreHouse.tar.gz $url/StoreHouse.tar.gz
	if [ "$result" != "200" ]; then
		echo -e "${red_text}文件下载失败！${reset}"
		error_download
		exit 1
	else
    # 解压脚本
    if ! tar -zxvf /tmp/StoreHouse.tar.gz -C $DIRPATH; then
        echo -e "${red_text}文件解压失败！${reset}"
        exit 1
    fi    
    fi
}

quick(){
        touch /usr/bin/tools 2>/dev/null && {
            cat >/usr/bin/tools <<EOF
            #!/bin/bash
            $DIRPATH/menu.sh \$1 \$2 \$3 \$4 \$5
EOF
            chmod +x /usr/bin/tools
        }
}

install(){
    echo -e "${green_text}安装脚本...${reset}"
    get_script
    echo -e "${green_text}安装完成！${reset}"
    quick
	echo -----------------------------------------------
	$echo "\033[33m输入\033[30;47m tools \033[0;33m命令即可管理！！！\033[0m"
	echo ----------------------------------------------- 
}
# 检查是否是 root 用户
if [ "$(id -u)" != "0" ]; then
    echo -e "\033[31m错误：请使用 root 用户执行此脚本！\033[0m"
    echo -e "请执行以下命令切换用户：\n  sudo su -"
    exit 1
fi
if [ -n "$DIRPATH" ]; then
    echo -e "${green_text}检测到旧的安装目录$DIRPATH${reset}"
    echo -e "${yellow_text}是否删除旧的安装目录？${reset}"
    read -p "请输入(y/n): " choice
    if [ "$choice" = "y" ]; then
        rm -rf $DIRPATH
        echo -e "${green_text}旧的安装目录已删除！${reset}"
        install
    elif [ "$choice" = "n" ]; then
        install
    else
        echo -e "${red_text}输入错误！${reset}"
        exit 1
    fi
else
    install
fi

