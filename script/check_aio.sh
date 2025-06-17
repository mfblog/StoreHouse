#!/bin/bash
# --- 变量与常量定义 ---
readonly green_text="\033[32m"
readonly yellow_text="\033[33m"
readonly red_text="\033[31m"
readonly reset="\033[0m"
readonly DIRPATH="/usr/local/bin/tools"
readonly NFT_RULESET="/etc/nftables.conf"


# --- 日志函数 ---
log_info() { echo -e "${green_text}[INFO]${reset} $1"; }
log_warn() { echo -e "${yellow_text}[WARN]${reset} $1"; }
log_error() { echo -e "${red_text}[ERROR]${reset} $1"; }

# 检查 AIO 环境并调整防火墙 (最终确认版)

    log_info "正在检测 AIO 环境 (是否DNS与代理核心共存)..."
    
    local has_mosdns=false
    local has_proxy=false
    
    [ -x "/usr/local/bin/mosdns" ] && has_mosdns=true
    if [ -x "/usr/local/bin/sing-box" ] || [ -x "/usr/local/bin/mihomo" ]; then
        has_proxy=true
    fi

    log_info "MosDNS 存在: $([[ $has_mosdns == true ]] && echo "${green_text}是✓${reset}" || echo "${red_text}否✗${reset}")"
    log_info "代理核心存在: $([[ $has_proxy == true ]] && echo "${green_text}是✓${reset}" || echo "${red_text}否✗${reset}")"

    if [[ $has_mosdns == true && $has_proxy == true ]]; then
        log_warn "检测到DNS与代理核心共存，需要调整防火墙规则。"
        
        # --- 定义 IPv4 规则块 (Heredoc方式，保持格式和换行) ---
        local aio_rules_ipv4_block
        aio_rules_ipv4_block=$(cat <<'EOF'
      # BEGIN-MOSDNS-AIO-IPV4-RULES - DONT'T EDIT THIS BLOCK MANUALLY
      # Public DNS for mainland China (IPv4)
      223.5.5.5, 223.6.6.6,
      # END-MOSDNS-AIO-IPV4-RULES
EOF
        )

        # --- 定义 IPv6 规则块 ---
        local aio_rules_ipv6_block
        aio_rules_ipv6_block=$(cat <<'EOF'
      # BEGIN-MOSDNS-AIO-IPV6-RULES - DONT'T EDIT THIS BLOCK MANUALLY
      # Public DNS for mainland China (IPv6)
      2400:3200::1, 2400:3200:baba::1,
      # END-MOSDNS-AIO-IPV6-RULES
EOF
        )

        # --- 修改 nftables.conf ---
        # 1. 先安全地删除旧的规则块，防止重复
        sed -i '/# BEGIN-MOSDNS-AIO-IPV4-RULES/,/# END-MOSDNS-AIO-IPV4-RULES/d' "$NFT_RULESET"
        sed -i '/# BEGIN-MOSDNS-AIO-IPV6-RULES/,/# END-MOSDNS-AIO-IPV6-RULES/d' "$NFT_RULESET"
        
        # --- 关键改动在此：使用您提供的正确锚点 ---
        # 2. 将 IPv4 规则块插入到 `10.0.0.0/8,` 之后
        sed -i "/10.0.0.0\/8,/a ${aio_rules_ipv4_block}" "$NFT_RULESET"
        
        # 3. 将 IPv6 规则块插入到 `100::/64,` 之后
        sed -i "/100::\/64,/a ${aio_rules_ipv6_block}" "$NFT_RULESET"

        log_info "正在验证并应用新的防火墙规则..."
        if nft -c -f "$NFT_RULESET"; then
            nft flush ruleset
            nft -f "$NFT_RULESET"
            log_info "防火墙规则已生效。"
            
            if systemctl is-active --quiet "tproxy-router"; then
                log_info "检测到 tproxy-router 服务正在运行，正在重启以应用新规则..."
                systemctl restart "tproxy-router"
                log_info "tproxy-router 服务重启完成。"
            else
                log_warn "tproxy-router 服务未运行，无需重启。"
            fi
            
        else
            log_error "新的防火墙配置无效！已自动回滚更改。"
            sed -i '/# BEGIN-MOSDNS-AIO-IPV4-RULES/,/# END-MOSDNS-AIO-IPV4-RULES/d' "$NFT_RULESET"
            sed -i '/# BEGIN-MOSDNS-AIO-IPV6-RULES/,/# END-MOSDNS-AIO-IPV6-RULES/d' "$NFT_RULESET"
            exit 1
        fi
    else
        log_info "DNS与代理核心未共存，无需调整"
        : # 不共存时保持静默
    fi
