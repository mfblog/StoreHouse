#!/usr/bin/env bash
#
# MyBox 多平台构建脚本
#

set -e

# 检查bash版本
if [[ ${BASH_VERSION%%.*} -lt 4 ]]; then
    echo "警告: 检测到bash版本 $BASH_VERSION，某些功能可能不可用"
    echo "建议升级到bash 4.0以上版本以获得最佳体验"
fi

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# 版本信息
VERSION=${VERSION:-"1.0.3"}
BUILD_TIME=$(date '+%Y-%m-%d %H:%M:%S')
GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

# 支持的平台架构（仅Linux）
SUPPORTED_PLATFORMS="linux-amd64 linux-arm64"

# 默认构建的平台（生产环境主要平台）
DEFAULT_PLATFORMS="linux-amd64 linux-arm64"

# 检查平台是否支持
is_platform_supported() {
    local platform="$1"
    case " $SUPPORTED_PLATFORMS " in
        *" $platform "*) return 0 ;;
        *) return 1 ;;
    esac
}

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_build() {
    echo -e "${BLUE}[BUILD]${NC} $1"
}

# 获取文件大小
get_file_size() {
    if [[ -f "$1" ]]; then
        if command -v numfmt >/dev/null 2>&1; then
            local bytes=$(stat -c%s "$1" 2>/dev/null || stat -f%z "$1" 2>/dev/null)
            numfmt --to=iec-i --suffix=B $bytes 2>/dev/null || du -h "$1" | cut -f1
        else
            du -h "$1" | cut -f1
        fi
    else
        echo "N/A"
    fi
}

# 清理构建目录
clean() {
    log_info "清理构建目录..."
    mkdir -p build/releases
}

# 完全清理（包括发布包）
clean_all() {
    log_info "完全清理构建目录..."
    rm -rf build/releases/
    mkdir -p build/releases
}

# 构建单个平台并直接打包
build_platform() {
    local platform="$1"
    local goos="${platform%-*}"
    local goarch="${platform#*-}"
    
    log_build "构建并打包 ${goos}/${goarch}..."
    
    local binary_name="mybox"
    
    # 创建临时目录
    local temp_dir="/tmp/mybox-build-$$-${platform}"
    mkdir -p "$temp_dir"
    
    # 直接构建到临时目录
    local output_path="$temp_dir/$binary_name"
    CGO_ENABLED=0 GOOS="$goos" GOARCH="$goarch" go build \
        -ldflags "-X 'main.Version=${VERSION}' -X 'main.BuildTime=${BUILD_TIME}' -X 'main.GitCommit=${GIT_COMMIT}' -s -w" \
        -o "$output_path" .
    
    if [[ -f "$output_path" ]]; then
        local size=$(get_file_size "$output_path")
        log_info "${platform} 构建完成: $size"
        
        # 创建压缩包
        mkdir -p build/releases
        local release_file="build/releases/mybox-${VERSION}-${platform}.tar.gz"
        tar -czf "$release_file" -C "$temp_dir" .
        
        if [[ -f "$release_file" ]]; then
            local package_size=$(get_file_size "$release_file")
            log_info "${platform} 发布包: mybox-${VERSION}-${platform}.tar.gz ($package_size)"
        fi
        
        # 清理临时目录
        rm -rf "$temp_dir"
        
        return 0
    else
        log_error "${platform} 构建失败"
        rm -rf "$temp_dir"
        return 1
    fi
}

# 构建指定的单个平台
build_single() {
    local target="$1"
    
    # 验证平台是否支持
    if ! is_platform_supported "$target"; then
        log_error "不支持的平台: $target"
        log_info "支持的平台: $SUPPORTED_PLATFORMS"
        return 1
    fi
    
    clean
    build_platform "$target"
    
    log_info "单平台构建完成！"
    ls -lah build/releases/
}

# 本地测试构建（Linux AMD64平台，输出到bin目录）
build_test() {
    local test_platform="linux-amd64"
    
    log_info "构建本地测试版本 ($test_platform)..."
    
    # 创建bin目录
    mkdir -p bin
    
    # 构建Linux AMD64平台到bin目录
    local output_path="bin/mybox-test"
    
    log_build "构建测试版本..."
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
        -ldflags "-X 'main.Version=${VERSION}-test' -X 'main.BuildTime=${BUILD_TIME}' -X 'main.GitCommit=${GIT_COMMIT}' -s -w" \
        -o "$output_path" .
    
    if [[ -f "$output_path" ]]; then
        local size=$(get_file_size "$output_path")
        log_info "测试版本构建完成: $size"
        log_info "测试文件位置: $output_path"
        
        # 测试版本验证
        if file "$output_path" | grep -q "ELF.*x86-64"; then
            log_info "测试版本验证通过 (Linux AMD64 ELF文件)"
        elif [[ -x "$output_path" ]]; then
            log_info "测试版本文件验证通过 (可执行文件)"
        else
            log_warn "测试版本验证失败"
        fi
        
        return 0
    else
        log_error "测试版本构建失败"
        return 1
    fi
}

# 构建多个平台
build_multi() {
    local platforms_str="$*"
    
    if [[ -z "$platforms_str" ]]; then
        platforms_str="$DEFAULT_PLATFORMS"
        log_info "使用默认平台: $platforms_str"
    fi
    
    clean
    
    local success_count=0
    local total_count=0
    
    for platform in $platforms_str; do
        ((total_count++))
        if is_platform_supported "$platform"; then
            if build_platform "$platform"; then
                ((success_count++))
            fi
        else
            log_warn "跳过不支持的平台: $platform"
        fi
    done
    
    log_info "多平台构建完成: $success_count/$total_count 成功"
}

# 构建所有支持的平台
build_all_platforms() {
    log_info "构建所有支持的平台..."
    build_multi $SUPPORTED_PLATFORMS
}


# 验证构建结果
test_build() {
    log_info "验证发布包..."
    
    local test_passed=0
    local test_total=0
    
    if [[ -d "build/releases" ]]; then
        for release_file in build/releases/*.tar.gz; do
            if [[ -f "$release_file" ]]; then
                ((test_total++))
                local filename=$(basename "$release_file")
                
                # 检查文件大小
                local size=$(get_file_size "$release_file")
                if [[ "$size" != "N/A" ]]; then
                    log_info "发布包 $filename: $size"
                    ((test_passed++))
                else
                    log_warn "发布包 $filename: 大小异常"
                fi
            fi
        done
    fi
    
    if [[ $test_total -eq 0 ]]; then
        log_warn "没有找到发布包"
    else
        log_info "发布包验证完成: $test_passed/$test_total"
    fi
}

# 显示帮助
show_help() {
    echo "MyBox 多平台构建脚本"
    echo ""
    echo "用法: $0 [命令] [选项]"
    echo ""
    echo "命令:"
    echo "  all                    构建默认平台 (linux-amd64, linux-arm64)"
    echo "  build [platforms...]   构建指定平台"
    echo "  build-all             构建所有Linux平台"
    echo "  single <platform>     构建单个平台"
    echo "  test                  本地测试构建 (Linux AMD64，输出到bin/)"
    echo "  verify                验证构建结果"
    echo "  clean                 清理构建目录 (保留发布包)"
    echo "  clean-all             完全清理 (包括发布包)"
    echo "  list                  列出支持的平台"
    echo "  help                  显示帮助"
    echo ""
    echo "支持的Linux平台:"
    for platform in $SUPPORTED_PLATFORMS; do
        echo "  $platform"
    done
    echo ""
    echo "环境变量:"
    echo "  VERSION      设置版本号 (默认: 1.0.2)"
    echo ""
    echo "示例:"
    echo "  $0                                    # 构建默认平台"
    echo "  $0 test                              # 本地测试构建"
    echo "  $0 single linux-amd64               # 构建Linux AMD64"
    echo "  $0 build linux-amd64 linux-arm64    # 构建指定平台"
    echo "  $0 build-all                        # 构建所有平台"
    echo "  VERSION=1.1.0 $0 all               # 指定版本构建"
    echo ""
    echo "默认平台: $DEFAULT_PLATFORMS"
}

# 列出支持的平台
list_platforms() {
    echo "支持的Linux平台架构:"
    echo ""
    printf "%-15s %-10s %-10s\n" "平台" "操作系统" "架构"
    echo "----------------------------------------"
    for platform in $SUPPORTED_PLATFORMS; do
        local goos="${platform%-*}"
        local goarch="${platform#*-}"
        printf "%-15s %-10s %-10s\n" "$platform" "$goos" "$goarch"
    done
    echo ""
    echo "默认构建平台: $DEFAULT_PLATFORMS"
    echo "当前系统: $(go env GOOS)-$(go env GOARCH)"
}

# 完整构建流程
build_complete() {
    log_info "开始完整构建流程..."
    build_multi $DEFAULT_PLATFORMS
    test_build
    
    log_info "构建完成！"
    echo ""
    echo "📦 发布包结果:"
    if ls build/releases/*.tar.gz >/dev/null 2>&1; then
        ls -lah build/releases/
    else
        log_warn "没有找到发布包"
    fi
}

# 主函数
main() {
    local cmd="${1:-all}"
    
    case "$cmd" in
        "all")
            build_complete
            ;;
        "build")
            shift
            build_multi "$@"
            ;;
        "build-all")
            build_all_platforms
            ;;
        "single")
            if [[ -z "$2" ]]; then
                log_error "请指定平台"
                show_help
                exit 1
            fi
            build_single "$2"
            ;;
        "test")
            build_test
            ;;
        "verify")
            test_build
            ;;
        "clean")
            clean
            ;;
        "clean-all")
            clean_all
            ;;
        "list")
            list_platforms
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        # 向后兼容旧的命令
        "linux")
            log_warn "命令 'linux' 已废弃，请使用 'single linux-amd64'"
            build_single "linux-amd64"
            ;;
        "current")
            local current_platform="$(go env GOOS)-$(go env GOARCH)"
            log_info "构建当前平台: $current_platform"
            build_single "$current_platform"
            ;;
        *)
            log_error "未知命令: $cmd"
            show_help
            exit 1
            ;;
    esac
}

# 检查Go环境
if ! command -v go >/dev/null 2>&1; then
    log_error "未找到Go环境，请先安装Go"
    exit 1
fi

# 显示构建信息
log_info "MyBox 构建脚本 v2.0"
log_info "版本: $VERSION"
log_info "构建时间: $BUILD_TIME"
log_info "Git提交: $GIT_COMMIT"
log_info "Go版本: $(go version | cut -d' ' -f3)"
echo ""

# 执行主函数
main "$@"