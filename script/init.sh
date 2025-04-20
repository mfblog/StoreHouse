#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

# 检查是否为 root 用户
if [ "$(id -u)" != "0" ]; then
    echo -e "\033[31m错误：请使用 root 用户执行此脚本！\033[0m"
    exit 1
fi

# 定义备份目录
backup_dir="/usr/local/bin/bak"
mkdir -p "$backup_dir" || { echo "无法创建备份目录！"; exit 1; }

# 备份指定服务
backup_service() {
    local service="$1"
    local service_file="/etc/systemd/system/${service}.service"

    # 如果找到服务文件
    if [ -f "$service_file" ]; then
        echo -e "\033[33m正在处理 $service...\033[0m"
        
        # 停止服务
        if systemctl is-active --quiet "$service"; then
            echo "正在停止 $service 服务..."
            systemctl stop "$service" || { echo -e "\033[31m停止 $service 服务失败！\033[0m"; exit 1; }
        fi
        # 移除自启动
        systemctl disable "$service"
        # 备份服务文件
        echo "正在备份 $service.service..."
        cp -v "$service_file" "$backup_dir/" || { echo -e "\033[31m备份 $service.service 失败！\033[0m"; exit 1; }
    else
        echo -e "\033[33m未找到 $service.service 文件，跳过处理。\033[0m"
    fi
}

# 备份指定服务
if [ -n "$1" ]; then
    backup_service "$1"
else
    echo -e "\033[31m错误：请指定要备份的服务！\033[0m"
    exit 1
fi

# 备份指定核心文件、配置文件和文件夹
echo "正在备份 核心文件、配置文件和文件夹..."
for file in "${@:2}"; do
    if [ -e "$file" ]; then
        cp -rv "$file" "$backup_dir/" || { echo -e "\033[31m备份 $file 失败！\033[0m"; exit 1; }
    else
        echo -e "\033[33m未找到 $file 文件或文件夹，跳过处理。\033[0m"
    fi
done
echo -e "\033[32m已完成 核心文件、配置文件和文件夹 的备份到 $backup_dir\033[0m"