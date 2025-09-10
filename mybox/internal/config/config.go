package config

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/spf13/viper"
	"github.com/herozmy/StoreHouse/mybox/internal/embed"
	"github.com/herozmy/StoreHouse/mybox/internal/utils"
)

// Config 应用配置结构
type Config struct {
	Server   ServerConfig            `yaml:"server"`
	Logging  LoggingConfig           `yaml:"logging"`
	Services map[string]ServiceConfig `yaml:"services"`
	Monitor  MonitorConfig           `yaml:"monitor"`
	Backup   BackupConfig            `yaml:"backup"`
}

// ServerConfig 服务器配置
type ServerConfig struct {
	Host       string `yaml:"host"`
	Port       int    `yaml:"port"`
	EnableCORS bool   `yaml:"enable_cors"`
}

// LoggingConfig 日志配置
type LoggingConfig struct {
	Level      string `yaml:"level"`
	File       string `yaml:"file"`
	MaxSize    int    `yaml:"max_size"`
	MaxBackups int    `yaml:"max_backups"`
}

// ServiceConfig 服务配置
type ServiceConfig struct {
	Binary       string `yaml:"binary"`
	Config       string `yaml:"config"`
	Service      string `yaml:"service"`
	AutoRestart  bool   `yaml:"auto_restart"`
	RestartDelay int    `yaml:"restart_delay"`
	LogPath      string `yaml:"log_path"`
}

// MonitorConfig 监控配置
type MonitorConfig struct {
	Interval      string `yaml:"interval"`
	Timeout       string `yaml:"timeout"`
	EnableMetrics bool   `yaml:"enable_metrics"`
}

// BackupConfig 备份配置
type BackupConfig struct {
	Enable     bool   `yaml:"enable"`
	Directory  string `yaml:"directory"`
	MaxBackups int    `yaml:"max_backups"`
}

var globalConfig *Config

// InitConfig 初始化配置
func InitConfig(configFile string) error {
	viper.SetConfigType("yaml")
	
	// 设置默认值
	setDefaults()
	
	// 直接使用嵌入的默认配置，不尝试读取外部配置文件
	utils.Logger.Info("使用嵌入的默认配置")
	if err := loadEmbeddedConfig(); err != nil {
		utils.Logger.Warnf("加载嵌入配置失败: %v，使用内置默认值", err)
		// 不返回错误，继续使用setDefaults()设置的默认值
	}
	
	// 解析配置到结构体
	globalConfig = &Config{}
	if err := viper.Unmarshal(globalConfig); err != nil {
		utils.Logger.Warnf("解析配置失败: %v，使用基本默认配置", err)
		// 创建基本的默认配置
		globalConfig = &Config{
			Server: ServerConfig{
				Host:       viper.GetString("server.host"),
				Port:       viper.GetInt("server.port"),
				EnableCORS: viper.GetBool("server.enable_cors"),
			},
			Logging: LoggingConfig{
				Level:      viper.GetString("logging.level"),
				File:       viper.GetString("logging.file"),
				MaxSize:    viper.GetInt("logging.max_size"),
				MaxBackups: viper.GetInt("logging.max_backups"),
			},
			Services: make(map[string]ServiceConfig),
		}
	}
	
	utils.Logger.Infof("配置已加载: %s", viper.ConfigFileUsed())
	return nil
}

// setDefaults 设置默认配置值
func setDefaults() {
	// 服务器配置
	viper.SetDefault("server.host", "0.0.0.0")
	viper.SetDefault("server.port", 8080)
	viper.SetDefault("server.enable_cors", true)
	
	// 日志配置
	viper.SetDefault("logging.level", "info")
	viper.SetDefault("logging.file", "/var/log/mybox.log")
	viper.SetDefault("logging.max_size", 100)
	viper.SetDefault("logging.max_backups", 3)
	
	// 服务配置
	viper.SetDefault("services.sing-box.binary", "/usr/local/bin/sing-box")
	viper.SetDefault("services.sing-box.config", "/etc/sing-box/config.json")
	viper.SetDefault("services.sing-box.service", "sing-box")
	viper.SetDefault("services.sing-box.auto_restart", true)
	viper.SetDefault("services.sing-box.restart_delay", 30)
	viper.SetDefault("services.sing-box.log_path", "/var/log/sing-box.log")
	
	viper.SetDefault("services.mosdns.binary", "/usr/local/bin/mosdns")
	viper.SetDefault("services.mosdns.config", "/etc/mosdns/config.yaml")
	viper.SetDefault("services.mosdns.service", "mosdns")
	viper.SetDefault("services.mosdns.auto_restart", true)
	viper.SetDefault("services.mosdns.restart_delay", 30)
	viper.SetDefault("services.mosdns.log_path", "/var/log/mosdns.log")
	
	// 监控配置
	viper.SetDefault("monitor.interval", "5s")
	viper.SetDefault("monitor.timeout", "10s")
	viper.SetDefault("monitor.enable_metrics", true)
	
	// 备份配置
	viper.SetDefault("backup.enable", true)
	viper.SetDefault("backup.directory", "/var/backups/mybox")
	viper.SetDefault("backup.max_backups", 10)
}

// loadEmbeddedConfig 加载嵌入的配置
func loadEmbeddedConfig() error {
	// 使用嵌入的配置内容
	configContent, err := embed.GetDefaultConfig()
	if err != nil {
		return fmt.Errorf("获取嵌入配置失败: %v", err)
	}
	
	// 设置配置类型和内容
	viper.SetConfigType("yaml")
	
	if err := viper.ReadConfig(strings.NewReader(string(configContent))); err != nil {
		return fmt.Errorf("解析嵌入配置失败: %v", err)
	}
	
	utils.Logger.Info("已加载嵌入的默认配置")
	return nil
}

// createDefaultConfig 创建默认配置文件
func createDefaultConfig() error {
	configDir := "/etc/mybox"
	configFile := filepath.Join(configDir, "mybox.yaml")
	
	// 创建配置目录
	if err := os.MkdirAll(configDir, 0755); err != nil {
		// 如果无法创建系统目录，尝试使用当前目录
		configDir = "./configs"
		configFile = filepath.Join(configDir, "mybox.yaml")
		if err := os.MkdirAll(configDir, 0755); err != nil {
			return err
		}
	}
	
	// 创建默认配置内容
	defaultConfig := `# MyBox 配置文件

server:
  host: "0.0.0.0"
  port: 8080
  enable_cors: true

logging:
  level: "info"
  file: "/var/log/mybox.log"
  max_size: 100  # MB
  max_backups: 3

services:
  sing-box:
    binary: "/usr/local/bin/sing-box"
    config: "/etc/sing-box/config.json"
    service: "sing-box"
    auto_restart: true
    restart_delay: 30
    log_path: "/var/log/sing-box.log"
    
  mosdns:
    binary: "/usr/local/bin/mosdns"
    config: "/etc/mosdns/config.yaml"
    service: "mosdns"
    auto_restart: true
    restart_delay: 30
    log_path: "/var/log/mosdns.log"

monitor:
  interval: "5s"
  timeout: "10s"
  enable_metrics: true

backup:
  enable: true
  directory: "/var/backups/mybox"
  max_backups: 10
`
	
	// 写入配置文件
	if err := os.WriteFile(configFile, []byte(defaultConfig), 0644); err != nil {
		return err
	}
	
	// 设置viper使用新创建的配置文件
	viper.SetConfigFile(configFile)
	return viper.ReadInConfig()
}

// GetConfig 获取全局配置
func GetConfig() *Config {
	return globalConfig
}

// GetServerConfig 获取服务器配置
func GetServerConfig() ServerConfig {
	if globalConfig != nil {
		return globalConfig.Server
	}
	return ServerConfig{
		Host:       viper.GetString("server.host"),
		Port:       viper.GetInt("server.port"),
		EnableCORS: viper.GetBool("server.enable_cors"),
	}
}

// GetServiceConfig 获取指定服务配置
func GetServiceConfig(serviceName string) (ServiceConfig, error) {
	if globalConfig != nil {
		if config, exists := globalConfig.Services[serviceName]; exists {
			return config, nil
		}
	}
	
	// 从viper中获取
	key := fmt.Sprintf("services.%s", serviceName)
	if !viper.IsSet(key) {
		return ServiceConfig{}, fmt.Errorf("服务配置不存在: %s", serviceName)
	}
	
	return ServiceConfig{
		Binary:       viper.GetString(key + ".binary"),
		Config:       viper.GetString(key + ".config"),
		Service:      viper.GetString(key + ".service"),
		AutoRestart:  viper.GetBool(key + ".auto_restart"),
		RestartDelay: viper.GetInt(key + ".restart_delay"),
		LogPath:      viper.GetString(key + ".log_path"),
	}, nil
}

// UpdateServiceConfig 更新服务配置
func UpdateServiceConfig(serviceName string, config ServiceConfig) error {
	key := fmt.Sprintf("services.%s", serviceName)
	
	viper.Set(key+".binary", config.Binary)
	viper.Set(key+".config", config.Config)
	viper.Set(key+".service", config.Service)
	viper.Set(key+".auto_restart", config.AutoRestart)
	viper.Set(key+".restart_delay", config.RestartDelay)
	viper.Set(key+".log_path", config.LogPath)
	
	// 保存到文件
	return viper.WriteConfig()
}

// ValidateConfig 验证配置
func ValidateConfig() error {
	config := GetConfig()
	if config == nil {
		return fmt.Errorf("配置未初始化")
	}
	
	// 验证服务器配置
	if config.Server.Port <= 0 || config.Server.Port > 65535 {
		return fmt.Errorf("无效的服务器端口: %d", config.Server.Port)
	}
	
	// 验证服务配置
	for name, svcConfig := range config.Services {
		if svcConfig.Binary == "" {
			return fmt.Errorf("服务 %s 的二进制路径不能为空", name)
		}
		
		if svcConfig.Config == "" {
			return fmt.Errorf("服务 %s 的配置路径不能为空", name)
		}
		
		if svcConfig.RestartDelay < 0 {
			return fmt.Errorf("服务 %s 的重启延迟不能为负数", name)
		}
	}
	
	// 验证备份配置
	if config.Backup.Enable && config.Backup.Directory == "" {
		return fmt.Errorf("备份已启用但目录为空")
	}
	
	return nil
}
