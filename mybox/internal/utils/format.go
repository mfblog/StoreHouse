package utils

import (
	"fmt"
	"strconv"
	"strings"
)

// 颜色常量
const (
	ColorReset  = "\033[0m"
	ColorRed    = "\033[31m"
	ColorGreen  = "\033[32m"
	ColorYellow = "\033[33m"
	ColorBlue   = "\033[34m"
	ColorPurple = "\033[35m"
	ColorCyan   = "\033[36m"
	ColorGray   = "\033[90m"
	ColorWhite  = "\033[97m"
)

// MakeGreen 绿色文本
func MakeGreen(text string) string {
	return ColorGreen + text + ColorReset
}

// MakeRed 红色文本
func MakeRed(text string) string {
	return ColorRed + text + ColorReset
}

// MakeYellow 黄色文本
func MakeYellow(text string) string {
	return ColorYellow + text + ColorReset
}

// MakeBlue 蓝色文本
func MakeBlue(text string) string {
	return ColorBlue + text + ColorReset
}

// MakeGray 灰色文本
func MakeGray(text string) string {
	return ColorGray + text + ColorReset
}

// FormatBytes 格式化字节数
func FormatBytes(bytes uint64) string {
	const unit = 1024
	if bytes < unit {
		return fmt.Sprintf("%d B", bytes)
	}
	
	div, exp := uint64(unit), 0
	for n := bytes / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}
	
	units := []string{"KB", "MB", "GB", "TB", "PB"}
	return fmt.Sprintf("%.1f %s", float64(bytes)/float64(div), units[exp])
}

// FormatPercent 格式化百分比
func FormatPercent(value float64) string {
	return fmt.Sprintf("%.1f%%", value)
}

// FormatUptime 格式化运行时间
func FormatUptime(seconds int64) string {
	if seconds < 60 {
		return fmt.Sprintf("%d秒", seconds)
	}
	
	minutes := seconds / 60
	if minutes < 60 {
		return fmt.Sprintf("%d分钟", minutes)
	}
	
	hours := minutes / 60
	if hours < 24 {
		return fmt.Sprintf("%d小时%d分钟", hours, minutes%60)
	}
	
	days := hours / 24
	return fmt.Sprintf("%d天%d小时", days, hours%24)
}

// PadRight 右填充字符串
func PadRight(str string, length int) string {
	if len(str) >= length {
		return str
	}
	return str + strings.Repeat(" ", length-len(str))
}

// PadLeft 左填充字符串
func PadLeft(str string, length int) string {
	if len(str) >= length {
		return str
	}
	return strings.Repeat(" ", length-len(str)) + str
}

// TruncateString 截断字符串
func TruncateString(str string, length int) string {
	if len(str) <= length {
		return str
	}
	if length <= 3 {
		return str[:length]
	}
	return str[:length-3] + "..."
}

// ParseSize 解析大小字符串 (如 "10MB", "1GB")
func ParseSize(sizeStr string) (uint64, error) {
	sizeStr = strings.ToUpper(strings.TrimSpace(sizeStr))
	
	// 提取数字部分
	var numStr string
	var unit string
	
	for i, c := range sizeStr {
		if c >= '0' && c <= '9' || c == '.' {
			numStr += string(c)
		} else {
			unit = sizeStr[i:]
			break
		}
	}
	
	if numStr == "" {
		return 0, fmt.Errorf("无效的大小格式: %s", sizeStr)
	}
	
	size, err := strconv.ParseFloat(numStr, 64)
	if err != nil {
		return 0, fmt.Errorf("无效的数字: %s", numStr)
	}
	
	// 转换单位
	switch unit {
	case "", "B":
		return uint64(size), nil
	case "K", "KB":
		return uint64(size * 1024), nil
	case "M", "MB":
		return uint64(size * 1024 * 1024), nil
	case "G", "GB":
		return uint64(size * 1024 * 1024 * 1024), nil
	case "T", "TB":
		return uint64(size * 1024 * 1024 * 1024 * 1024), nil
	default:
		return 0, fmt.Errorf("不支持的单位: %s", unit)
	}
}

// FormatTable 格式化表格
func FormatTable(headers []string, rows [][]string, padding int) string {
	if len(headers) == 0 || len(rows) == 0 {
		return ""
	}
	
	// 计算每列的最大宽度
	colWidths := make([]int, len(headers))
	for i, header := range headers {
		colWidths[i] = len(header)
	}
	
	for _, row := range rows {
		for i, cell := range row {
			if i < len(colWidths) && len(cell) > colWidths[i] {
				colWidths[i] = len(cell)
			}
		}
	}
	
	// 构建表格
	var result strings.Builder
	
	// 表头
	for i, header := range headers {
		if i > 0 {
			result.WriteString(strings.Repeat(" ", padding))
		}
		result.WriteString(PadRight(header, colWidths[i]))
	}
	result.WriteString("\n")
	
	// 分隔线
	for i := range headers {
		if i > 0 {
			result.WriteString(strings.Repeat(" ", padding))
		}
		result.WriteString(strings.Repeat("-", colWidths[i]))
	}
	result.WriteString("\n")
	
	// 数据行
	for _, row := range rows {
		for i, cell := range row {
			if i > 0 {
				result.WriteString(strings.Repeat(" ", padding))
			}
			if i < len(colWidths) {
				result.WriteString(PadRight(cell, colWidths[i]))
			} else {
				result.WriteString(cell)
			}
		}
		result.WriteString("\n")
	}
	
	return result.String()
}

// ProgressBar 创建进度条
func ProgressBar(current, total int, width int) string {
	if total <= 0 {
		return ""
	}
	
	percent := float64(current) / float64(total)
	if percent > 1 {
		percent = 1
	}
	
	filled := int(percent * float64(width))
	bar := strings.Repeat("=", filled) + strings.Repeat("-", width-filled)
	
	return fmt.Sprintf("[%s] %.1f%% (%d/%d)", bar, percent*100, current, total)
}
