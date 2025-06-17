#!/bin/bash
# 脚本在遇到任何命令失败时立即退出
set -e

nft flush ruleset

# 创建 'proxy' 表
nft add table inet proxy

# 创建所有的链 (包括基础链和钩子链)
nft add chain inet proxy nat-prerouting { type nat hook prerouting priority dstnat \; policy accept \; }
nft add chain inet proxy nat-output { type nat hook output priority filter \; policy accept \; }
nft add chain inet proxy mangle-output { type route hook output priority mangle \; policy accept \; }
nft add chain inet proxy mangle-prerouting { type filter hook prerouting priority mangle \; policy accept \; }
# 创建没有 hook 的基础链
nft add chain inet proxy proxy-tproxy
nft add chain inet proxy proxy-mark

# 创建集合定义
nft add set inet proxy local_ipv4 { type ipv4_addr\; flags interval\; }
nft add set inet proxy local_ipv6 { type ipv6_addr\; flags interval\; }
nft add set inet proxy dns_ipv4 { type ipv4_addr\; }
nft add set inet proxy dns_ipv6 { type ipv6_addr\; }
nft add set inet proxy fake_ipv4 { type ipv4_addr\; flags interval\; }
nft add set inet proxy fake_ipv6 { type ipv6_addr\; flags interval\; }

# 向集合中添加元素
nft add element inet proxy local_ipv4 { 10.0.0.0/8, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16, 240.0.0.0/4 }
nft add element inet proxy local_ipv6 { ::ffff:0.0.0.0/96, 64:ff9b::/96, 100::/64, 2001::/32, 2001:10::/28, 2001:20::/28, 2001:db8::/32, 2002::/16, fc00::/7, fe80::/10 }
nft add element inet proxy dns_ipv4 { 8.8.8.8, 8.8.4.4, 1.1.1.1, 1.0.0.1 }
nft add element inet proxy dns_ipv6 { 2001:4860:4860::8888, 2001:4860:4860::8844, 2606:4700:4700::1111, 2606:4700:4700::1001 }
nft add element inet proxy fake_ipv4 { 28.0.0.0/8 }
nft add element inet proxy fake_ipv6 { f2b0::/18 }


# Rules for: nat-prerouting
nft add rule inet proxy nat-prerouting fib daddr type { unspec, local, anycast, multicast } return
nft add rule inet proxy nat-prerouting ip daddr @local_ipv4 return
nft add rule inet proxy nat-prerouting ip6 daddr @local_ipv6 return
nft add rule inet proxy nat-prerouting udp dport 123 return
nft add rule inet proxy nat-prerouting ip daddr @dns_ipv4 meta l4proto tcp redirect to :7877
nft add rule inet proxy nat-prerouting ip6 daddr @dns_ipv6 meta l4proto tcp redirect to :7877
nft add rule inet proxy nat-prerouting iifname { lo, eth0 } meta l4proto tcp redirect to :7877

# Rules for: nat-output
nft add rule inet proxy nat-output fib daddr type { unspec, local, anycast, multicast } return
nft add rule inet proxy nat-output ip daddr @fake_ipv4 meta l4proto tcp redirect to :7877
nft add rule inet proxy nat-output ip6 daddr @fake_ipv6 meta l4proto tcp redirect to :7877

# Rules for: proxy-tproxy
nft add rule inet proxy proxy-tproxy fib daddr type { unspec, local, anycast, multicast } return
nft add rule inet proxy proxy-tproxy ip daddr @local_ipv4 return
nft add rule inet proxy proxy-tproxy ip6 daddr @local_ipv6 return
nft add rule inet proxy proxy-tproxy udp dport 123 return
nft add rule inet proxy proxy-tproxy meta l4proto udp meta mark set 1 tproxy to :7896 accept

# Rules for: proxy-mark
nft add rule inet proxy proxy-mark fib daddr type { unspec, local, anycast, multicast } return
nft add rule inet proxy proxy-mark ip daddr @local_ipv4 return
nft add rule inet proxy proxy-mark ip6 daddr @local_ipv6 return
nft add rule inet proxy proxy-mark udp dport 123 return
nft add rule inet proxy proxy-mark meta mark set 1

# Rules for: mangle-output
nft add rule inet proxy mangle-output meta l4proto udp skgid != 1 ct direction original goto proxy-mark

# Rules for: mangle-prerouting
nft add rule inet proxy mangle-prerouting ip daddr @dns_ipv4 meta l4proto udp ct direction original goto proxy-tproxy
nft add rule inet proxy mangle-prerouting ip6 daddr @dns_ipv6 meta l4proto udp ct direction original goto proxy-tproxy
nft add rule inet proxy mangle-prerouting iifname { lo, eth0 } meta l4proto udp ct direction original goto proxy-tproxy

