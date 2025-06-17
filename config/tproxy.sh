#!/bin/bash

set -e

nft flush ruleset

# 创建 'proxy' 表
nft add table inet proxy

nft add chain inet proxy mangle-output { type route hook output priority mangle \; policy accept \; }
nft add chain inet proxy mangle-prerouting { type filter hook prerouting priority mangle \; policy accept \; }
# 创建没有 hook 的基础链
nft add chain inet proxy proxy-tproxy
nft add chain inet proxy proxy-mark

# 创建集合定义
nft add set inet proxy local_ipv4 { type ipv4_addr\; flags interval\; }
nft add set inet proxy local_ipv6 { type ipv6_addr\; flags interval\; }

# 向集合中添加元素
nft add element inet proxy local_ipv4 { 10.0.0.0/8, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16, 240.0.0.0/4 }
nft add element inet proxy local_ipv6 { ::ffff:0.0.0.0/96, 64:ff9b::/96, 100::/64, 2001::/32, 2001:10::/28, 2001:20::/28, 2001:db8::/32, 2002::/16, fc00::/7, fe80::/10 }

# Rules for: proxy-tproxy
nft add rule inet proxy proxy-tproxy fib daddr type { unspec, local, anycast, multicast } return
nft add rule inet proxy proxy-tproxy ip daddr @local_ipv4 return
nft add rule inet proxy proxy-tproxy ip6 daddr @local_ipv6 return
nft add rule inet proxy proxy-tproxy udp dport 123 return
nft add rule inet proxy proxy-tproxy meta l4proto { tcp, udp } meta mark set 1 tproxy to :7896 accept

# Rules for: proxy-mark
nft add rule inet proxy proxy-mark fib daddr type { unspec, local, anycast, multicast } return
nft add rule inet proxy proxy-mark ip daddr @local_ipv4 return
nft add rule inet proxy proxy-mark ip6 daddr @local_ipv6 return
nft add rule inet proxy proxy-mark udp dport 123 return
nft add rule inet proxy proxy-mark meta mark set 1

# Rules for: mangle-output
nft add rule inet proxy mangle-output meta l4proto { tcp, udp } skgid != 1 ct direction original goto proxy-mark

# Rules for: mangle-prerouting
nft add rule inet proxy mangle-prerouting iifname { wg0, lo, eth0 } meta l4proto { tcp, udp } ct direction original goto proxy-tproxy

