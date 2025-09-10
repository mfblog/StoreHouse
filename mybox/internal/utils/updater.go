package utils

import (
	"archive/tar"
	"archive/zip"
	"compress/gzip"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
	"time"
)

// CoreUpdater 内核更新器
type CoreUpdater struct {
	ServiceName string
	BinaryPath  string
	BackupDir   string
}

// SystemInfo 系统信息
type SystemInfo struct {
	OS   string `json:"os"`
	Arch string `json:"arch"`
}

// UpdateResult 更新结果
type UpdateResult struct {
	Success     bool   `json:"success"`
	Message     string `json:"message"`
	OldVersion  string `json:"old_version,omitempty"`
	NewVersion  string `json:"new_version,omitempty"`
	BackupPath  string `json:"backup_path,omitempty"`
	Error       string `json:"error,omitempty"`
}

// GitHubRelease GitHub Release 结构
type GitHubRelease struct {
	TagName string `json:"tag_name"`
	Name    string `json:"name"`
	Assets  []struct {
		Name               string `json:"name"`
		BrowserDownloadURL string `json:"browser_download_url"`
	} `json:"assets"`
}

// ReleaseInfo Release 信息
type ReleaseInfo struct {
	Version     string            `json:"version"`
	DownloadURL string            `json:"download_url"`
	Assets      map[string]string `json:"assets"`
}

// NewCoreUpdater 创建内核更新器
func NewCoreUpdater(serviceName string) *CoreUpdater {
	var binaryPath string
	switch serviceName {
	case "sing-box":
		binaryPath = "/usr/local/bin/sing-box"
	case "mosdns":
		binaryPath = "/usr/local/bin/mosdns"
	default:
		binaryPath = fmt.Sprintf("/usr/local/bin/%s", serviceName)
	}

	return &CoreUpdater{
		ServiceName: serviceName,
		BinaryPath:  binaryPath,
		BackupDir:   "/etc/mybox/backups",
	}
}

// GetSystemInfo 获取系统信息
func (u *CoreUpdater) GetSystemInfo() SystemInfo {
	osName := runtime.GOOS
	archName := runtime.GOARCH
	
	// 转换为常用的架构名称
	switch archName {
	case "amd64":
		archName = "amd64"
	case "arm64":
		archName = "arm64"
	case "arm":
		archName = "armv7"
	case "386":
		archName = "386"
	}
	
	return SystemInfo{
		OS:   osName,
		Arch: archName,
	}
}

// GetCurrentVersion 获取当前版本
func (u *CoreUpdater) GetCurrentVersion() (string, error) {
	if !FileExists(u.BinaryPath) {
		return "", fmt.Errorf("二进制文件不存在: %s", u.BinaryPath)
	}
	
	var output string
	var err error
	
	switch u.ServiceName {
	case "sing-box":
		output, err = RunCommand(u.BinaryPath, "version")
		if err != nil {
			return "", fmt.Errorf("获取 sing-box 版本失败: %v", err)
		}
		
		// 解析 sing-box version 输出
		lines := strings.Split(output, "\n")
		for _, line := range lines {
			if strings.Contains(strings.ToLower(line), "version") {
				parts := strings.Fields(line)
				if len(parts) >= 2 {
					return parts[len(parts)-1], nil
				}
			}
		}
		
		// 如果没有找到 version 关键字，尝试解析第一行
		if len(lines) > 0 && lines[0] != "" {
			return strings.TrimSpace(lines[0]), nil
		}
		
	case "mosdns":
		output, err = RunCommand(u.BinaryPath, "version")
		if err != nil {
			return "", fmt.Errorf("获取 mosdns 版本失败: %v", err)
		}
		return strings.TrimSpace(output), nil
		
	default:
		return "", fmt.Errorf("不支持的服务: %s", u.ServiceName)
	}
	
	return "", fmt.Errorf("无法解析版本信息")
}

// BackupCurrentBinary 备份当前二进制文件
func (u *CoreUpdater) BackupCurrentBinary() (string, error) {
	if !FileExists(u.BinaryPath) {
		return "", fmt.Errorf("二进制文件不存在: %s", u.BinaryPath)
	}
	
	// 确保备份目录存在
	if err := os.MkdirAll(u.BackupDir, 0755); err != nil {
		return "", fmt.Errorf("创建备份目录失败: %v", err)
	}
	
	// 生成备份文件名（包含时间戳）
	timestamp := time.Now().Format("20060102-150405")
	backupFileName := fmt.Sprintf("%s-backup-%s", u.ServiceName, timestamp)
	backupPath := filepath.Join(u.BackupDir, backupFileName)
	
	// 复制文件
	if err := copyFile(u.BinaryPath, backupPath); err != nil {
		return "", fmt.Errorf("备份文件失败: %v", err)
	}
	
	// 设置执行权限
	if err := os.Chmod(backupPath, 0755); err != nil {
		Logger.Warnf("设置备份文件权限失败: %v", err)
	}
	
	Logger.Infof("成功备份 %s 到 %s", u.BinaryPath, backupPath)
	return backupPath, nil
}

// DownloadCore 下载内核文件
func (u *CoreUpdater) DownloadCore(downloadURL string) (string, error) {
	// 创建临时目录
	tempDir := "/tmp/mybox-update"
	if err := os.MkdirAll(tempDir, 0755); err != nil {
		return "", fmt.Errorf("创建临时目录失败: %v", err)
	}
	
	Logger.Infof("开始下载 %s 内核: %s", u.ServiceName, downloadURL)
	
	// 创建HTTP请求
	resp, err := http.Get(downloadURL)
	if err != nil {
		return "", fmt.Errorf("下载失败: %v", err)
	}
	defer resp.Body.Close()
	
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("下载失败，HTTP状态码: %d", resp.StatusCode)
	}
	
	// 根据URL判断文件类型
	isCompressed := strings.HasSuffix(downloadURL, ".tar.gz") || 
					strings.HasSuffix(downloadURL, ".zip") ||
					strings.HasSuffix(downloadURL, ".tgz")
	
	if isCompressed {
		// 处理压缩文件
		return u.downloadAndExtract(resp.Body, downloadURL, tempDir)
	} else {
		// 处理单个二进制文件
		return u.downloadBinary(resp.Body, tempDir)
	}
}

// downloadBinary 下载单个二进制文件
func (u *CoreUpdater) downloadBinary(reader io.Reader, tempDir string) (string, error) {
	tempFileName := fmt.Sprintf("%s-new", u.ServiceName)
	tempPath := filepath.Join(tempDir, tempFileName)
	
	// 创建临时文件
	out, err := os.Create(tempPath)
	if err != nil {
		return "", fmt.Errorf("创建临时文件失败: %v", err)
	}
	defer out.Close()
	
	// 复制数据
	_, err = io.Copy(out, reader)
	if err != nil {
		return "", fmt.Errorf("写入文件失败: %v", err)
	}
	
	// 设置执行权限
	if err := os.Chmod(tempPath, 0755); err != nil {
		return "", fmt.Errorf("设置文件权限失败: %v", err)
	}
	
	Logger.Infof("成功下载 %s 内核到 %s", u.ServiceName, tempPath)
	return tempPath, nil
}

// downloadAndExtract 下载并解压压缩文件
func (u *CoreUpdater) downloadAndExtract(reader io.Reader, downloadURL, tempDir string) (string, error) {
	// 先下载到临时文件
	downloadFileName := filepath.Base(downloadURL)
	downloadPath := filepath.Join(tempDir, downloadFileName)
	
	// 创建下载文件
	downloadFile, err := os.Create(downloadPath)
	if err != nil {
		return "", fmt.Errorf("创建下载文件失败: %v", err)
	}
	defer downloadFile.Close()
	
	// 下载文件
	_, err = io.Copy(downloadFile, reader)
	if err != nil {
		return "", fmt.Errorf("下载文件失败: %v", err)
	}
	
	Logger.Infof("成功下载压缩文件到 %s", downloadPath)
	
	// 解压文件
	extractDir := filepath.Join(tempDir, "extracted")
	if err := os.MkdirAll(extractDir, 0755); err != nil {
		return "", fmt.Errorf("创建解压目录失败: %v", err)
	}
	
	var binaryPath string
	
	if strings.HasSuffix(downloadURL, ".tar.gz") || strings.HasSuffix(downloadURL, ".tgz") {
		binaryPath, err = u.extractTarGz(downloadPath, extractDir)
	} else if strings.HasSuffix(downloadURL, ".zip") {
		binaryPath, err = u.extractZip(downloadPath, extractDir)
	} else {
		return "", fmt.Errorf("不支持的压缩格式")
	}
	
	if err != nil {
		return "", fmt.Errorf("解压文件失败: %v", err)
	}
	
	// 清理下载的压缩文件
	os.Remove(downloadPath)
	
	Logger.Infof("成功解压并找到二进制文件: %s", binaryPath)
	return binaryPath, nil
}

// extractTarGz 解压 tar.gz 文件
func (u *CoreUpdater) extractTarGz(archivePath, extractDir string) (string, error) {
	file, err := os.Open(archivePath)
	if err != nil {
		return "", err
	}
	defer file.Close()
	
	gzReader, err := gzip.NewReader(file)
	if err != nil {
		return "", err
	}
	defer gzReader.Close()
	
	tarReader := tar.NewReader(gzReader)
	
	var binaryPath string
	
	for {
		header, err := tarReader.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return "", err
		}
		
		targetPath := filepath.Join(extractDir, header.Name)
		
		switch header.Typeflag {
		case tar.TypeDir:
			if err := os.MkdirAll(targetPath, 0755); err != nil {
				return "", err
			}
		case tar.TypeReg:
			// 创建目录
			if err := os.MkdirAll(filepath.Dir(targetPath), 0755); err != nil {
				return "", err
			}
			
			// 创建文件
			outFile, err := os.Create(targetPath)
			if err != nil {
				return "", err
			}
			
			// 复制内容
			_, err = io.Copy(outFile, tarReader)
			outFile.Close()
			if err != nil {
				return "", err
			}
			
			// 设置权限
			if err := os.Chmod(targetPath, os.FileMode(header.Mode)); err != nil {
				Logger.Warnf("设置文件权限失败: %v", err)
			}
			
			// 检查是否是我们要找的二进制文件
			if u.isBinaryFile(targetPath, header.Name) {
				binaryPath = targetPath
			}
		}
	}
	
	if binaryPath == "" {
		return "", fmt.Errorf("在压缩包中未找到 %s 二进制文件", u.ServiceName)
	}
	
	return binaryPath, nil
}

// extractZip 解压 zip 文件
func (u *CoreUpdater) extractZip(archivePath, extractDir string) (string, error) {
	zipReader, err := zip.OpenReader(archivePath)
	if err != nil {
		return "", err
	}
	defer zipReader.Close()
	
	var binaryPath string
	
	for _, file := range zipReader.File {
		targetPath := filepath.Join(extractDir, file.Name)
		
		if file.FileInfo().IsDir() {
			if err := os.MkdirAll(targetPath, file.FileInfo().Mode()); err != nil {
				return "", err
			}
			continue
		}
		
		// 创建目录
		if err := os.MkdirAll(filepath.Dir(targetPath), 0755); err != nil {
			return "", err
		}
		
		// 打开zip文件中的文件
		rc, err := file.Open()
		if err != nil {
			return "", err
		}
		
		// 创建目标文件
		outFile, err := os.Create(targetPath)
		if err != nil {
			rc.Close()
			return "", err
		}
		
		// 复制内容
		_, err = io.Copy(outFile, rc)
		rc.Close()
		outFile.Close()
		if err != nil {
			return "", err
		}
		
		// 设置权限
		if err := os.Chmod(targetPath, file.FileInfo().Mode()); err != nil {
			Logger.Warnf("设置文件权限失败: %v", err)
		}
		
		// 检查是否是我们要找的二进制文件
		if u.isBinaryFile(targetPath, file.Name) {
			binaryPath = targetPath
		}
	}
	
	if binaryPath == "" {
		return "", fmt.Errorf("在压缩包中未找到 %s 二进制文件", u.ServiceName)
	}
	
	return binaryPath, nil
}

// isBinaryFile 检查文件是否是我们要找的二进制文件
func (u *CoreUpdater) isBinaryFile(filePath, fileName string) bool {
	// 检查文件名是否包含服务名
	baseName := filepath.Base(fileName)
	
	// 去掉路径中的目录部分，只看文件名
	if strings.Contains(strings.ToLower(baseName), strings.ToLower(u.ServiceName)) {
		// 检查文件是否可执行
		if info, err := os.Stat(filePath); err == nil {
			mode := info.Mode()
			if mode&0111 != 0 { // 检查是否有执行权限
				return true
			}
		}
		
		// 如果没有执行权限，但文件名匹配，也认为是二进制文件
		return true
	}
	
	return false
}

// InstallCore 安装内核文件
func (u *CoreUpdater) InstallCore(tempPath string) error {
	// 停止服务
	Logger.Infof("停止 %s 服务", u.ServiceName)
	if err := StopSystemdService(u.ServiceName); err != nil {
		Logger.Warnf("停止服务失败: %v", err)
	}
	
	// 等待服务完全停止
	time.Sleep(2 * time.Second)
	
	// 替换二进制文件
	Logger.Infof("替换二进制文件: %s -> %s", tempPath, u.BinaryPath)
	if err := copyFile(tempPath, u.BinaryPath); err != nil {
		return fmt.Errorf("替换二进制文件失败: %v", err)
	}
	
	// 设置执行权限
	if err := os.Chmod(u.BinaryPath, 0755); err != nil {
		return fmt.Errorf("设置文件权限失败: %v", err)
	}
	
	// 启动服务
	Logger.Infof("启动 %s 服务", u.ServiceName)
	if err := StartSystemdService(u.ServiceName); err != nil {
		return fmt.Errorf("启动服务失败: %v", err)
	}
	
	// 等待服务启动
	time.Sleep(3 * time.Second)
	
	// 验证服务状态
	if !IsServiceRunning(u.ServiceName) {
		return fmt.Errorf("服务启动失败，请检查日志")
	}
	
	// 清理临时文件
	if err := os.Remove(tempPath); err != nil {
		Logger.Warnf("清理临时文件失败: %v", err)
	}
	
	Logger.Infof("成功安装 %s 内核", u.ServiceName)
	return nil
}

// UpdateCore 执行完整的内核更新流程
func (u *CoreUpdater) UpdateCore(downloadURL string) *UpdateResult {
	result := &UpdateResult{}
	
	// 获取当前版本
	oldVersion, err := u.GetCurrentVersion()
	if err != nil {
		result.Error = fmt.Sprintf("获取当前版本失败: %v", err)
		return result
	}
	result.OldVersion = oldVersion
	
	// 备份当前二进制文件
	backupPath, err := u.BackupCurrentBinary()
	if err != nil {
		result.Error = fmt.Sprintf("备份失败: %v", err)
		return result
	}
	result.BackupPath = backupPath
	
	// 下载新内核
	tempPath, err := u.DownloadCore(downloadURL)
	if err != nil {
		result.Error = fmt.Sprintf("下载失败: %v", err)
		return result
	}
	
	// 安装新内核
	if err := u.InstallCore(tempPath); err != nil {
		result.Error = fmt.Sprintf("安装失败: %v", err)
		
		// 尝试恢复备份
		Logger.Warnf("安装失败，尝试恢复备份: %s", backupPath)
		if restoreErr := copyFile(backupPath, u.BinaryPath); restoreErr != nil {
			result.Error += fmt.Sprintf("，恢复备份也失败: %v", restoreErr)
		} else {
			os.Chmod(u.BinaryPath, 0755)
			StartSystemdService(u.ServiceName)
			result.Error += "，已恢复到原版本"
		}
		return result
	}
	
	// 获取新版本
	newVersion, err := u.GetCurrentVersion()
	if err != nil {
		Logger.Warnf("获取新版本失败: %v", err)
		newVersion = "未知"
	}
	result.NewVersion = newVersion
	
	result.Success = true
	result.Message = fmt.Sprintf("成功更新 %s 内核从 %s 到 %s", u.ServiceName, oldVersion, newVersion)
	
	return result
}

// RestoreFromBackup 从备份恢复
func (u *CoreUpdater) RestoreFromBackup(backupPath string) error {
	if !FileExists(backupPath) {
		return fmt.Errorf("备份文件不存在: %s", backupPath)
	}
	
	// 停止服务
	Logger.Infof("停止 %s 服务", u.ServiceName)
	if err := StopSystemdService(u.ServiceName); err != nil {
		Logger.Warnf("停止服务失败: %v", err)
	}
	
	time.Sleep(2 * time.Second)
	
	// 恢复文件
	Logger.Infof("恢复二进制文件: %s -> %s", backupPath, u.BinaryPath)
	if err := copyFile(backupPath, u.BinaryPath); err != nil {
		return fmt.Errorf("恢复文件失败: %v", err)
	}
	
	// 设置权限
	if err := os.Chmod(u.BinaryPath, 0755); err != nil {
		return fmt.Errorf("设置文件权限失败: %v", err)
	}
	
	// 启动服务
	Logger.Infof("启动 %s 服务", u.ServiceName)
	if err := StartSystemdService(u.ServiceName); err != nil {
		return fmt.Errorf("启动服务失败: %v", err)
	}
	
	time.Sleep(3 * time.Second)
	
	if !IsServiceRunning(u.ServiceName) {
		return fmt.Errorf("服务启动失败")
	}
	
	Logger.Infof("成功恢复 %s 内核", u.ServiceName)
	return nil
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
	
	_, err = io.Copy(destFile, sourceFile)
	if err != nil {
		return err
	}
	
	return destFile.Sync()
}

// ListBackups 列出备份文件
func (u *CoreUpdater) ListBackups() ([]string, error) {
	if !FileExists(u.BackupDir) {
		return []string{}, nil
	}
	
	files, err := os.ReadDir(u.BackupDir)
	if err != nil {
		return nil, err
	}
	
	var backups []string
	prefix := u.ServiceName + "-backup-"
	
	for _, file := range files {
		if !file.IsDir() && strings.HasPrefix(file.Name(), prefix) {
			backups = append(backups, filepath.Join(u.BackupDir, file.Name()))
		}
	}
	
	return backups, nil
}

// ParseGitHubReleaseURL 解析 GitHub Release URL 并获取发布信息
func (u *CoreUpdater) ParseGitHubReleaseURL(releaseURL string) (*ReleaseInfo, error) {
	// 解析 GitHub Release URL
	// 支持格式：https://github.com/user/repo/releases/tag/tagname
	re := regexp.MustCompile(`https://github\.com/([^/]+)/([^/]+)/releases/tag/(.+)`)
	matches := re.FindStringSubmatch(releaseURL)
	
	if len(matches) != 4 {
		return nil, fmt.Errorf("无效的 GitHub Release URL 格式")
	}
	
	owner := matches[1]
	repo := matches[2]
	tag := matches[3]
	
	// 构建 GitHub API URL
	apiURL := fmt.Sprintf("https://api.github.com/repos/%s/%s/releases/tags/%s", owner, repo, tag)
	
	// 发起 HTTP 请求
	resp, err := http.Get(apiURL)
	if err != nil {
		return nil, fmt.Errorf("请求 GitHub API 失败: %v", err)
	}
	defer resp.Body.Close()
	
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("GitHub API 响应错误: %d", resp.StatusCode)
	}
	
	// 解析 JSON 响应
	var release GitHubRelease
	if err := json.NewDecoder(resp.Body).Decode(&release); err != nil {
		return nil, fmt.Errorf("解析 GitHub API 响应失败: %v", err)
	}
	
	// 获取系统信息
	systemInfo := u.GetSystemInfo()
	
	// 查找匹配的资源文件
	downloadURL, assets := u.findMatchingAsset(release.Assets, systemInfo)
	
	releaseInfo := &ReleaseInfo{
		Version:     release.TagName,
		DownloadURL: downloadURL,
		Assets:      assets,
	}
	
	return releaseInfo, nil
}

// findMatchingAsset 根据系统架构查找匹配的资源文件
func (u *CoreUpdater) findMatchingAsset(assets []struct {
	Name               string `json:"name"`
	BrowserDownloadURL string `json:"browser_download_url"`
}, systemInfo SystemInfo) (string, map[string]string) {
	
	assetMap := make(map[string]string)
	var bestMatch string
	
	// 构建匹配模式
	var archPatterns []string
	switch systemInfo.Arch {
	case "amd64":
		archPatterns = []string{"amd64", "x86_64", "x64"}
	case "arm64":
		archPatterns = []string{"arm64", "aarch64"}
	case "armv7":
		archPatterns = []string{"armv7", "arm"}
	case "386":
		archPatterns = []string{"386", "i386", "x86"}
	default:
		archPatterns = []string{systemInfo.Arch}
	}
	
	// 遍历所有资源文件
	for _, asset := range assets {
		name := strings.ToLower(asset.Name)
		assetMap[asset.Name] = asset.BrowserDownloadURL
		
		// 检查是否匹配当前系统
		isOSMatch := strings.Contains(name, strings.ToLower(systemInfo.OS))
		isArchMatch := false
		
		for _, pattern := range archPatterns {
			if strings.Contains(name, strings.ToLower(pattern)) {
				isArchMatch = true
				break
			}
		}
		
		// 排除不需要的文件类型
		isValidType := !strings.Contains(name, ".txt") && 
		              !strings.Contains(name, ".md") && 
		              !strings.Contains(name, ".sig") &&
		              !strings.Contains(name, ".sha") &&
		              (strings.Contains(name, ".tar.gz") || 
		               strings.Contains(name, ".zip") || 
		               strings.HasSuffix(name, u.ServiceName) ||
		               (!strings.Contains(name, ".") && len(name) > 3))
		
		// 排除 v3 版本（优先选择标准版本）
		isNotV3 := !strings.Contains(name, "-v3") && !strings.Contains(name, "v3.")
		
		if isOSMatch && isArchMatch && isValidType && isNotV3 {
			bestMatch = asset.BrowserDownloadURL
			Logger.Infof("找到匹配的资源文件: %s (OS: %s, Arch: %s)", asset.Name, systemInfo.OS, systemInfo.Arch)
			break
		}
	}
	
	// 如果没有找到完全匹配的，尝试只匹配架构
	if bestMatch == "" {
		for _, asset := range assets {
			name := strings.ToLower(asset.Name)
			
			isArchMatch := false
			for _, pattern := range archPatterns {
				if strings.Contains(name, strings.ToLower(pattern)) {
					isArchMatch = true
					break
				}
			}
			
			isValidType := !strings.Contains(name, ".txt") && 
			              !strings.Contains(name, ".md") && 
			              !strings.Contains(name, ".sig") &&
			              !strings.Contains(name, ".sha") &&
			              (strings.Contains(name, ".tar.gz") || 
			               strings.Contains(name, ".zip") || 
			               strings.HasSuffix(name, u.ServiceName) ||
			               (!strings.Contains(name, ".") && len(name) > 3))
			
			// 排除 v3 版本（优先选择标准版本）
			isNotV3 := !strings.Contains(name, "-v3") && !strings.Contains(name, "v3.")
			
			if isArchMatch && isValidType && isNotV3 {
				bestMatch = asset.BrowserDownloadURL
				Logger.Infof("找到部分匹配的资源文件: %s (Arch: %s)", asset.Name, systemInfo.Arch)
				break
			}
		}
	}
	
	return bestMatch, assetMap
}

// UpdateFromGitHubRelease 从 GitHub Release 更新内核
func (u *CoreUpdater) UpdateFromGitHubRelease(releaseURL string) *UpdateResult {
	result := &UpdateResult{}
	
	// 解析 GitHub Release
	releaseInfo, err := u.ParseGitHubReleaseURL(releaseURL)
	if err != nil {
		result.Error = fmt.Sprintf("解析 GitHub Release 失败: %v", err)
		return result
	}
	
	if releaseInfo.DownloadURL == "" {
		result.Error = "未找到适合当前系统架构的下载文件"
		return result
	}
	
	Logger.Infof("从 GitHub Release 更新: %s -> %s", releaseInfo.Version, releaseInfo.DownloadURL)
	
	// 使用找到的下载链接执行更新
	return u.UpdateCore(releaseInfo.DownloadURL)
}
