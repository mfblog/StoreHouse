package service

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/herozmy/StoreHouse/mybox/internal/utils"
)

// ServiceStatus 服务状态枚举
type ServiceStatus int

const (
	StatusRunning      ServiceStatus = iota // 运行中 = 0
	StatusStopped                           // 已停止 = 1
	StatusNotInstalled                      // 未安装 = 2
	StatusError                             // 错误状态 = 3
)

// ServiceInfo 服务信息
type ServiceInfo struct {
	Name        string        // 服务名称
	Status      ServiceStatus // 运行状态
	PID         int           // 进程ID
	StartTime   time.Time     // 启动时间
	CPUPercent  float64       // CPU使用率
	MemoryBytes uint64        // 内存使用量
	ConfigPath  string        // 配置文件路径
	BinaryPath  string        // 二进制文件路径
}

// Manager 服务管理器
type Manager struct {
	services map[string]*ServiceConfig
}

// ServiceConfig 服务配置
type ServiceConfig struct {
	Name         string `yaml:"name"`
	BinaryPath   string `yaml:"binary"`
	ConfigPath   string `yaml:"config"`
	ServiceName  string `yaml:"service"`
	AutoRestart  bool   `yaml:"auto_restart"`
	RestartDelay int    `yaml:"restart_delay"`
	LogPath      string `yaml:"log_path"`
}

// NewManager 创建服务管理器
func NewManager() *Manager {
	m := &Manager{
		services: make(map[string]*ServiceConfig),
	}
	
	// 初始化默认服务配置
	m.initDefaultServices()
	
	return m
}

// initDefaultServices 初始化默认服务配置
func (m *Manager) initDefaultServices() {
	// sing-box配置 - 使用StoreHouse项目的标准路径
	m.services["sing-box"] = &ServiceConfig{
		Name:         "sing-box",
		BinaryPath:   "",  // 不依赖具体路径，使用systemd管理
		ConfigPath:   "",  // 让systemd服务文件定义配置路径
		ServiceName:  "sing-box",
		AutoRestart:  true,
		RestartDelay: 5,   // 缩短重启延迟
		LogPath:      "",  // 使用journalctl获取日志
	}
	
	// mosdns配置 - 使用StoreHouse项目的标准路径
	m.services["mosdns"] = &ServiceConfig{
		Name:         "mosdns",
		BinaryPath:   "",  // 不依赖具体路径，使用systemd管理
		ConfigPath:   "",  // 让systemd服务文件定义配置路径
		ServiceName:  "mosdns",
		AutoRestart:  true,
		RestartDelay: 5,   // 缩短重启延迟
		LogPath:      "",  // 使用journalctl获取日志
	}
}

// GetServiceStatus 获取服务状态
func (m *Manager) GetServiceStatus(serviceName string) ServiceStatus {
	utils.Logger.Debugf("获取服务 %s 的状态", serviceName)
	
	config, exists := m.services[serviceName]
	if !exists {
		utils.Logger.Debugf("服务 %s 不在配置中", serviceName)
		return StatusError
	}
	
	// 首先检查服务是否在运行
	isRunning := utils.IsServiceRunning(config.ServiceName)
	utils.Logger.Debugf("服务 %s 运行状态: %v", serviceName, isRunning)
	
	if isRunning {
		utils.Logger.Debugf("服务 %s 状态: 运行中", serviceName)
		return StatusRunning
	}
	
	// 检查服务是否在systemd中安装
	if !m.isServiceInstalled(config.ServiceName) {
		utils.Logger.Debugf("服务 %s 未安装", serviceName)
		return StatusNotInstalled
	}
	
	// 服务已安装但未运行
	utils.Logger.Debugf("服务 %s 状态: 已停止", serviceName)
	return StatusStopped
}

// isServiceInstalled 检查服务是否在systemd中安装
func (m *Manager) isServiceInstalled(serviceName string) bool {
	utils.Logger.Debugf("检查服务 %s 是否安装", serviceName)
	
	// 移除特殊处理，对所有服务都进行真实检测
	
	// 方法1: 检查systemctl list-unit-files
	output, err := utils.RunCommand("systemctl", "list-unit-files", serviceName+".service")
	utils.Logger.Debugf("list-unit-files结果: err=%v, output包含服务=%v", err, strings.Contains(output, serviceName+".service"))
	if err == nil && strings.Contains(output, serviceName+".service") {
		utils.Logger.Debugf("通过list-unit-files检测到服务 %s", serviceName)
		return true
	}
	
	// 方法2: 检查systemctl status（即使服务没有运行，如果安装了也会有状态）
	statusOutput, err := utils.RunCommand("systemctl", "status", serviceName)
	utils.Logger.Debugf("status检查结果: err=%v, output=%s", err, statusOutput)
	// 只有在有输出内容且不包含"not found"错误时才认为服务存在
	if err == nil {
		utils.Logger.Debugf("通过status检测到服务 %s", serviceName)
		return true
	}
	// 检查是否是"Unit not found"错误
	if strings.Contains(statusOutput, "Unit "+serviceName+".service could not be found") ||
	   strings.Contains(statusOutput, "could not be found") ||
	   strings.Contains(statusOutput, "not found") ||
	   statusOutput == "" {
		utils.Logger.Debugf("服务 %s 未找到", serviceName)
	} else {
		// 有错误但不是"not found"，可能是服务停止状态，说明服务存在
		utils.Logger.Debugf("通过status检测到服务 %s (stopped)", serviceName)
		return true
	}
	
	// 方法3: 检查/etc/systemd/system/或/usr/lib/systemd/system/中是否有服务文件
	servicePaths := []string{
		"/etc/systemd/system/" + serviceName + ".service",
		"/usr/lib/systemd/system/" + serviceName + ".service", 
		"/lib/systemd/system/" + serviceName + ".service",
	}
	
	for _, path := range servicePaths {
		exists := utils.FileExists(path)
		utils.Logger.Debugf("检查路径 %s: exists=%v", path, exists)
		if exists {
			utils.Logger.Debugf("通过文件路径检测到服务 %s", serviceName)
			return true
		}
	}
	
	utils.Logger.Debugf("服务 %s 未检测到安装", serviceName)
	return false
}

// GetServiceInfo 获取详细服务信息
func (m *Manager) GetServiceInfo(serviceName string) (*ServiceInfo, error) {
	config, exists := m.services[serviceName]
	if !exists {
		return nil, fmt.Errorf("未知服务: %s", serviceName)
	}
	
	info := &ServiceInfo{
		Name:       serviceName,
		Status:     m.GetServiceStatus(serviceName),
		ConfigPath: config.ConfigPath,
		BinaryPath: config.BinaryPath,
	}
	
	// 如果服务在运行，获取更多信息
	if info.Status == StatusRunning {
		if pid, err := utils.GetServicePID(config.ServiceName); err == nil {
			info.PID = pid
			
			// 获取进程资源使用情况
			if metrics, err := getProcessMetrics(pid); err == nil {
				info.CPUPercent = metrics.CPUPercent
				info.MemoryBytes = metrics.MemoryBytes
				info.StartTime = metrics.StartTime
			}
		}
	}
	
	return info, nil
}

// StartService 启动服务
func (m *Manager) StartService(serviceName string) error {
	config, exists := m.services[serviceName]
	if !exists {
		return fmt.Errorf("未知服务: %s", serviceName)
	}
	
	// 检查服务是否已经在运行
	if utils.IsServiceRunning(config.ServiceName) {
		utils.Logger.Infof("服务 %s 已在运行", serviceName)
		return nil // 已在运行不算错误
	}
	
	// 检查服务是否在systemd中安装
	if !m.isServiceInstalled(config.ServiceName) {
		return fmt.Errorf("服务未安装在systemd中: %s", serviceName)
	}
	
	// 启动systemd服务
	if err := utils.StartSystemdService(config.ServiceName); err != nil {
		return fmt.Errorf("启动服务失败: %v", err)
	}
	
	// 等待服务启动
	time.Sleep(2 * time.Second)
	
	// 验证服务是否成功启动
	if !utils.IsServiceRunning(config.ServiceName) {
		return fmt.Errorf("服务启动失败，请检查日志")
	}
	
	utils.Logger.Infof("服务 %s 启动成功", serviceName)
	return nil
}

// StopService 停止服务
func (m *Manager) StopService(serviceName string) error {
	config, exists := m.services[serviceName]
	if !exists {
		return fmt.Errorf("未知服务: %s", serviceName)
	}
	
	// 检查服务是否在运行
	if !utils.IsServiceRunning(config.ServiceName) {
		return fmt.Errorf("服务未在运行: %s", serviceName)
	}
	
	// 停止systemd服务
	if err := utils.StopSystemdService(config.ServiceName); err != nil {
		return fmt.Errorf("停止服务失败: %v", err)
	}
	
	// 等待服务停止
	time.Sleep(2 * time.Second)
	
	// 验证服务是否成功停止
	if utils.IsServiceRunning(config.ServiceName) {
		return fmt.Errorf("服务停止失败，尝试强制终止")
	}
	
	utils.Logger.Infof("服务 %s 停止成功", serviceName)
	return nil
}

// RestartService 重启服务
func (m *Manager) RestartService(serviceName string) error {
	config, exists := m.services[serviceName]
	if !exists {
		return fmt.Errorf("未知服务: %s", serviceName)
	}
	
	utils.Logger.Infof("正在重启服务: %s", serviceName)
	
	// 使用systemd重启
	if err := utils.RestartSystemdService(config.ServiceName); err != nil {
		return fmt.Errorf("重启服务失败: %v", err)
	}
	
	// 等待服务重启
	time.Sleep(time.Duration(config.RestartDelay) * time.Second)
	
	// 验证服务是否成功重启
	if !utils.IsServiceRunning(config.ServiceName) {
		return fmt.Errorf("服务重启失败，请检查日志")
	}
	
	utils.Logger.Infof("服务 %s 重启成功", serviceName)
	return nil
}

// EnableService 启用服务开机自启
func (m *Manager) EnableService(serviceName string) error {
	config, exists := m.services[serviceName]
	if !exists {
		return fmt.Errorf("未知服务: %s", serviceName)
	}
	
	if err := utils.EnableSystemdService(config.ServiceName); err != nil {
		return fmt.Errorf("启用服务开机自启失败: %v", err)
	}
	
	utils.Logger.Infof("服务 %s 开机自启已启用", serviceName)
	return nil
}

// DisableService 禁用服务开机自启
func (m *Manager) DisableService(serviceName string) error {
	config, exists := m.services[serviceName]
	if !exists {
		return fmt.Errorf("未知服务: %s", serviceName)
	}
	
	if err := utils.DisableSystemdService(config.ServiceName); err != nil {
		return fmt.Errorf("禁用服务开机自启失败: %v", err)
	}
	
	utils.Logger.Infof("服务 %s 开机自启已禁用", serviceName)
	return nil
}

// GetLogs 获取服务日志
func (m *Manager) GetLogs(serviceName string, lines int) ([]string, error) {
	config, exists := m.services[serviceName]
	if !exists {
		return nil, fmt.Errorf("未知服务: %s", serviceName)
	}
	
	// 使用journalctl获取systemd服务日志
	output, err := utils.RunCommand("journalctl", "-u", config.ServiceName, "-n", fmt.Sprintf("%d", lines), "--no-pager")
	if err != nil {
		return nil, fmt.Errorf("获取服务日志失败: %v", err)
	}
	
	linesSlice := strings.Split(output, "\n")
	return linesSlice, nil
}

// TailLogs 实时跟踪服务日志
func (m *Manager) TailLogs(serviceName string, lines int) error {
	config, exists := m.services[serviceName]
	if !exists {
		return fmt.Errorf("未知服务: %s", serviceName)
	}
	
	// 使用journalctl实时跟踪日志
	cmd := exec.Command("journalctl", "-u", config.ServiceName, "-f", "-n", fmt.Sprintf("%d", lines))
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	
	return cmd.Run()
}

// GetAllServicesStatus 获取所有服务状态
func (m *Manager) GetAllServicesStatus() map[string]ServiceStatus {
	status := make(map[string]ServiceStatus)
	
	for name := range m.services {
		status[name] = m.GetServiceStatus(name)
	}
	
	return status
}

// ValidateService 验证服务配置
func (m *Manager) ValidateService(serviceName string) error {
	config, exists := m.services[serviceName]
	if !exists {
		return fmt.Errorf("未知服务: %s", serviceName)
	}
	
	// 检查服务是否在systemd中安装
	if !m.isServiceInstalled(config.ServiceName) {
		return fmt.Errorf("服务未安装在systemd中: %s", serviceName)
	}
	
	// 检查配置文件（如果指定了路径）
	if config.ConfigPath != "" && !utils.FileExists(config.ConfigPath) {
		return fmt.Errorf("配置文件不存在: %s", config.ConfigPath)
	}
	
	// 调用具体服务的配置验证
	switch serviceName {
	case "sing-box":
		return m.validateSingBoxConfig(config.ConfigPath)
	case "mosdns":
		return m.validateMosDNSConfig(config.ConfigPath)
	default:
		return fmt.Errorf("不支持的服务: %s", serviceName)
	}
}

// validateSingBoxConfig 验证sing-box配置
func (m *Manager) validateSingBoxConfig(configPath string) error {
	if configPath == "" {
		return nil // 没有配置文件路径，跳过验证
	}
	
	// 尝试使用系统路径中的sing-box验证配置
	_, err := utils.RunCommand("sing-box", "check", "-c", configPath)
	return err
}

// validateMosDNSConfig 验证mosdns配置
func (m *Manager) validateMosDNSConfig(configPath string) error {
	// 检查YAML格式
	if _, err := os.ReadFile(configPath); err != nil {
		return fmt.Errorf("无法读取配置文件: %v", err)
	}
	
	// 可以添加更多的配置验证逻辑
	return nil
}
