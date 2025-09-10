package main

import (
	"fmt"
	"os"
	"strconv"

	"github.com/herozmy/StoreHouse/mybox/internal/api"
	"github.com/herozmy/StoreHouse/mybox/internal/config"
	"github.com/herozmy/StoreHouse/mybox/internal/monitor"
	"github.com/herozmy/StoreHouse/mybox/internal/service"
	"github.com/herozmy/StoreHouse/mybox/internal/utils"
)

// 版本信息
var (
	Version   = "1.1.0"
	BuildTime = "unknown"
	GitCommit = "unknown"
)

func main() {
	// 检查root权限
	if !utils.IsRoot() {
		fmt.Fprintf(os.Stderr, "错误: 请使用root权限运行此程序\n")
		fmt.Fprintf(os.Stderr, "请执行: sudo %s\n", os.Args[0])
		os.Exit(1)
	}

	// 初始化日志
	if err := utils.InitLogger(); err != nil {
		fmt.Fprintf(os.Stderr, "初始化日志失败: %v\n", err)
		os.Exit(1)
	}

	// 初始化配置（使用嵌入的配置）
	if err := config.InitConfig(""); err != nil {
		utils.Logger.Fatalf("初始化配置失败: %v", err)
	}

	// 解析命令行参数
	switch len(os.Args) {
	case 1:
		// 无参数，默认启动Web服务器
		startWebServer(8080)
	case 2:
		switch os.Args[1] {
		case "version", "-v", "--version":
			showVersion()
		case "help", "-h", "--help":
			showHelp()
		case "status":
			showStatus()
		case "server":
			startWebServer(8080)
		case "monitor":
			startMonitor()
		default:
			fmt.Printf("未知命令: %s\n", os.Args[1])
			showHelp()
			os.Exit(1)
		}
	case 3:
		if os.Args[1] == "start" {
			startService(os.Args[2])
		} else if os.Args[1] == "stop" {
			stopService(os.Args[2])
		} else if os.Args[1] == "restart" {
			restartService(os.Args[2])
		} else {
			fmt.Printf("未知命令: %s %s\n", os.Args[1], os.Args[2])
			showHelp()
			os.Exit(1)
		}
	case 4:
		if os.Args[1] == "server" && os.Args[2] == "--port" {
			if port, err := strconv.Atoi(os.Args[3]); err == nil {
				startWebServer(port)
			} else {
				fmt.Printf("无效端口: %s\n", os.Args[3])
				os.Exit(1)
			}
		} else {
			fmt.Printf("未知命令组合\n")
			showHelp()
			os.Exit(1)
		}
	default:
		showHelp()
		os.Exit(1)
	}
}

func showVersion() {
	fmt.Printf("MyBox v%s\n", Version)
	fmt.Printf("构建时间: %s\n", BuildTime)
	fmt.Printf("Git提交: %s\n", GitCommit)
	fmt.Printf("功能特性: Web界面 + 配置管理 + 服务控制\n")
}

func showHelp() {
	fmt.Printf(`MyBox - 代理服务控制中心 (嵌入版本)

用法: %s [命令] [选项]

命令:
  (无参数)           启动Web服务器 (端口8080)
  server             启动Web服务器 (端口8080)
  server --port N    启动Web服务器 (指定端口)
  status             显示服务状态
  start <service>    启动服务 (sing-box, mosdns)
  stop <service>     停止服务
  restart <service>  重启服务
  monitor            监控模式
  version            显示版本信息
  help               显示帮助信息

特性:
  ✅ 内嵌Web界面 - 无需外部文件
  ✅ 内嵌配置 - 自动使用优化配置
  ✅ 固定路径 - 适配StoreHouse项目

示例:
  %s                    # 启动Web服务器
  %s server --port 8081 # 指定端口启动
  %s status             # 查看服务状态
  %s start sing-box     # 启动sing-box服务

Web界面: http://your-ip:8080

`, os.Args[0], os.Args[0], os.Args[0], os.Args[0], os.Args[0])
}

func showStatus() {
	sm := service.NewManager()
	services := []string{"sing-box", "mosdns"}
	
	fmt.Println("=== 服务状态 ===")
	for _, serviceName := range services {
		status := sm.GetServiceStatus(serviceName)
		statusText := formatStatus(status)
		fmt.Printf("%-12s %s\n", serviceName+":", statusText)
	}
}

func formatStatus(status service.ServiceStatus) string {
	switch status {
	case service.StatusRunning:
		return "\033[32m[运行中]\033[0m"
	case service.StatusStopped:
		return "\033[31m[已停止]\033[0m"
	case service.StatusNotInstalled:
		return "\033[90m[未安装]\033[0m"
	case service.StatusError:
		return "\033[31m[错误]\033[0m"
	default:
		return "\033[33m[未知]\033[0m"
	}
}

func startService(serviceName string) {
	sm := service.NewManager()
	
	fmt.Printf("正在启动服务: %s\n", serviceName)
	if err := sm.StartService(serviceName); err != nil {
		fmt.Printf("启动失败: %v\n", err)
		os.Exit(1)
	}
	
	fmt.Printf("服务 %s 启动成功\n", serviceName)
}

func stopService(serviceName string) {
	sm := service.NewManager()
	
	fmt.Printf("正在停止服务: %s\n", serviceName)
	if err := sm.StopService(serviceName); err != nil {
		fmt.Printf("停止失败: %v\n", err)
		os.Exit(1)
	}
	
	fmt.Printf("服务 %s 停止成功\n", serviceName)
}

func restartService(serviceName string) {
	sm := service.NewManager()
	
	fmt.Printf("正在重启服务: %s\n", serviceName)
	if err := sm.RestartService(serviceName); err != nil {
		fmt.Printf("重启失败: %v\n", err)
		os.Exit(1)
	}
	
	fmt.Printf("服务 %s 重启成功\n", serviceName)
}

func startWebServer(port int) {
	server := api.NewServer()
	addr := fmt.Sprintf("0.0.0.0:%d", port)
	
	fmt.Printf("🚀 MyBox 嵌入版本启动\n")
	fmt.Printf("📍 Web界面: http://%s:%d\n", getLocalIP(), port)
	fmt.Printf("📋 API文档: http://%s:%d/api/health\n", getLocalIP(), port)
	fmt.Printf("🔧 按 Ctrl+C 停止服务器\n\n")
	
	if err := server.Start(addr); err != nil {
		utils.Logger.Errorf("启动服务器失败: %v", err)
		os.Exit(1)
	}
}

func startMonitor() {
	m := monitor.NewMonitor()
	if err := m.Start(); err != nil {
		utils.Logger.Errorf("启动监控失败: %v", err)
		os.Exit(1)
	}
}

func getLocalIP() string {
	if ip := utils.GetLocalIP(); ip != "127.0.0.1" {
		return ip
	}
	return "localhost"
}
