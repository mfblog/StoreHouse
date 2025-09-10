package embed

import (
    "embed"
)

//go:embed config
var configFS embed.FS

// GetDefaultConfig 返回默认配置文件内容
func GetDefaultConfig() ([]byte, error) {
    return configFS.ReadFile("config/default.yaml")
}
