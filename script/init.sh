#!/bin/bash
#
# 服务清理与备份脚本 (重构优化版)
#
# 功能: 停止指定服务，备份核心文件、配置文件和服务文件，然后清理原文件。
#

# --- 脚本设置 ---
# set -e: 当任何命令返回非零退出码时，立即退出脚本。
# set -o pipefail: 在管道中，只要有任何一个命令失败，整个管道的退出码就为非零。
set -e
set -o pipefail
common_path="/usr/local/bin/tools/common.sh"
source "$common_path"

# --- 主函数 ---
main() {
    # 1. 参数检查与变量初始化
    if [ $# -ne 3 ]; then
        log_error "用法: . $0 <服务名> <核心文件路径> <配置目录>"
        log_error "示例: . $0 sing-box /usr/local/bin/sing-box /etc/sing-box"
        # 兼容被 source 和直接执行两种情况
        return 1 2>/dev/null || exit 1
    fi

    local service_name="$1"
    local core_file="$2"
    local config_dir="$3"
    local timestamp
    timestamp=$(date +%Y%m%d%H%M%S)

    # 2. 执行核心流程
    log_info "开始处理服务: $service_name"
    
    # 创建备份根目录
    mkdir -p "$BAK_ROOT"

    stop_and_disable_service "$service_name"
    backup_files "$service_name" "$core_file" "$config_dir" "$timestamp"
    cleanup_files "$core_file" "$service_name"

    # 3. 输出总结信息
    echo # 添加一个空行以改善格式
    log_success "所有操作完成！"
    log_info "备份文件已创建，位于 $BAK_ROOT"
    log_info "与本次操作相关的备份文件如下:"
    # -print0 和 xargs -0 是一种更安全处理带空格文件名的方式
    find "$BAK_ROOT" -name "*${timestamp}*" -print0 | xargs -0 -I {} echo -e "  ${YELLOW}{}${RESET}"
}

# --- 辅助函数 ---

# 停止并禁用服务
# 由于设置了 'set -e'，任何 systemctl 命令失败都会自动终止脚本。
stop_and_disable_service() {
    local service_name=$1
    log_info "处理 systemd 服务..."

    if systemctl is-active --quiet "$service_name"; then
        log_warn "服务正在运行，现在停止..."
        systemctl stop "$service_name"
        log_success "服务已停止。"
    else
        log_success "服务当前未运行。"
    fi

    if systemctl is-enabled --quiet "$service_name"; then
        log_warn "服务设置为开机自启，现在禁用..."
        systemctl disable "$service_name"
        log_success "服务已禁用开机自启。"
    else
        log_success "服务未设置开机自启。"
    fi
}

# 备份所有相关文件
backup_files() {
    local service_name=$1
    local core_file=$2
    local config_dir=$3
    local timestamp=$4
    local service_file="/etc/systemd/system/${service_name}.service"

    log_info "开始备份文件..."

    # 备份核心文件
    if [ -f "$core_file" ]; then
        local core_backup="${core_file}_${timestamp}_bak"
        cp -v "$core_file" "$core_backup"
        log_success "核心文件备份至: $core_backup"
    else
        log_warn "核心文件不存在，跳过备份: $core_file"
    fi

    # 备份配置目录
    if [ -d "$config_dir" ]; then
        local config_backup="${BAK_ROOT}/${service_name}_config_${timestamp}.tar.gz"
        # -C 选项让 tar 先切换到指定目录，再打包，避免在压缩包中产生绝对路径。
        # "${config_dir%/*}" 获取父目录 (e.g., /etc)
        # "${config_dir##*/}" 获取目录名 (e.g., sing-box)
        tar -zcf "$config_backup" -C "${config_dir%/*}" "${config_dir##*/}"
        log_success "配置目录备份至: $config_backup"
    else
        log_warn "配置目录不存在，跳过备份: $config_dir"
    fi

    # 备份服务文件
    if [ -f "$service_file" ]; then
        local service_backup="${BAK_ROOT}/${service_name}.service_${timestamp}_bak"
        cp -v "$service_file" "$service_backup"
        log_success "服务文件备份至: $service_backup"
    else
        log_warn "服务文件不存在，跳过备份: $service_file"
    fi
}

# 清理旧文件 (保留配置文件)
cleanup_files() {
    local core_file=$1
    local service_name=$2
    local service_file="/etc/systemd/system/${service_name}.service"

    log_info "开始清理旧文件..."

    # 删除核心文件
    if [ -f "$core_file" ]; then
        rm -v "$core_file"
        log_success "已移除核心文件: $core_file"
    fi

    # 删除服务文件
    if [ -f "$service_file" ]; then
        rm -v "$service_file"
        log_success "已移除服务文件: $service_file"
    fi

    log_info "根据设计，配置文件目录被保留。"
}


# --- 脚本执行入口 ---
# 将所有命令行参数传递给 main 函数
main "$@"