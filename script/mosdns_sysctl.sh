#!/usr/bin/env bash
# MosDNS RON 系统优化脚本：安装/启用 BBR + 在 /etc/sysctl.d/99-sysctl.conf 中配置系统参数
#set -euo pipefail

# --- 引入通用工具库 ---
readonly COMMON_UTILS_PATH="/usr/local/bin/tools/common.sh"
if [ -f "$COMMON_UTILS_PATH" ]; then
    source "$COMMON_UTILS_PATH"
else
    # 如果找不到依赖库，打印清晰的错误信息并退出
    echo -e "\033[31m✖ 致命错误: 依赖库缺失: $COMMON_UTILS_PATH\033[0m" >&2
    exit 1
fi

# 检查运行权限
if [[ $EUID -ne 0 ]]; then
    log_error "请使用 root 权限运行此脚本"
    exit 1
fi

# 检查系统兼容性
if ! command -v sysctl &> /dev/null; then
    log_error "系统不支持 sysctl 命令，无法继续"
    exit 1
fi

# 检查是否为 systemd 系统
if ! systemctl --version &> /dev/null; then
    log_warn "检测到非 systemd 系统，某些功能可能不可用"
fi

CONF_DIR="/etc/sysctl.d"
CONF_FILE="${CONF_DIR}/99-sysctl.conf"
MODULES_FILE="/etc/modules-load.d/bbr-fq.conf"

# 显示使用说明
show_usage() {
    echo "使用方法:"
    echo "  $0 install   - 安装系统优化配置"
    echo "  $0 uninstall - 卸载系统优化配置"
    echo "  $0 status    - 仅检查当前优化状态"
    echo "  $0           - 默认执行安装操作"
}

# 显示当前系统优化状态
show_optimization_status() {
    local bbr_enabled=false
    local config_exists=false
    local modules_loaded=false
    local current_bbr=""
    local current_qdisc=""
    
    log_info "检查当前系统优化状态..."
    echo "======================================"
    
    # 检查 BBR 是否已启用
    if command -v sysctl &> /dev/null; then
        current_bbr=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "未知")
        current_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "未知")
        
        if [[ "$current_bbr" == "bbr" ]]; then
            bbr_enabled=true
            log_success "BBR 拥塞控制算法: $current_bbr (已启用)"
        else
            log_warn "BBR 拥塞控制算法: $current_bbr (未启用)"
        fi
        
        if [[ "$current_qdisc" == "fq" ]]; then
            log_success "默认队列调度算法: $current_qdisc (已优化)"
        else
            log_warn "默认队列调度算法: $current_qdisc (未优化)"
        fi
    else
        log_error "无法检查系统参数"
    fi
    
    # 检查配置文件是否存在
    if [[ -f "$CONF_FILE" ]]; then
        config_exists=true
        if grep -q "MosDNS 系统优化配置" "$CONF_FILE" 2>/dev/null; then
            log_success "系统配置文件: 已安装 (本脚本创建)"
        else
            log_warn "系统配置文件: 存在但非本脚本创建"
        fi
    else
        log_warn "系统配置文件: 未安装"
    fi
    
    # 检查内核模块是否已加载
    local loaded_modules=$(lsmod | grep -E 'tcp_bbr|sch_fq' 2>/dev/null || echo "")
    if [[ -n "$loaded_modules" ]]; then
        modules_loaded=true
        log_success "内核模块: 已加载"
        echo "$loaded_modules" | while read -r line; do
            [[ -n "$line" ]] && echo "  • $line"
        done
    else
        log_warn "内核模块: 未加载"
    fi
    
    # 检查模块配置文件
    if [[ -f "$MODULES_FILE" ]]; then
        log_success "模块自动加载配置: 已设置"
    else
        log_warn "模块自动加载配置: 未设置"
    fi
    
    echo "======================================"
    
    # 显示优化状态
    if [[ "$bbr_enabled" == true ]] && [[ "$config_exists" == true ]] && [[ "$modules_loaded" == true ]]; then
        log_success "系统优化状态: 已完全优化"
    elif [[ "$bbr_enabled" == true ]] || [[ "$config_exists" == true ]] || [[ "$modules_loaded" == true ]]; then
        log_warn "系统优化状态: 部分优化"
    else
        log_warn "系统优化状态: 未优化"
    fi
    
    # 始终返回成功，避免 set -e 导致脚本退出
    return 0
}

# 检测是否已经安装了优化配置（用于安装前确认）
check_existing_optimization() {
    local bbr_enabled=false
    local config_exists=false
    local modules_loaded=false
    
    # 检查 BBR 是否已启用
    if command -v sysctl &> /dev/null; then
        local current_bbr=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "")
        if [[ "$current_bbr" == "bbr" ]]; then
            bbr_enabled=true
        fi
    fi
    
    # 检查配置文件是否存在
    if [[ -f "$CONF_FILE" ]]; then
        config_exists=true
    fi
    
    # 检查内核模块是否已加载
    if lsmod | grep -q "tcp_bbr\|sch_fq"; then
        modules_loaded=true
    fi
    
    # 如果检测到已有优化配置，询问用户是否覆盖
    if [[ "$bbr_enabled" == true ]] || [[ "$config_exists" == true ]] || [[ "$modules_loaded" == true ]]; then
        log_warn "检测到系统已存在优化配置："
        [[ "$bbr_enabled" == true ]] && echo "  • BBR 拥塞控制算法已启用"
        [[ "$config_exists" == true ]] && echo "  • 系统配置文件已存在: $CONF_FILE"
        [[ "$modules_loaded" == true ]] && echo "  • 相关内核模块已加载"
        echo
        read -p "是否要覆盖现有配置？(y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "操作已取消"
            exit 0
        fi
        log_info "将覆盖现有配置，继续执行..."
    fi
}

# 卸载优化配置
uninstall_optimization() {
    log_info "开始卸载 MosDNS RON 系统优化配置..."
    echo "======================================"
    
    local removed_something=false
    sleep 1
    log_info "[1/4] 检查并移除系统配置文件..."
    if [[ -f "$CONF_FILE" ]]; then
        # 检查是否是我们的配置文件
        if grep -q "MosDNS 系统优化配置" "$CONF_FILE" 2>/dev/null; then
            rm -f "$CONF_FILE"
            log_success "已移除配置文件: $CONF_FILE"
            removed_something=true
        else
            log_warn "配置文件存在但不是本脚本创建的，跳过删除: $CONF_FILE"
        fi
    else
        log_info "配置文件不存在，跳过"
    fi
    
    log_info "[2/4] 检查并移除内核模块配置..."
    if [[ -f "$MODULES_FILE" ]]; then
        rm -f "$MODULES_FILE"
        log_success "已移除模块配置文件: $MODULES_FILE"
        removed_something=true
    else
        log_info "模块配置文件不存在，跳过"
    fi
    sleep 1
    log_info "[3/4] 恢复默认系统参数..."
    if [[ "$removed_something" == true ]]; then
        if sysctl --system; then
            log_success "系统参数已重新加载"
        else
            log_warn "系统参数重新加载失败，可能需要手动处理"
        fi
        
        # 尝试卸载内核模块（可选，因为模块可能被其他进程使用）
        log_info "尝试卸载内核模块..."
        if modprobe -r tcp_bbr 2>/dev/null; then
            log_success "tcp_bbr 模块已卸载"
        else
            log_warn "tcp_bbr 模块卸载失败或仍在使用中"
        fi
        
        if modprobe -r sch_fq 2>/dev/null; then
            log_success "sch_fq 模块已卸载"
        else
            log_warn "sch_fq 模块卸载失败或仍在使用中"
        fi
    fi
    sleep 1
    log_info "[4/4] 卸载完成"
    echo "======================================"
    
    if [[ "$removed_something" == true ]]; then
        log_success "系统优化配置已成功卸载"
        log_warn "建议重启系统以完全恢复默认设置"
        echo
        read -p "是否现在重启系统？(y/N): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "正在重启系统..."
            reboot
        else
            log_info "请稍后手动重启系统: sudo reboot"
        fi
    else
        log_info "未发现需要卸载的优化配置"
    fi
}

# 安装优化配置
install_optimization() {
    # 执行检测
    check_existing_optimization
    sleep 1
    log_info "[1/7] 创建系统配置文件 ${CONF_FILE} ..."
    if ! install -d "${CONF_DIR}"; then
        log_error "无法创建目录 ${CONF_DIR}"
        exit 1
    fi
    if ! cat > "${CONF_FILE}" <<'EOF'; then

kernel.hardlockup_panic = 0  
kernel.nmi_watchdog = 0  
kernel.sched_autogroup_enabled = 0  
kernel.split_lock_mitigate = 1  
kernel.sysrq = 0  
kernel.task_delayacct = 0  
kernel.timer_migration = 0  
kernel.watchdog = 1  
net.core.default_qdisc = fq
net.core.netdev_budget = 600  
net.core.netdev_budget_usecs = 8000  
net.core.netdev_max_backlog = 4096  
net.core.optmem_max = 262144  
net.core.rmem_default = 131072  
net.core.rmem_max = 1048576  
net.core.wmem_default = 131072  
net.core.wmem_max = 1048576  
net.ipv4.conf.all.accept_redirects = 0  
net.ipv4.conf.all.rp_filter = 0  
net.ipv4.conf.default.accept_redirects = 0  
net.ipv4.conf.default.rp_filter = 0  
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_dsack = 1 
net.ipv4.tcp_ecn = 2  
net.ipv4.tcp_ecn_fallback = 1  
net.ipv4.tcp_low_latency = 1  
net.ipv4.tcp_min_snd_mss = 1024  
net.ipv4.tcp_mtu_probing = 1  
net.ipv4.tcp_rmem = 4096 131072 1048576   
net.ipv4.tcp_syncookies = 0  
net.ipv4.tcp_wmem = 4096 65536 1048576  
net.ipv4.udp_mem = 65536 131072 262144  
net.ipv4.udp_rmem_min = 131072  
net.ipv4.udp_wmem_min = 131072  
net.ipv6.conf.all.accept_ra = 0  
net.ipv6.conf.all.accept_redirects = 0  
net.ipv6.conf.default.accept_ra = 0  
net.ipv6.conf.default.accept_redirects = 0  
vm.compaction_proactiveness = 0  
vm.dirty_background_ratio = 2  
vm.dirty_expire_centisecs = 500  
vm.dirty_ratio = 10  
vm.dirty_writeback_centisecs = 100  
vm.page-cluster = 0  
vm.swappiness = 0  
EOF
    log_error "无法写入配置文件 ${CONF_FILE}"
    exit 1
fi

# 清理可能的回车符
sed -i 's/\r$//' "${CONF_FILE}"
log_success "系统配置文件创建完成"
sleep 1
log_info "[2/7] 加载内核模块 (tcp_bbr, sch_fq) ..."
module_loaded=true
if ! modprobe tcp_bbr; then
    log_warn "无法加载 tcp_bbr 模块，BBR 可能不可用"
    module_loaded=false
fi

if ! modprobe sch_fq; then
    log_warn "无法加载 sch_fq 模块，队列调度可能不可用"
    module_loaded=false
fi

if [[ "$module_loaded" == "true" ]]; then
    # 创建模块自动加载配置
    if ! echo -e "tcp_bbr\nsch_fq" > /etc/modules-load.d/bbr-fq.conf; then
        log_warn "无法创建模块自动加载配置"
    else
        log_success "内核模块加载完成"
    fi
else
    log_warn "部分内核模块加载失败，系统可能不支持所有优化功能"
fi
sleep 1
log_info "[3/7] 备份并处理现有的 /etc/sysctl.conf ..."
if [[ -f /etc/sysctl.conf ]]; then
    ts="$(date +%Y%m%d-%H%M%S)"
    if cp -a /etc/sysctl.conf "/etc/sysctl.conf.bak-${ts}"; then
        rm -f /etc/sysctl.conf
        log_success "已备份到 /etc/sysctl.conf.bak-${ts} 并删除原文件"
    else
        log_error "无法备份 /etc/sysctl.conf"
        exit 1
    fi
else
    log_info "未发现 /etc/sysctl.conf 文件，跳过备份"
fi
sleep 1
log_info "[4/7] 应用系统参数配置 ..."
if sysctl --system; then
    log_success "系统参数配置应用成功"
else
    log_error "系统参数配置应用失败"
    exit 1
fi
sleep 1
log_info "[5/7] 验证配置结果 ..."
echo "======================================"
sleep 1
# 验证 BBR
if bbr_status=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null); then
    if [[ "$bbr_status" == "bbr" ]]; then
        log_success "BBR 拥塞控制算法: $bbr_status"
    else
        log_warn "BBR 拥塞控制算法: $bbr_status (未启用)"
    fi
else
    log_error "无法检查 BBR 状态"
fi
sleep 1
# 验证队列调度
if qdisc_status=$(sysctl -n net.core.default_qdisc 2>/dev/null); then
    if [[ "$qdisc_status" == "fq" ]]; then
        log_success "默认队列调度算法: $qdisc_status"
    else
        log_warn "默认队列调度算法: $qdisc_status (建议使用 fq)"
    fi
else
    log_warn "无法检查队列调度算法状态"
fi
sleep 1
# 验证模块加载
loaded_modules=$(lsmod | grep -E 'tcp_bbr|sch_fq' || true)
if [[ -n "$loaded_modules" ]]; then
    log_success "已加载的相关内核模块:"
    echo "$loaded_modules"
else
    log_warn "未检测到相关内核模块"
fi
sleep 1
echo "======================================"

log_info "[6/7] 配置完成！"
sleep 1
# 询问是否重启
log_info "[7/7] 系统重启确认"
log_warn "为了使所有配置生效，建议重启系统"
read -p "是否现在重启系统？(y/N): " -r
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "正在重启系统..."
    reboot
else
    log_info "跳过重启，请稍后手动重启以使配置完全生效"
    log_info "可以运行 'reboot' 来重启系统"
fi
}

# 主函数 - 根据命令行参数执行相应操作
main() {
    # 首先显示当前系统优化状态
    show_optimization_status
    echo
    
    local operation="${1:-install}"
    log_info "执行操作: $operation"
    
    case "$operation" in
        "install")
            log_info "开始 MosDNS RON 系统优化配置..."
            echo "======================================"
            install_optimization
            ;;
        "uninstall")
            uninstall_optimization
            ;;
        "status")
            # 仅显示状态，不执行其他操作
            log_info "状态检查完成"
            ;;
        "help"|"-h"|"--help")
            show_usage
            ;;
        *)
            log_error "无效的参数: $1"
            echo
            show_usage
            exit 1
            ;;
    esac
    
    log_info "脚本执行完成"
}

# 脚本入口
main "$@"
