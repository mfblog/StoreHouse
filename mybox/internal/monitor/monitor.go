package monitor

import (
	"fmt"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/herozmy/StoreHouse/mybox/internal/service"
	"github.com/herozmy/StoreHouse/mybox/internal/utils"
)

// Monitor 监控器
type Monitor struct {
	serviceManager *service.Manager
	interval       time.Duration
	stopChan       chan bool
}

// NewMonitor 创建监控器
func NewMonitor() *Monitor {
	return &Monitor{
		serviceManager: service.NewManager(),
		interval:       5 * time.Second,
		stopChan:       make(chan bool),
	}
}

// Start 启动监控
func (m *Monitor) Start() error {
	utils.Logger.Info("启动监控模式...")
	
	// 设置信号处理
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
	
	// 启动监控循环
	go m.monitorLoop()
	
	// 等待退出信号
	<-sigChan
	utils.Logger.Info("收到退出信号，停止监控...")
	
	m.Stop()
	return nil
}

// Stop 停止监控
func (m *Monitor) Stop() {
	close(m.stopChan)
}

// monitorLoop 监控循环
func (m *Monitor) monitorLoop() {
	ticker := time.NewTicker(m.interval)
	defer ticker.Stop()
	
	for {
		select {
		case <-ticker.C:
			m.displayStatus()
		case <-m.stopChan:
			return
		}
	}
}

// displayStatus 显示状态信息
func (m *Monitor) displayStatus() {
	// 清屏
	fmt.Print("\033[2J\033[H")
	
	// 显示标题和时间
	fmt.Printf("=== MyBox 实时监控 ===\n")
	fmt.Printf("更新时间: %s\n\n", time.Now().Format("2006-01-02 15:04:05"))
	
	// 显示系统指标
	m.displaySystemMetrics()
	
	// 显示服务状态
	m.displayServiceStatus()
	
	fmt.Println("\n按 Ctrl+C 退出监控模式")
}

// displaySystemMetrics 显示系统指标
func (m *Monitor) displaySystemMetrics() {
	fmt.Println("=== 系统指标 ===")
	
	metrics, err := service.GetSystemMetrics()
	if err != nil {
		fmt.Printf("获取系统指标失败: %v\n", err)
		return
	}
	
	fmt.Printf("CPU使用率:    %s\n", utils.FormatPercent(metrics.CPUPercent))
	fmt.Printf("内存使用率:   %s\n", utils.FormatPercent(metrics.MemoryPercent))
	fmt.Printf("磁盘使用率:   %s\n", utils.FormatPercent(metrics.DiskPercent))
	fmt.Printf("系统负载:     %.2f\n", metrics.LoadAverage)
	fmt.Println()
}

// displayServiceStatus 显示服务状态
func (m *Monitor) displayServiceStatus() {
	fmt.Println("=== 服务状态 ===")
	
	services := []string{"sing-box", "mosdns"}
	
	// 表头
	fmt.Printf("%-12s %-10s %-8s %-12s %-10s %s\n", 
		"服务", "状态", "PID", "CPU", "内存", "启动时间")
	fmt.Println("----------------------------------------------------------------")
	
	for _, serviceName := range services {
		info, err := m.serviceManager.GetServiceInfo(serviceName)
		if err != nil {
			fmt.Printf("%-12s %-10s %s\n", serviceName, "错误", err.Error())
			continue
		}
		
		status := m.formatServiceStatus(info.Status)
		pid := "-"
		cpu := "-"
		memory := "-"
		startTime := "-"
		
		if info.Status == service.StatusRunning {
			pid = fmt.Sprintf("%d", info.PID)
			cpu = utils.FormatPercent(info.CPUPercent)
			memory = utils.FormatBytes(info.MemoryBytes)
			if !info.StartTime.IsZero() {
				startTime = info.StartTime.Format("15:04:05")
			}
		}
		
		fmt.Printf("%-12s %-10s %-8s %-12s %-10s %s\n", 
			serviceName, status, pid, cpu, memory, startTime)
	}
	fmt.Println()
}

// formatServiceStatus 格式化服务状态
func (m *Monitor) formatServiceStatus(status service.ServiceStatus) string {
	switch status {
	case service.StatusRunning:
		return utils.MakeGreen("运行中")
	case service.StatusStopped:
		return utils.MakeRed("已停止")
	case service.StatusNotInstalled:
		return utils.MakeGray("未安装")
	case service.StatusError:
		return utils.MakeRed("错误")
	default:
		return utils.MakeYellow("未知")
	}
}

// GetServiceMetrics 获取服务指标
func (m *Monitor) GetServiceMetrics(serviceName string) (*ServiceMetrics, error) {
	info, err := m.serviceManager.GetServiceInfo(serviceName)
	if err != nil {
		return nil, err
	}
	
	metrics := &ServiceMetrics{
		Name:        serviceName,
		Status:      fmt.Sprintf("%d", info.Status),
		PID:         info.PID,
		CPUPercent:  info.CPUPercent,
		MemoryBytes: info.MemoryBytes,
		StartTime:   info.StartTime,
	}
	
	return metrics, nil
}

// ServiceMetrics 服务指标
type ServiceMetrics struct {
	Name        string    `json:"name"`
	Status      string    `json:"status"`
	PID         int       `json:"pid"`
	CPUPercent  float64   `json:"cpu_percent"`
	MemoryBytes uint64    `json:"memory_bytes"`
	StartTime   time.Time `json:"start_time"`
}

// GetAllMetrics 获取所有指标
func (m *Monitor) GetAllMetrics() (*AllMetrics, error) {
	// 获取系统指标
	systemMetrics, err := service.GetSystemMetrics()
	if err != nil {
		return nil, fmt.Errorf("获取系统指标失败: %v", err)
	}
	
	// 获取服务指标
	services := []string{"sing-box", "mosdns"}
	serviceMetrics := make([]*ServiceMetrics, 0, len(services))
	
	for _, serviceName := range services {
		metrics, err := m.GetServiceMetrics(serviceName)
		if err != nil {
			utils.Logger.Warnf("获取服务 %s 指标失败: %v", serviceName, err)
			continue
		}
		serviceMetrics = append(serviceMetrics, metrics)
	}
	
	return &AllMetrics{
		Timestamp: time.Now(),
		System:    systemMetrics,
		Services:  serviceMetrics,
	}, nil
}

// AllMetrics 所有指标
type AllMetrics struct {
	Timestamp time.Time                `json:"timestamp"`
	System    *service.SystemMetrics   `json:"system"`
	Services  []*ServiceMetrics        `json:"services"`
}
