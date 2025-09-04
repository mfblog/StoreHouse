package config

import (
	"fmt"
	"io/ioutil"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/herozmy/StoreHouse/mybox/internal/utils"
)

// Manager 配置管理器
type Manager struct {
	backupDir string
}

// NewManager 创建配置管理器
func NewManager() *Manager {
	config := GetConfig()
	backupDir := "/var/backups/mybox"
	if config != nil && config.Backup.Directory != "" {
		backupDir = config.Backup.Directory
	}
	
	return &Manager{
		backupDir: backupDir,
	}
}

// EditConfig 编辑服务配置文件
func (m *Manager) EditConfig(serviceName string) error {
	serviceConfig, err := GetServiceConfig(serviceName)
	if err != nil {
		return err
	}
	
	configPath := serviceConfig.Config
	if !utils.FileExists(configPath) {
		return fmt.Errorf("配置文件不存在: %s", configPath)
	}
	
	// 备份原配置文件
	if _, err := m.BackupConfig(serviceName); err != nil {
		utils.Logger.Warnf("备份配置失败: %v", err)
	}
	
	// 获取编辑器
	editor := os.Getenv("EDITOR")
	if editor == "" {
		// 尝试常用编辑器
		editors := []string{"nano", "vim", "vi"}
		for _, e := range editors {
			if _, err := exec.LookPath(e); err == nil {
				editor = e
				break
			}
		}
	}
	
	if editor == "" {
		return fmt.Errorf("未找到可用的编辑器，请设置EDITOR环境变量")
	}
	
	// 启动编辑器
	cmd := exec.Command(editor, configPath)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("编辑器执行失败: %v", err)
	}
	
	// 验证编辑后的配置
	if err := m.ValidateConfig(serviceName); err != nil {
		utils.Logger.Errorf("配置验证失败: %v", err)
		
		// 询问是否恢复备份
		fmt.Print("配置验证失败，是否恢复备份？(y/N): ")
		var response string
		fmt.Scanln(&response)
		
		if response == "y" || response == "Y" {
			if err := m.RestoreLatestConfig(serviceName); err != nil {
				return fmt.Errorf("恢复备份失败: %v", err)
			}
			fmt.Println("已恢复到之前的配置")
		}
		
		return fmt.Errorf("配置编辑被取消")
	}
	
	utils.Logger.Infof("服务 %s 配置编辑完成", serviceName)
	return nil
}

// ValidateConfig 验证服务配置
func (m *Manager) ValidateConfig(serviceName string) error {
	serviceConfig, err := GetServiceConfig(serviceName)
	if err != nil {
		return err
	}
	
	configPath := serviceConfig.Config
	if !utils.FileExists(configPath) {
		return fmt.Errorf("配置文件不存在: %s", configPath)
	}
	
	// 根据服务类型进行特定验证
	switch serviceName {
	case "sing-box":
		return m.validateSingBoxConfig(configPath, serviceConfig.Binary)
	case "mosdns":
		return m.validateMosDNSConfig(configPath)
	default:
		// 基本验证：检查文件是否可读
		if _, err := os.ReadFile(configPath); err != nil {
			return fmt.Errorf("无法读取配置文件: %v", err)
		}
	}
	
	return nil
}

// validateSingBoxConfig 验证sing-box配置
func (m *Manager) validateSingBoxConfig(configPath, binaryPath string) error {
	if !utils.FileExists(binaryPath) {
		return fmt.Errorf("sing-box二进制文件不存在: %s", binaryPath)
	}
	
	// 使用sing-box check命令验证配置
	cmd := exec.Command(binaryPath, "check", "-c", configPath)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("sing-box配置验证失败: %s", string(output))
	}
	
	return nil
}

// validateMosDNSConfig 验证mosdns配置
func (m *Manager) validateMosDNSConfig(configPath string) error {
	// 检查YAML格式
	content, err := os.ReadFile(configPath)
	if err != nil {
		return fmt.Errorf("无法读取配置文件: %v", err)
	}
	
	// 基本的YAML格式检查
	if len(content) == 0 {
		return fmt.Errorf("配置文件为空")
	}
	
	// 可以添加更复杂的mosdns配置验证逻辑
	// 例如检查必要的字段、插件配置等
	
	return nil
}

// BackupConfig 备份服务配置
func (m *Manager) BackupConfig(serviceName string) (string, error) {
	serviceConfig, err := GetServiceConfig(serviceName)
	if err != nil {
		return "", err
	}
	
	configPath := serviceConfig.Config
	if !utils.FileExists(configPath) {
		return "", fmt.Errorf("配置文件不存在: %s", configPath)
	}
	
	// 创建备份目录
	backupServiceDir := filepath.Join(m.backupDir, serviceName)
	if err := os.MkdirAll(backupServiceDir, 0755); err != nil {
		return "", fmt.Errorf("创建备份目录失败: %v", err)
	}
	
	// 生成备份文件名
	timestamp := time.Now().Format("20060102_150405")
	backupFileName := fmt.Sprintf("config_%s.bak", timestamp)
	backupPath := filepath.Join(backupServiceDir, backupFileName)
	
	// 复制配置文件
	if err := copyFile(configPath, backupPath); err != nil {
		return "", fmt.Errorf("备份文件失败: %v", err)
	}
	
	// 清理旧备份
	m.cleanOldBackups(backupServiceDir)
	
	utils.Logger.Infof("服务 %s 配置已备份到: %s", serviceName, backupPath)
	return backupPath, nil
}

// RestoreConfig 恢复指定备份
func (m *Manager) RestoreConfig(serviceName, backupPath string) error {
	serviceConfig, err := GetServiceConfig(serviceName)
	if err != nil {
		return err
	}
	
	if !utils.FileExists(backupPath) {
		return fmt.Errorf("备份文件不存在: %s", backupPath)
	}
	
	configPath := serviceConfig.Config
	
	// 备份当前配置
	if utils.FileExists(configPath) {
		currentBackup := configPath + ".before_restore"
		if err := copyFile(configPath, currentBackup); err != nil {
			utils.Logger.Warnf("备份当前配置失败: %v", err)
		}
	}
	
	// 恢复配置
	if err := copyFile(backupPath, configPath); err != nil {
		return fmt.Errorf("恢复配置失败: %v", err)
	}
	
	// 验证恢复的配置
	if err := m.ValidateConfig(serviceName); err != nil {
		return fmt.Errorf("恢复的配置验证失败: %v", err)
	}
	
	utils.Logger.Infof("服务 %s 配置已从 %s 恢复", serviceName, backupPath)
	return nil
}

// RestoreLatestConfig 恢复最新备份
func (m *Manager) RestoreLatestConfig(serviceName string) error {
	backupServiceDir := filepath.Join(m.backupDir, serviceName)
	
	// 查找最新备份
	files, err := filepath.Glob(filepath.Join(backupServiceDir, "config_*.bak"))
	if err != nil {
		return fmt.Errorf("查找备份文件失败: %v", err)
	}
	
	if len(files) == 0 {
		return fmt.Errorf("未找到备份文件")
	}
	
	// 找到最新的备份文件（按文件名排序，时间戳格式保证了字典序等于时间序）
	latestBackup := ""
	for _, file := range files {
		if latestBackup == "" || file > latestBackup {
			latestBackup = file
		}
	}
	
	return m.RestoreConfig(serviceName, latestBackup)
}

// ListBackups 列出备份文件
func (m *Manager) ListBackups(serviceName string) ([]string, error) {
	backupServiceDir := filepath.Join(m.backupDir, serviceName)
	
	files, err := filepath.Glob(filepath.Join(backupServiceDir, "config_*.bak"))
	if err != nil {
		return nil, fmt.Errorf("查找备份文件失败: %v", err)
	}
	
	// 按时间倒序排列（最新的在前）
	for i, j := 0, len(files)-1; i < j; i, j = i+1, j-1 {
		files[i], files[j] = files[j], files[i]
	}
	
	return files, nil
}

// cleanOldBackups 清理旧备份
func (m *Manager) cleanOldBackups(backupDir string) {
	config := GetConfig()
	maxBackups := 10
	if config != nil {
		maxBackups = config.Backup.MaxBackups
	}
	
	files, err := filepath.Glob(filepath.Join(backupDir, "config_*.bak"))
	if err != nil {
		utils.Logger.Warnf("查找备份文件失败: %v", err)
		return
	}
	
	if len(files) <= maxBackups {
		return
	}
	
	// 按文件名排序（时间戳）
	// 由于使用时间戳命名，字典序就是时间序
	for i := 0; i < len(files)-1; i++ {
		for j := i + 1; j < len(files); j++ {
			if files[i] > files[j] {
				files[i], files[j] = files[j], files[i]
			}
		}
	}
	
	// 删除最旧的备份
	for i := 0; i < len(files)-maxBackups; i++ {
		if err := os.Remove(files[i]); err != nil {
			utils.Logger.Warnf("删除旧备份失败: %v", err)
		} else {
			utils.Logger.Debugf("已删除旧备份: %s", files[i])
		}
	}
}

// copyFile 复制文件
func copyFile(src, dst string) error {
	sourceFile, err := os.Open(src)
	if err != nil {
		return err
	}
	defer sourceFile.Close()
	
	destFile, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer destFile.Close()
	
	_, err = destFile.ReadFrom(sourceFile)
	return err
}

// GetConfigContent 获取配置文件内容
func (m *Manager) GetConfigContent(serviceName string) (string, error) {
	serviceConfig, err := GetServiceConfig(serviceName)
	if err != nil {
		return "", err
	}
	
	content, err := os.ReadFile(serviceConfig.Config)
	if err != nil {
		return "", fmt.Errorf("读取配置文件失败: %v", err)
	}
	
	return string(content), nil
}

// SetConfigContent 设置配置文件内容
func (m *Manager) SetConfigContent(serviceName, content string) error {
	serviceConfig, err := GetServiceConfig(serviceName)
	if err != nil {
		return err
	}
	
	// 备份当前配置
	if _, err := m.BackupConfig(serviceName); err != nil {
		utils.Logger.Warnf("备份配置失败: %v", err)
	}
	
	// 写入新内容
	if err := os.WriteFile(serviceConfig.Config, []byte(content), 0644); err != nil {
		return fmt.Errorf("写入配置文件失败: %v", err)
	}
	
	// 验证新配置
	if err := m.ValidateConfig(serviceName); err != nil {
		// 验证失败，恢复备份
		if restoreErr := m.RestoreLatestConfig(serviceName); restoreErr != nil {
			utils.Logger.Errorf("恢复备份失败: %v", restoreErr)
		}
		return fmt.Errorf("配置验证失败: %v", err)
	}
	
	utils.Logger.Infof("服务 %s 配置已更新", serviceName)
	return nil
}

// GetSingBoxConfig 获取Sing-Box配置
func (m *Manager) GetSingBoxConfig() (map[string]interface{}, error) {
	return m.getServiceConfigParsed("sing-box")
}

// GetMosDNSConfig 获取MosDNS配置  
func (m *Manager) GetMosDNSConfig() (map[string]interface{}, error) {
	return m.getServiceConfigParsed("mosdns")
}

// getServiceConfigParsed 获取并解析服务配置文件
func (m *Manager) getServiceConfigParsed(serviceName string) (map[string]interface{}, error) {
	serviceConfig, err := GetServiceConfig(serviceName)
	if err != nil {
		return nil, fmt.Errorf("获取服务配置失败: %v", err)
	}
	
	configPath := serviceConfig.Config
	if !utils.FileExists(configPath) {
		return nil, fmt.Errorf("配置文件不存在: %s", configPath)
	}
	
	// 读取配置文件内容
	content, err := utils.ReadConfig(configPath)
	if err != nil {
		return nil, fmt.Errorf("读取配置文件失败: %v", err)
	}
	
	return content, nil
}

// ValidateConfigContent 验证配置内容
func (m *Manager) ValidateConfigContent(serviceName, configContent string) (map[string]interface{}, error) {
	serviceConfig, err := GetServiceConfig(serviceName)
	if err != nil {
		return nil, err
	}
	
	// 创建临时文件
	tempFile, err := ioutil.TempFile("", fmt.Sprintf("%s_validate_*.json", serviceName))
	if err != nil {
		return nil, fmt.Errorf("创建临时文件失败: %v", err)
	}
	defer os.Remove(tempFile.Name()) // 清理临时文件
	defer tempFile.Close()
	
	// 写入配置内容到临时文件
	if _, err := tempFile.WriteString(configContent); err != nil {
		return nil, fmt.Errorf("写入临时文件失败: %v", err)
	}
	tempFile.Close()
	
	// 根据服务类型进行验证
	switch serviceName {
	case "sing-box":
		if err := m.validateSingBoxConfig(tempFile.Name(), serviceConfig.Binary); err != nil {
			return nil, err
		}
	case "mosdns":
		if err := m.validateMosDNSConfig(tempFile.Name()); err != nil {
			return nil, err
		}
	default:
		// 基本验证：检查文件是否可读
		if _, err := os.ReadFile(tempFile.Name()); err != nil {
			return nil, fmt.Errorf("无法读取配置内容: %v", err)
		}
	}
	
	// 解析配置内容
	config, err := utils.ReadConfig(tempFile.Name())
	if err != nil {
		return nil, fmt.Errorf("解析配置内容失败: %v", err)
	}
	
	return config, nil
}

// GetMosDNSLocalDNS 获取MosDNS本地DNS配置
func (m *Manager) GetMosDNSLocalDNS() (map[string]interface{}, error) {
	// 尝试多个可能的配置文件路径
	possiblePaths := []string{
		"/cus/mosdns/sub_config/forward_local.yaml",
		"/cus/mosdns/sub_config/forward_1.yaml",
		"/cus/mosdns/config.yaml",
		"/etc/mosdns/config.yaml",
	}
	
	for _, configPath := range possiblePaths {
		utils.Logger.Debugf("尝试读取配置文件: %s", configPath)
		
		if !utils.FileExists(configPath) {
			utils.Logger.Debugf("配置文件不存在: %s", configPath)
			continue
		}
		
		// 尝试读取为数组格式
		if content, err := utils.ReadYAMLConfigAsArray(configPath); err == nil {
			utils.Logger.Debugf("成功解析 %s 为数组格式，包含 %d 个配置项", configPath, len(content))
			
			// 记录所有找到的配置项
			utils.Logger.Infof("在 %s 中找到 %d 个配置项", configPath, len(content))
			for i, item := range content {
				if config, ok := item.(map[string]interface{}); ok {
					tag := "无标签"
					configType := "无类型"
					if t, exists := config["tag"]; exists {
						tag = fmt.Sprintf("%v", t)
					}
					if ct, exists := config["type"]; exists {
						configType = fmt.Sprintf("%v", ct)
					}
					utils.Logger.Infof("配置项 %d: tag=%s, type=%s", i, tag, configType)
				}
			}
			
			// 优先查找 forward_local 配置
			for i, item := range content {
				if config, ok := item.(map[string]interface{}); ok {
					if tag, exists := config["tag"]; exists {
						tagStr := fmt.Sprintf("%v", tag)
						if tagStr == "forward_local" {
							utils.Logger.Infof("✅ 找到 forward_local 配置在 %s (索引 %d)", configPath, i)
							return config, nil
						}
					}
				}
			}
			
			// 查找包含 local 的配置
			for i, item := range content {
				if config, ok := item.(map[string]interface{}); ok {
					if tag, exists := config["tag"]; exists {
						tagStr := fmt.Sprintf("%v", tag)
						if strings.Contains(strings.ToLower(tagStr), "local") && 
						   config["type"] == "forward" {
							utils.Logger.Infof("✅ 找到包含 local 的配置: tag=%s 在 %s (索引 %d)", tagStr, configPath, i)
							return config, nil
						}
					}
				}
			}
			
			// 查找任何 forward 类型的配置（作为fallback）
			for i, item := range content {
				if config, ok := item.(map[string]interface{}); ok {
					if configType, exists := config["type"]; exists && configType == "forward" {
						if tag, exists := config["tag"]; exists {
							tagStr := fmt.Sprintf("%v", tag)
							utils.Logger.Infof("⚠️ 使用第一个 forward 配置作为本地DNS: tag=%s 在 %s (索引 %d)", tagStr, configPath, i)
							return config, nil
						}
					}
				}
			}
		} else {
			utils.Logger.Debugf("无法解析 %s 为数组格式: %v", configPath, err)
		}
		
		// 尝试读取为单个对象格式
		if config, err := utils.ReadYAMLConfig(configPath); err == nil {
			utils.Logger.Debugf("成功解析 %s 为对象格式", configPath)
			
			if tag, exists := config["tag"]; exists {
				tagStr := fmt.Sprintf("%v", tag)
				utils.Logger.Debugf("单个配置: tag=%s, type=%s", tagStr, config["type"])
				
				if tagStr == "forward_local" || 
				   (strings.Contains(strings.ToLower(tagStr), "local") && config["type"] == "forward") ||
				   config["type"] == "forward" {
					utils.Logger.Infof("使用单个配置: tag=%s 在 %s", tagStr, configPath)
					return config, nil
				}
			}
		} else {
			utils.Logger.Debugf("无法解析 %s 为对象格式: %v", configPath, err)
		}
	}
	
	return nil, fmt.Errorf("在所有可能的配置文件中都未找到合适的本地DNS配置，尝试的路径: %v", possiblePaths)
}

// UpdateMosDNSLocalDNS 更新MosDNS本地DNS配置
func (m *Manager) UpdateMosDNSLocalDNS(config map[string]interface{}) error {
	configPath := "/cus/mosdns/sub_config/forward_local.yaml"
	
	// 备份原配置
	if _, err := m.BackupConfig("mosdns"); err != nil {
		utils.Logger.Warnf("备份本地DNS配置失败: %v", err)
	}
	
	// 写入新配置
	if err := utils.WriteYAMLConfig(configPath, config); err != nil {
		return fmt.Errorf("写入本地DNS配置失败: %v", err)
	}
	
	utils.Logger.Info("MosDNS本地DNS配置更新成功")
	return nil
}

// GetMosDNSRemoteDNS 获取MosDNS远程DNS配置
func (m *Manager) GetMosDNSRemoteDNS() (map[string]interface{}, error) {
	configPath := "/cus/mosdns/sub_config/forward_1.yaml"
	
	if !utils.FileExists(configPath) {
		return nil, fmt.Errorf("远程DNS配置文件不存在: %s", configPath)
	}
	
	// 尝试读取为数组格式
	if content, err := utils.ReadYAMLConfigAsArray(configPath); err == nil {
		utils.Logger.Infof("在 %s 中找到 %d 个配置项", configPath, len(content))
		
		// 记录所有找到的配置项
		for i, item := range content {
			if config, ok := item.(map[string]interface{}); ok {
				tag := "无标签"
				configType := "无类型"
				if t, exists := config["tag"]; exists {
					tag = fmt.Sprintf("%v", t)
				}
				if ct, exists := config["type"]; exists {
					configType = fmt.Sprintf("%v", ct)
				}
				utils.Logger.Infof("配置项 %d: tag=%s, type=%s", i, tag, configType)
			}
		}
		
		// 优先查找 forward_fakeip 或 forward_1 配置
		for i, item := range content {
			if config, ok := item.(map[string]interface{}); ok {
				if tag, exists := config["tag"]; exists {
					tagStr := fmt.Sprintf("%v", tag)
					if tagStr == "forward_fakeip" || tagStr == "forward_1" {
						utils.Logger.Infof("✅ 找到远程DNS配置: tag=%s 在 %s (索引 %d)", tagStr, configPath, i)
						return config, nil
					}
				}
			}
		}
		
		// 查找包含 fakeip 或 1 的配置
		for i, item := range content {
			if config, ok := item.(map[string]interface{}); ok {
				if tag, exists := config["tag"]; exists {
					tagStr := fmt.Sprintf("%v", tag)
					if (strings.Contains(strings.ToLower(tagStr), "fakeip") || 
					    strings.Contains(tagStr, "1")) && config["type"] == "forward" {
						utils.Logger.Infof("✅ 找到包含关键词的远程DNS配置: tag=%s 在 %s (索引 %d)", tagStr, configPath, i)
						return config, nil
					}
				}
			}
		}
		
		// 查找任何 forward 类型的配置（作为fallback，跳过本地DNS已用的）
		for i, item := range content {
			if config, ok := item.(map[string]interface{}); ok {
				if configType, exists := config["type"]; exists && configType == "forward" {
					if tag, exists := config["tag"]; exists {
						tagStr := fmt.Sprintf("%v", tag)
						// 跳过明显是本地DNS的配置
						if !strings.Contains(strings.ToLower(tagStr), "local") {
							utils.Logger.Infof("⚠️ 使用forward配置作为远程DNS: tag=%s 在 %s (索引 %d)", tagStr, configPath, i)
							return config, nil
						}
					}
				}
			}
		}
	}
	
	// 尝试读取为单个对象格式
	if config, err := utils.ReadYAMLConfig(configPath); err == nil {
		if tag, exists := config["tag"]; exists {
			tagStr := fmt.Sprintf("%v", tag)
			utils.Logger.Debugf("找到单个配置: tag=%s, type=%s", tagStr, config["type"])
			
			// 匹配多种可能的标签
			if tagStr == "forward_fakeip" || tagStr == "forward_1" || 
			   strings.Contains(tagStr, "fakeip") || strings.Contains(tagStr, "forward") {
				utils.Logger.Infof("成功读取远程DNS配置 (对象格式): tag=%s", tagStr)
				return config, nil
			}
		}
		
		// 如果是forward类型，直接使用
		if configType, exists := config["type"]; exists && fmt.Sprintf("%v", configType) == "forward" {
			utils.Logger.Infof("使用forward类型配置作为远程DNS (对象格式)")
			return config, nil
		}
	}
	
	return nil, fmt.Errorf("在配置文件中未找到合适的远程DNS配置")
}

// UpdateMosDNSRemoteDNS 更新MosDNS远程DNS配置
func (m *Manager) UpdateMosDNSRemoteDNS(config map[string]interface{}) error {
	configPath := "/cus/mosdns/sub_config/forward_1.yaml"
	
	// 备份原配置
	if _, err := m.BackupConfig("mosdns"); err != nil {
		utils.Logger.Warnf("备份远程DNS配置失败: %v", err)
	}
	
	// 写入新配置
	if err := utils.WriteYAMLConfig(configPath, config); err != nil {
		return fmt.Errorf("写入远程DNS配置失败: %v", err)
	}
	
	utils.Logger.Info("MosDNS远程DNS配置更新成功")
	return nil
}
