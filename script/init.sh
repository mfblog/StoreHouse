#!/bin/bash
# 服务清理备份脚本

# 颜色定义
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
RESET='\033[0m'

# 参数检查
if [ $# -ne 3 ]; then
    echo -e "${RED}用法: . $0 <服务名> <核心文件路径> <配置目录>${RESET}"
    echo -e "示例: . init.sh sing-box /usr/local/bin/sing-box /etc/sing-box"
    return 1 2>/dev/null || exit 1
fi

# 基础变量
SERVICE_NAME="$1"
CORE_FILE="$2"
CONFIG_DIR="$3"
BAK_ROOT="/usr/local/bin/bak"
TIMESTAMP=$(date +%Y%m%d%H%M%S)

# 创建备份目录
mkdir -p "$BAK_ROOT" || {
    echo -e "${RED}创建备份目录失败: $BAK_ROOT${RESET}"
    return 1 2>/dev/null || exit 1
}

# 停止服务
stop_service() {
    echo -e "${BLUE}=== 停止服务 ===${RESET}"
    
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo -e "${YELLOW}正在停止服务...${RESET}"
        systemctl stop "$SERVICE_NAME" || {
            echo -e "${RED}服务停止失败${RESET}"
            return 1
        }
    fi

    if systemctl is-enabled --quiet "$SERVICE_NAME"; then
        echo -e "${YELLOW}移除服务自启动...${RESET}"
        systemctl disable "$SERVICE_NAME" || {
            echo -e "${RED}禁用服务失败${RESET}"
            return 1
        }
    fi
}

# 执行备份
do_backup() {
    echo -e "${BLUE}=== 执行备份 ===${RESET}"

    # 备份核心文件
    if [ -f "$CORE_FILE" ]; then
        local core_backup="${CORE_FILE}_${TIMESTAMP}_bak"
        cp -v "$CORE_FILE" "$core_backup" && \
        echo -e "${GREEN}核心文件备份完成: ${core_backup}${RESET}"
    else
        echo -e "${YELLOW}核心文件不存在: ${CORE_FILE}${RESET}"
    fi

    # 备份配置目录
    if [ -d "$CONFIG_DIR" ]; then
        local config_backup="${BAK_ROOT}/${SERVICE_NAME}_config_${TIMESTAMP}.tar.gz"
        tar -zcf "$config_backup" -C "${CONFIG_DIR%/*}" "${CONFIG_DIR##*/}" && \
        echo -e "${GREEN}配置备份完成: ${config_backup}${RESET}"
    else
        echo -e "${YELLOW}配置目录不存在: ${CONFIG_DIR}${RESET}"
    fi

    # 备份服务文件
    local service_file="/etc/systemd/system/${SERVICE_NAME}.service"
    if [ -f "$service_file" ]; then
        local service_backup="${BAK_ROOT}/${SERVICE_NAME}.service_${TIMESTAMP}_bak"
        cp -v "$service_file" "$service_backup" && \
        echo -e "${GREEN}服务文件备份完成: ${service_backup}${RESET}"
    else
        echo -e "${YELLOW}服务文件不存在: ${service_file}${RESET}"
    fi
}

# 清理文件
do_clean() {
    echo -e "${BLUE}=== 执行清理 ===${RESET}"

    # 删除核心文件
    if [ -f "$CORE_FILE" ]; then
        rm -v "$CORE_FILE" && \
        echo -e "${YELLOW}已移除核心文件${RESET}"
    fi

    # 删除服务文件
    local service_file="/etc/systemd/system/${SERVICE_NAME}.service"
    if [ -f "$service_file" ]; then
        rm -v "$service_file" && \
        echo -e "${YELLOW}已移除服务文件${RESET}"
    fi

    # 保留配置目录
    echo -e "${YELLOW}配置目录保留: ${CONFIG_DIR}${RESET}"
}

# 主流程
main() {
    # 停止服务
    if ! stop_service; then
        echo -e "${RED}服务停止流程异常，终止执行${RESET}"
        return 1
    fi

    # 执行备份
    do_backup

    # 执行清理
    do_clean

    echo -e "\n${GREEN}=== 操作完成 ===${RESET}"
    echo -e "可重新安装时使用备份文件："
    find "$BAK_ROOT" -name "*${TIMESTAMP}*" -print
}

# 执行入口
main