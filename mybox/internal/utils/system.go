package utils

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"strconv"
	"strings"
	"syscall"
	
	"gopkg.in/yaml.v3"
)

// IsRoot 检查是否为root用户
func IsRoot() bool {
	return os.Geteuid() == 0
}

// IsServiceRunning 检查systemd服务是否在运行
func IsServiceRunning(serviceName string) bool {
	// 尝试不带--quiet参数，获取更多信息
	output, err := RunCommand("systemctl", "is-active", serviceName)
	Logger.Debugf("检查服务 %s 运行状态: output='%s', err=%v", serviceName, output, err)
	
	// 检查输出是否为"active"
	return strings.TrimSpace(output) == "active"
}

// IsServiceEnabled 检查systemd服务是否已启用
func IsServiceEnabled(serviceName string) bool {
	cmd := exec.Command("systemctl", "is-enabled", "--quiet", serviceName)
	return cmd.Run() == nil
}

// StartSystemdService 启动systemd服务
func StartSystemdService(serviceName string) error {
	cmd := exec.Command("systemctl", "start", serviceName)
	return cmd.Run()
}

// StopSystemdService 停止systemd服务
func StopSystemdService(serviceName string) error {
	cmd := exec.Command("systemctl", "stop", serviceName)
	return cmd.Run()
}

// RestartSystemdService 重启systemd服务
func RestartSystemdService(serviceName string) error {
	cmd := exec.Command("systemctl", "restart", serviceName)
	return cmd.Run()
}

// EnableSystemdService 启用systemd服务开机自启
func EnableSystemdService(serviceName string) error {
	cmd := exec.Command("systemctl", "enable", serviceName)
	return cmd.Run()
}

// DisableSystemdService 禁用systemd服务开机自启
func DisableSystemdService(serviceName string) error {
	cmd := exec.Command("systemctl", "disable", serviceName)
	return cmd.Run()
}

// GetServicePID 获取服务的PID
func GetServicePID(serviceName string) (int, error) {
	cmd := exec.Command("systemctl", "show", "--property=MainPID", serviceName)
	output, err := cmd.Output()
	if err != nil {
		return 0, err
	}
	
	pidStr := strings.TrimSpace(strings.Split(string(output), "=")[1])
	if pidStr == "0" || pidStr == "" {
		return 0, fmt.Errorf("服务未运行或PID为0")
	}
	
	return strconv.Atoi(pidStr)
}

// KillProcess 终止进程
func KillProcess(pid int) error {
	process, err := os.FindProcess(pid)
	if err != nil {
		return err
	}
	
	// 先尝试优雅终止
	if err := process.Signal(syscall.SIGTERM); err != nil {
		// 如果失败，强制终止
		return process.Signal(syscall.SIGKILL)
	}
	
	return nil
}

// FileExists 检查文件是否存在
func FileExists(filename string) bool {
	_, err := os.Stat(filename)
	return !os.IsNotExist(err)
}

// IsExecutable 检查文件是否可执行
func IsExecutable(filename string) bool {
	info, err := os.Stat(filename)
	if err != nil {
		return false
	}
	
	return info.Mode()&0111 != 0
}

// GetLocalIP 获取本机IP地址
func GetLocalIP() string {
	cmd := exec.Command("hostname", "-I")
	output, err := cmd.Output()
	if err != nil {
		return "127.0.0.1"
	}
	
	ips := strings.Fields(string(output))
	if len(ips) > 0 {
		return ips[0]
	}
	
	return "127.0.0.1"
}

// RunCommand 执行命令并返回输出
func RunCommand(name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	output, err := cmd.Output()
	return strings.TrimSpace(string(output)), err
}

// RunCommandWithInput 执行命令并提供输入
func RunCommandWithInput(input, name string, args ...string) error {
	cmd := exec.Command(name, args...)
	cmd.Stdin = strings.NewReader(input)
	return cmd.Run()
}

// ReadConfig 读取并解析配置文件
func ReadConfig(configPath string) (map[string]interface{}, error) {
	// 检查文件是否存在
	if !FileExists(configPath) {
		return nil, fmt.Errorf("配置文件不存在: %s", configPath)
	}
	
	// 读取文件内容
	content, err := os.ReadFile(configPath)
	if err != nil {
		return nil, fmt.Errorf("读取文件失败: %v", err)
	}
	
	// 检查文件是否为空
	if len(content) == 0 {
		return nil, fmt.Errorf("配置文件为空: %s", configPath)
	}
	
	// 记录配置文件内容的前100个字符用于调试
	contentPreview := string(content)
	if len(contentPreview) > 100 {
		contentPreview = contentPreview[:100] + "..."
	}
	Logger.Debugf("配置文件内容预览: %s", contentPreview)
	
	// 预处理配置内容，移除注释和尾随逗号
	contentStr := string(content)
	cleanContent, err := cleanJSONContent(contentStr)
	if err != nil {
		return nil, fmt.Errorf("预处理配置文件失败: %v", err)
	}
	
	// 尝试解析JSON配置
	var config map[string]interface{}
	if err := json.Unmarshal([]byte(cleanContent), &config); err != nil {
		return nil, fmt.Errorf("解析JSON配置失败: %v。配置文件路径: %s", err, configPath)
	}
	
	Logger.Debugf("成功解析配置文件: %s，包含 %d 个顶级键", configPath, len(config))
	return config, nil
}

// cleanJSONContent 清理JSONC内容，移除注释和尾随逗号
func cleanJSONContent(content string) (string, error) {
	var result strings.Builder
	scanner := bufio.NewScanner(strings.NewReader(content))
	
	for scanner.Scan() {
		line := scanner.Text()
		cleanLine := cleanJSONLine(line)
		
		// 如果清理后的行不为空，添加到结果中
		if strings.TrimSpace(cleanLine) != "" {
			result.WriteString(cleanLine)
			result.WriteString("\n")
		}
	}
	
	if err := scanner.Err(); err != nil {
		return "", fmt.Errorf("读取内容失败: %v", err)
	}
	
	// 移除尾随逗号
	cleanedContent := removeTrailingCommas(result.String())
	
	return cleanedContent, nil
}

// cleanJSONLine 清理单行JSON，移除注释
func cleanJSONLine(line string) string {
	var result strings.Builder
	inString := false
	escape := false
	
	runes := []rune(line)
	for i, r := range runes {
		if escape {
			result.WriteRune(r)
			escape = false
			continue
		}
		
		if r == '\\' && inString {
			escape = true
			result.WriteRune(r)
			continue
		}
		
		if r == '"' {
			inString = !inString
			result.WriteRune(r)
			continue
		}
		
		// 如果在字符串外遇到//，停止处理这一行
		if !inString && r == '/' && i+1 < len(runes) && runes[i+1] == '/' {
			break
		}
		
		result.WriteRune(r)
	}
	
	return strings.TrimRightFunc(result.String(), func(r rune) bool {
		return r == ' ' || r == '\t'
	})
}

// removeTrailingCommas 移除尾随逗号
func removeTrailingCommas(content string) string {
	// 移除对象中的尾随逗号
	re1 := regexp.MustCompile(`,(\s*})`)
	content = re1.ReplaceAllString(content, "$1")
	
	// 移除数组中的尾随逗号
	re2 := regexp.MustCompile(`,(\s*])`)
	content = re2.ReplaceAllString(content, "$1")
	
	return content
}

// ReadYAMLConfig 读取并解析YAML配置文件
func ReadYAMLConfig(configPath string) (map[string]interface{}, error) {
	// 检查文件是否存在
	if !FileExists(configPath) {
		return nil, fmt.Errorf("配置文件不存在: %s", configPath)
	}
	
	// 读取文件内容
	content, err := os.ReadFile(configPath)
	if err != nil {
		return nil, fmt.Errorf("读取文件失败: %v", err)
	}
	
	// 检查文件是否为空
	if len(content) == 0 {
		return nil, fmt.Errorf("配置文件为空: %s", configPath)
	}
	
	// 解析YAML配置
	var config map[string]interface{}
	if err := yaml.Unmarshal(content, &config); err != nil {
		return nil, fmt.Errorf("解析YAML配置失败: %v。配置文件路径: %s", err, configPath)
	}
	
	Logger.Debugf("成功解析YAML配置文件: %s，包含 %d 个顶级键", configPath, len(config))
	return config, nil
}

// WriteYAMLConfig 写入YAML配置文件
func WriteYAMLConfig(configPath string, config map[string]interface{}) error {
	// 将配置转换为YAML格式
	yamlData, err := yaml.Marshal(config)
	if err != nil {
		return fmt.Errorf("转换为YAML格式失败: %v", err)
	}
	
	// 写入文件
	if err := os.WriteFile(configPath, yamlData, 0644); err != nil {
		return fmt.Errorf("写入配置文件失败: %v", err)
	}
	
	Logger.Debugf("成功写入YAML配置文件: %s", configPath)
	return nil
}

// ReadYAMLConfigAsArray 读取并解析YAML配置文件为数组
func ReadYAMLConfigAsArray(configPath string) ([]interface{}, error) {
	// 检查文件是否存在
	if !FileExists(configPath) {
		return nil, fmt.Errorf("配置文件不存在: %s", configPath)
	}
	
	// 读取文件内容
	content, err := os.ReadFile(configPath)
	if err != nil {
		return nil, fmt.Errorf("读取文件失败: %v", err)
	}
	
	// 检查文件是否为空
	if len(content) == 0 {
		return nil, fmt.Errorf("配置文件为空: %s", configPath)
	}
	
	// 解析YAML配置为数组
	var config []interface{}
	if err := yaml.Unmarshal(content, &config); err != nil {
		return nil, fmt.Errorf("解析YAML配置失败: %v。配置文件路径: %s", err, configPath)
	}
	
	Logger.Debugf("成功解析YAML配置文件为数组: %s，包含 %d 个元素", configPath, len(config))
	return config, nil
}

// IsProcessRunning 检查指定名称的进程是否在运行
func IsProcessRunning(processName string) bool {
	// 使用pgrep命令查找进程
	output, err := RunCommand("pgrep", "-f", processName)
	if err != nil {
		return false
	}
	
	// 如果有输出，说明进程存在
	return strings.TrimSpace(output) != ""
}

// GetProcessPID 获取指定名称进程的PID
func GetProcessPID(processName string) (int, error) {
	// 使用pgrep命令查找进程PID
	output, err := RunCommand("pgrep", "-f", processName)
	if err != nil {
		return 0, fmt.Errorf("进程 %s 未找到", processName)
	}
	
	pidStr := strings.TrimSpace(output)
	if pidStr == "" {
		return 0, fmt.Errorf("进程 %s 未运行", processName)
	}
	
	// 如果有多个PID，取第一个
	pids := strings.Fields(pidStr)
	if len(pids) == 0 {
		return 0, fmt.Errorf("进程 %s 未运行", processName)
	}
	
	return strconv.Atoi(pids[0])
}
