package utils

import (
	"io"
	"os"
	"path/filepath"

	"github.com/sirupsen/logrus"
)

var Logger *logrus.Logger

// InitLogger 初始化日志系统
func InitLogger() error {
	Logger = logrus.New()
	
	// 设置日志格式
	Logger.SetFormatter(&logrus.TextFormatter{
		FullTimestamp:   true,
		TimestampFormat: "2006-01-02 15:04:05",
		ForceColors:     true,
	})
	
	// 设置调试日志级别
	Logger.SetLevel(logrus.DebugLevel)
	
	// 创建日志目录
	logDir := "/var/log/mybox"
	if err := os.MkdirAll(logDir, 0755); err != nil {
		// 如果无法创建系统日志目录，使用当前目录
		logDir = "."
	}
	
	// 设置日志输出到文件和控制台
	logFile := filepath.Join(logDir, "mybox.log")
	file, err := os.OpenFile(logFile, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0666)
	if err != nil {
		// 如果无法写入日志文件，只输出到控制台
		Logger.SetOutput(os.Stdout)
		Logger.Warnf("无法创建日志文件 %s: %v，将只输出到控制台", logFile, err)
	} else {
		// 使用MultiWriter同时输出到文件和控制台
		multiWriter := io.MultiWriter(os.Stdout, file)
		Logger.SetOutput(multiWriter)
	}
	
	Logger.Info("MyBox日志系统已初始化")
	return nil
}

// SetLogLevel 设置日志级别
func SetLogLevel(level string) {
	switch level {
	case "debug":
		Logger.SetLevel(logrus.DebugLevel)
	case "info":
		Logger.SetLevel(logrus.InfoLevel)
	case "warn":
		Logger.SetLevel(logrus.WarnLevel)
	case "error":
		Logger.SetLevel(logrus.ErrorLevel)
	default:
		Logger.SetLevel(logrus.InfoLevel)
	}
}
