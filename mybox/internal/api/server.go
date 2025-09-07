package api

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/herozmy/StoreHouse/mybox/internal/config"
	"github.com/herozmy/StoreHouse/mybox/internal/embed"
	"github.com/herozmy/StoreHouse/mybox/internal/monitor"
	"github.com/herozmy/StoreHouse/mybox/internal/service"
	"github.com/herozmy/StoreHouse/mybox/internal/utils"
)

// Server Web API服务器
type Server struct {
	engine         *gin.Engine
	serviceManager *service.Manager
	configManager  *config.Manager
	monitor        *monitor.Monitor
	server         *http.Server
}

// NewServer 创建API服务器
func NewServer() *Server {
	// 设置Gin模式
	gin.SetMode(gin.ReleaseMode)
	
	engine := gin.New()
	
	// 添加中间件
	engine.Use(gin.Logger())
	engine.Use(gin.Recovery())
	engine.Use(corsMiddleware())
	
	server := &Server{
		engine:         engine,
		serviceManager: service.NewManager(),
		configManager:  config.NewManager(),
		monitor:        monitor.NewMonitor(),
	}
	
	// 注册路由
	server.setupRoutes()
	
	return server
}

// setupRoutes 设置路由
func (s *Server) setupRoutes() {
	// API路由组
	api := s.engine.Group("/api")
	{
		// 健康检查
		api.GET("/health", s.healthCheck)
		
		// 服务管理
		services := api.Group("/services")
		{
			services.GET("", s.getServicesStatus)
			services.GET("/:name", s.getServiceStatus)
			services.POST("/:name/start", s.startService)
			services.POST("/:name/stop", s.stopService)
			services.POST("/:name/restart", s.restartService)
			services.POST("/:name/enable", s.enableService)
			services.POST("/:name/disable", s.disableService)
		}
		
		// 日志管理
		logs := api.Group("/logs")
		{
			logs.GET("/:service", s.getLogs)
			logs.GET("/:service/tail", s.tailLogs)
		}
		
		// 监控和指标
		api.GET("/metrics", s.getMetrics)
		api.GET("/metrics/system", s.getSystemMetrics)
		api.GET("/metrics/services", s.getServicesMetrics)
		
		// 系统信息
		api.GET("/system", s.getSystemInfo)
		
		// 版本信息
		api.GET("/version/:service", s.getServiceVersion)
		
		// 内核更新
		update := api.Group("/update")
		{
			update.GET("/:service/info", s.getUpdateInfo)
			update.POST("/:service/core", s.updateCore)
			update.POST("/:service/github", s.updateFromGitHub)
			update.GET("/:service/backups", s.getUpdateBackups)
			update.POST("/:service/restore", s.restoreFromBackup)
		}
		
		// 网络信息
		network := api.Group("/network")
		{
			network.GET("/routes", s.getStaticRoutes)
			network.GET("/nftables", s.getNftablesRules)
		}
		
		// 配置管理
		config := api.Group("/config")
		{
			// Sing-Box 专用配置接口（具体路由优先）
			config.GET("/sing-box", s.getSingBoxConfig)
			config.PUT("/sing-box", s.updateSingBoxConfig)
			config.POST("/sing-box/validate", s.validateSingBoxConfig)
			
			// MosDNS 专用配置接口
			config.GET("/mosdns", s.getMosDNSConfig)
			config.PUT("/mosdns", s.updateMosDNSConfig)
			config.POST("/mosdns/validate", s.validateMosDNSConfig)
			
			// MosDNS 详细配置管理
			mosdns := config.Group("/mosdns")
			{
				mosdns.GET("/local-dns", s.getMosDNSLocalDNS)
				mosdns.PUT("/local-dns", s.updateMosDNSLocalDNS)
				mosdns.GET("/remote-dns", s.getMosDNSRemoteDNS)
				mosdns.PUT("/remote-dns", s.updateMosDNSRemoteDNS)
				mosdns.GET("/raw-config", s.getMosDNSRawConfig)
				mosdns.GET("/parsed-config", s.getMosDNSParsedConfig)
				mosdns.PUT("/parsed-config", s.updateMosDNSParsedConfig)
			}
			
			// 通用配置接口（通配符路由放最后）
			config.GET("/:service", s.getConfig)
			config.PUT("/:service", s.updateConfig)
			config.POST("/:service/validate", s.validateConfig)
			config.POST("/:service/backup", s.backupConfig)
			config.GET("/:service/backups", s.listBackups)
			config.POST("/:service/restore", s.restoreConfig)
		}
	}
	
	// 使用嵌入的Web界面 - Vue.js架构
	s.engine.NoRoute(func(c *gin.Context) {
		// 如果不是API请求，则尝试提供静态文件
		if !strings.HasPrefix(c.Request.URL.Path, "/api/") {
			fileServer := http.FileServer(embed.GetWebFS())
			fileServer.ServeHTTP(c.Writer, c.Request)
			return
		}
		// 如果是API请求但没有匹配的路由，返回404
		c.JSON(http.StatusNotFound, gin.H{
			"error": "API endpoint not found",
		})
	})
	
	utils.Logger.Info("使用嵌入的Web界面 - Vue.js架构")
}

// Start 启动服务器
func (s *Server) Start(addr string) error {
	s.server = &http.Server{
		Addr:    addr,
		Handler: s.engine,
	}
	
	utils.Logger.Infof("Web API服务器启动在 %s", addr)
	
	if err := s.server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		return fmt.Errorf("启动服务器失败: %v", err)
	}
	
	return nil
}

// Stop 停止服务器
func (s *Server) Stop() error {
	if s.server != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		
		return s.server.Shutdown(ctx)
	}
	return nil
}

// corsMiddleware CORS中间件
func corsMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Header("Access-Control-Allow-Origin", "*")
		c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Origin, Content-Type, Accept, Authorization")
		
		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}
		
		c.Next()
	}
}

// healthCheck 健康检查
func (s *Server) healthCheck(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"status":    "ok",
		"timestamp": time.Now(),
		"version":   "1.0.0",
	})
}

// getServicesStatus 获取所有服务状态
func (s *Server) getServicesStatus(c *gin.Context) {
	utils.Logger.Infof("API请求: 获取所有服务状态")
	
	statuses := s.serviceManager.GetAllServicesStatus()
	utils.Logger.Infof("服务状态汇总: %+v", statuses)
	
	result := make(map[string]interface{})
	for name, status := range statuses {
		utils.Logger.Infof("处理服务 %s, 状态: %d", name, status)
		
		info, err := s.serviceManager.GetServiceInfo(name)
		if err != nil {
			utils.Logger.Errorf("获取服务 %s 详细信息失败: %v", name, err)
			result[name] = gin.H{
				"status": status,
				"error":  err.Error(),
			}
			continue
		}
		
		utils.Logger.Infof("服务 %s 详细信息: PID=%d, Status=%d", name, info.PID, info.Status)
		
		result[name] = gin.H{
			"status":       status,
			"pid":          info.PID,
			"cpu_percent":  info.CPUPercent,
			"memory_bytes": info.MemoryBytes,
			"start_time":   info.StartTime,
		}
	}
	
	utils.Logger.Infof("最终返回结果: %+v", result)
	
	c.JSON(http.StatusOK, gin.H{
		"services": result,
	})
}

// getServiceStatus 获取指定服务状态
func (s *Server) getServiceStatus(c *gin.Context) {
	serviceName := c.Param("name")
	
	info, err := s.serviceManager.GetServiceInfo(serviceName)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{
			"error": err.Error(),
		})
		return
	}
	
	c.JSON(http.StatusOK, gin.H{
		"name":         info.Name,
		"status":       info.Status,
		"pid":          info.PID,
		"cpu_percent":  info.CPUPercent,
		"memory_bytes": info.MemoryBytes,
		"start_time":   info.StartTime,
		"config_path":  info.ConfigPath,
		"binary_path":  info.BinaryPath,
	})
}

// startService 启动服务
func (s *Server) startService(c *gin.Context) {
	serviceName := c.Param("name")
	
	if err := s.serviceManager.StartService(serviceName); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": err.Error(),
		})
		return
	}
	
	c.JSON(http.StatusOK, gin.H{
		"message": fmt.Sprintf("服务 %s 启动成功", serviceName),
	})
}

// stopService 停止服务
func (s *Server) stopService(c *gin.Context) {
	serviceName := c.Param("name")
	
	if err := s.serviceManager.StopService(serviceName); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": err.Error(),
		})
		return
	}
	
	c.JSON(http.StatusOK, gin.H{
		"message": fmt.Sprintf("服务 %s 停止成功", serviceName),
	})
}

// restartService 重启服务
func (s *Server) restartService(c *gin.Context) {
	serviceName := c.Param("name")
	
	if err := s.serviceManager.RestartService(serviceName); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": err.Error(),
		})
		return
	}
	
	c.JSON(http.StatusOK, gin.H{
		"message": fmt.Sprintf("服务 %s 重启成功", serviceName),
	})
}

// enableService 启用服务开机自启
func (s *Server) enableService(c *gin.Context) {
	serviceName := c.Param("name")
	
	if err := s.serviceManager.EnableService(serviceName); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": err.Error(),
		})
		return
	}
	
	c.JSON(http.StatusOK, gin.H{
		"message": fmt.Sprintf("服务 %s 开机自启已启用", serviceName),
	})
}

// disableService 禁用服务开机自启
func (s *Server) disableService(c *gin.Context) {
	serviceName := c.Param("name")
	
	if err := s.serviceManager.DisableService(serviceName); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": err.Error(),
		})
		return
	}
	
	c.JSON(http.StatusOK, gin.H{
		"message": fmt.Sprintf("服务 %s 开机自启已禁用", serviceName),
	})
}

// getConfig 获取服务配置
func (s *Server) getConfig(c *gin.Context) {
	serviceName := c.Param("service")
	
	content, err := s.configManager.GetConfigContent(serviceName)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": err.Error(),
		})
		return
	}
	
	c.JSON(http.StatusOK, gin.H{
		"service": serviceName,
		"content": content,
	})
}

// updateConfig 更新服务配置
func (s *Server) updateConfig(c *gin.Context) {
	serviceName := c.Param("service")
	
	var req struct {
		Content string `json:"content" binding:"required"`
	}
	
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": err.Error(),
		})
		return
	}
	
	if err := s.configManager.SetConfigContent(serviceName, req.Content); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": err.Error(),
		})
		return
	}
	
	c.JSON(http.StatusOK, gin.H{
		"message": fmt.Sprintf("服务 %s 配置更新成功", serviceName),
	})
}

// validateConfig 验证服务配置
func (s *Server) validateConfig(c *gin.Context) {
	serviceName := c.Param("service")
	
	if err := s.configManager.ValidateConfig(serviceName); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"valid": false,
			"error": err.Error(),
		})
		return
	}
	
	c.JSON(http.StatusOK, gin.H{
		"valid":   true,
		"message": "配置验证通过",
	})
}

// backupConfig 备份服务配置
func (s *Server) backupConfig(c *gin.Context) {
	serviceName := c.Param("service")
	
	backupPath, err := s.configManager.BackupConfig(serviceName)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": err.Error(),
		})
		return
	}
	
	c.JSON(http.StatusOK, gin.H{
		"message":     "配置备份成功",
		"backup_path": backupPath,
	})
}

// listBackups 列出备份文件
func (s *Server) listBackups(c *gin.Context) {
	serviceName := c.Param("service")
	
	backups, err := s.configManager.ListBackups(serviceName)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": err.Error(),
		})
		return
	}
	
	c.JSON(http.StatusOK, gin.H{
		"service": serviceName,
		"backups": backups,
	})
}

// restoreConfig 恢复配置
func (s *Server) restoreConfig(c *gin.Context) {
	serviceName := c.Param("service")
	
	var req struct {
		BackupPath string `json:"backup_path"`
	}
	
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": err.Error(),
		})
		return
	}
	
	var err error
	if req.BackupPath == "" {
		// 恢复最新备份
		err = s.configManager.RestoreLatestConfig(serviceName)
	} else {
		// 恢复指定备份
		err = s.configManager.RestoreConfig(serviceName, req.BackupPath)
	}
	
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": err.Error(),
		})
		return
	}
	
	c.JSON(http.StatusOK, gin.H{
		"message": "配置恢复成功",
	})
}

// getLogs 获取服务日志
func (s *Server) getLogs(c *gin.Context) {
	serviceName := c.Param("service")
	lines := 100
	
	if l := c.Query("lines"); l != "" {
		if parsed, err := parseIntParam(l); err == nil {
			lines = parsed
		}
	}
	
	logs, err := s.serviceManager.GetLogs(serviceName, lines)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": err.Error(),
		})
		return
	}
	
	c.JSON(http.StatusOK, gin.H{
		"service": serviceName,
		"logs":    logs,
	})
}

// tailLogs 实时日志流
func (s *Server) tailLogs(c *gin.Context) {
	// 这里应该实现WebSocket连接来提供实时日志流
	// 为简化，返回错误提示
	c.JSON(http.StatusNotImplemented, gin.H{
		"error": "实时日志流功能尚未实现，请使用命令行工具",
	})
}

// getMetrics 获取所有指标
func (s *Server) getMetrics(c *gin.Context) {
	metrics, err := s.monitor.GetAllMetrics()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": err.Error(),
		})
		return
	}
	
	c.JSON(http.StatusOK, metrics)
}

// getSystemMetrics 获取系统指标
func (s *Server) getSystemMetrics(c *gin.Context) {
	metrics, err := service.GetSystemMetrics()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": err.Error(),
		})
		return
	}
	
	c.JSON(http.StatusOK, metrics)
}

// getSystemInfo 获取系统信息（CPU、内存、磁盘使用率）
func (s *Server) getSystemInfo(c *gin.Context) {
	metrics, err := service.GetSystemMetrics()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": err.Error(),
		})
		return
	}
	
	// 提取需要的系统信息
	c.JSON(http.StatusOK, gin.H{
		"cpu":    int(metrics.CPUPercent),
		"memory": int(metrics.MemoryPercent),
		"disk":   int(metrics.DiskPercent),
	})
}

// getServicesMetrics 获取服务指标
func (s *Server) getServicesMetrics(c *gin.Context) {
	services := []string{"sing-box", "mosdns"}
	result := make(map[string]interface{})
	
	for _, serviceName := range services {
		metrics, err := s.monitor.GetServiceMetrics(serviceName)
		if err != nil {
			result[serviceName] = gin.H{
				"error": err.Error(),
			}
			continue
		}
		result[serviceName] = metrics
	}
	
	c.JSON(http.StatusOK, gin.H{
		"services": result,
	})
}

// parseIntParam 解析整数参数
func parseIntParam(s string) (int, error) {
	// 简单的整数解析，可以使用strconv.Atoi
	var result int
	for _, c := range s {
		if c < '0' || c > '9' {
			return 0, fmt.Errorf("无效的数字")
		}
		result = result*10 + int(c-'0')
	}
	return result, nil
}





// defaultHomePage 默认主页（备用）
func (s *Server) defaultHomePage(c *gin.Context) {
	html := `<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>MyBox - 代理服务控制中心</title>
    <style>
        body { font-family: Arial, sans-serif; max-width: 800px; margin: 50px auto; padding: 20px; }
        .header { text-align: center; color: #333; }
        .api-list { background: #f5f5f5; padding: 20px; border-radius: 8px; margin: 20px 0; }
        .api-item { margin: 10px 0; }
        .method { background: #007bff; color: white; padding: 2px 8px; border-radius: 4px; font-size: 12px; }
        .url { font-family: monospace; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🎉 MyBox API 服务器</h1>
        <p>代理服务控制中心 - Web界面文件未找到，显示API文档</p>
    </div>
    
    <div class="api-list">
        <h3>📋 可用的API接口</h3>
        
        <div class="api-item">
            <span class="method">GET</span>
            <span class="url">/api/health</span> - 健康检查
        </div>
        
        <div class="api-item">
            <span class="method">GET</span>
            <span class="url">/api/services</span> - 获取所有服务状态
        </div>
        
        <div class="api-item">
            <span class="method">GET</span>
            <span class="url">/api/services/{name}</span> - 获取指定服务状态
        </div>
        
        <div class="api-item">
            <span class="method">POST</span>
            <span class="url">/api/services/{name}/start</span> - 启动服务
        </div>
        
        <div class="api-item">
            <span class="method">POST</span>
            <span class="url">/api/services/{name}/stop</span> - 停止服务
        </div>
        
        <div class="api-item">
            <span class="method">POST</span>
            <span class="url">/api/services/{name}/restart</span> - 重启服务
        </div>
        
        <div class="api-item">
            <span class="method">GET</span>
            <span class="url">/api/metrics</span> - 获取所有指标
        </div>
        
        <div class="api-item">
            <span class="method">GET</span>
            <span class="url">/api/metrics/system</span> - 获取系统指标
        </div>
        
        <div class="api-item">
            <span class="method">GET</span>
            <span class="url">/api/config/{service}</span> - 获取服务配置
        </div>
        
        <div class="api-item">
            <span class="method">GET</span>
            <span class="url">/api/logs/{service}</span> - 获取服务日志
        </div>
    </div>
    
    <div style="text-align: center; margin-top: 40px; color: #666;">
        <p>💡 提示：安装完整的Web界面文件到以下路径之一：</p>
        <ul style="text-align: left; display: inline-block;">
            <li><code>./web/index.html</code></li>
            <li><code>/etc/mybox/web/index.html</code></li>
            <li><code>/usr/share/mybox/web/index.html</code></li>
        </ul>
    </div>
    
    <div style="text-align: center; margin-top: 20px; color: #999;">
        <p>MyBox v1.0.0 - 代理服务控制中心</p>
    </div>
</body>
</html>`
	
	c.Header("Content-Type", "text/html; charset=utf-8")
	c.String(http.StatusOK, html)
}

// getSingBoxConfig 获取Sing-Box配置
func (s *Server) getSingBoxConfig(c *gin.Context) {
	utils.Logger.Info("开始获取Sing-Box配置")
	
	config, err := s.configManager.GetSingBoxConfig()
	if err != nil {
		utils.Logger.Errorf("获取Sing-Box配置失败: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": fmt.Sprintf("获取配置失败: %v", err),
		})
		return
	}

	utils.Logger.Infof("成功获取Sing-Box配置，包含 %d 个顶级键", len(config))
	c.JSON(http.StatusOK, gin.H{
		"config": config,
	})
}

// getMosDNSConfig 获取MosDNS配置
func (s *Server) getMosDNSConfig(c *gin.Context) {
	config, err := s.configManager.GetMosDNSConfig()
	if err != nil {
		utils.Logger.Errorf("获取MosDNS配置失败: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": fmt.Sprintf("获取配置失败: %v", err),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"config": config,
	})
}

// updateSingBoxConfig 更新Sing-Box配置
func (s *Server) updateSingBoxConfig(c *gin.Context) {
	var req struct {
		Content string `json:"content" binding:"required"`
	}
	
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": fmt.Sprintf("请求参数错误: %v", err),
		})
		return
	}
	
	if err := s.configManager.SetConfigContent("sing-box", req.Content); err != nil {
		utils.Logger.Errorf("更新Sing-Box配置失败: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": fmt.Sprintf("更新配置失败: %v", err),
		})
		return
	}
	
	utils.Logger.Info("Sing-Box配置更新成功")
	c.JSON(http.StatusOK, gin.H{
		"message": "配置更新成功",
	})
}

// updateMosDNSConfig 更新MosDNS配置
func (s *Server) updateMosDNSConfig(c *gin.Context) {
	var req struct {
		Content string `json:"content" binding:"required"`
	}
	
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": fmt.Sprintf("请求参数错误: %v", err),
		})
		return
	}
	
	if err := s.configManager.SetConfigContent("mosdns", req.Content); err != nil {
		utils.Logger.Errorf("更新MosDNS配置失败: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": fmt.Sprintf("更新配置失败: %v", err),
		})
		return
	}
	
	utils.Logger.Info("MosDNS配置更新成功")
	c.JSON(http.StatusOK, gin.H{
		"message": "配置更新成功",
	})
}

// validateSingBoxConfig 验证Sing-Box配置
func (s *Server) validateSingBoxConfig(c *gin.Context) {
	var req struct {
		Content string `json:"content" binding:"required"`
	}
	
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": fmt.Sprintf("请求参数错误: %v", err),
		})
		return
	}
	
	// 使用临时文件进行验证
	tempConfig, err := s.configManager.ValidateConfigContent("sing-box", req.Content)
	if err != nil {
		utils.Logger.Errorf("Sing-Box配置验证失败: %v", err)
		c.JSON(http.StatusBadRequest, gin.H{
			"valid": false,
			"error": err.Error(),
		})
		return
	}
	
	utils.Logger.Info("Sing-Box配置验证成功")
	c.JSON(http.StatusOK, gin.H{
		"valid": true,
		"message": "配置验证通过",
		"config": tempConfig,
	})
}

// validateMosDNSConfig 验证MosDNS配置
func (s *Server) validateMosDNSConfig(c *gin.Context) {
	var req struct {
		Content string `json:"content" binding:"required"`
	}
	
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": fmt.Sprintf("请求参数错误: %v", err),
		})
		return
	}
	
	// 使用临时文件进行验证
	tempConfig, err := s.configManager.ValidateConfigContent("mosdns", req.Content)
	if err != nil {
		utils.Logger.Errorf("MosDNS配置验证失败: %v", err)
		c.JSON(http.StatusBadRequest, gin.H{
			"valid": false,
			"error": err.Error(),
		})
		return
	}
	
	utils.Logger.Info("MosDNS配置验证成功")
	c.JSON(http.StatusOK, gin.H{
		"valid": true,
		"message": "配置验证通过",
		"config": tempConfig,
	})
}

// getMosDNSLocalDNS 获取MosDNS本地DNS配置
func (s *Server) getMosDNSLocalDNS(c *gin.Context) {
	config, err := s.configManager.GetMosDNSLocalDNS()
	if err != nil {
		utils.Logger.Errorf("获取MosDNS本地DNS配置失败: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": fmt.Sprintf("获取配置失败: %v", err),
		})
		return
	}
	
	c.JSON(http.StatusOK, gin.H{
		"config": config,
	})
}

// updateMosDNSLocalDNS 更新MosDNS本地DNS配置
func (s *Server) updateMosDNSLocalDNS(c *gin.Context) {
	var req map[string]interface{}
	
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": fmt.Sprintf("请求参数错误: %v", err),
		})
		return
	}
	
	if err := s.configManager.UpdateMosDNSLocalDNS(req); err != nil {
		utils.Logger.Errorf("更新MosDNS本地DNS配置失败: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": fmt.Sprintf("更新配置失败: %v", err),
		})
		return
	}
	
	utils.Logger.Info("MosDNS本地DNS配置更新成功")
	c.JSON(http.StatusOK, gin.H{
		"message": "配置更新成功",
	})
}

// getMosDNSRemoteDNS 获取MosDNS远程DNS配置
func (s *Server) getMosDNSRemoteDNS(c *gin.Context) {
	config, err := s.configManager.GetMosDNSRemoteDNS()
	if err != nil {
		utils.Logger.Errorf("获取MosDNS远程DNS配置失败: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": fmt.Sprintf("获取配置失败: %v", err),
		})
		return
	}
	
	c.JSON(http.StatusOK, gin.H{
		"config": config,
	})
}

// updateMosDNSRemoteDNS 更新MosDNS远程DNS配置
func (s *Server) updateMosDNSRemoteDNS(c *gin.Context) {
	var req map[string]interface{}
	
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": fmt.Sprintf("请求参数错误: %v", err),
		})
		return
	}
	
	if err := s.configManager.UpdateMosDNSRemoteDNS(req); err != nil {
		utils.Logger.Errorf("更新MosDNS远程DNS配置失败: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": fmt.Sprintf("更新配置失败: %v", err),
		})
		return
	}
	
	utils.Logger.Info("MosDNS远程DNS配置更新成功")
	c.JSON(http.StatusOK, gin.H{
		"message": "配置更新成功",
	})
}

// getMosDNSRawConfig 获取MosDNS原始配置文件内容
func (s *Server) getMosDNSRawConfig(c *gin.Context) {
	configFiles := map[string]string{
		"forward_local": "/cus/mosdns/sub_config/forward_local.yaml",
		"forward_1":     "/cus/mosdns/sub_config/forward_1.yaml",
	}
	
	result := make(map[string]interface{})
	
	for name, path := range configFiles {
		if content, err := os.ReadFile(path); err == nil {
			result[name] = map[string]interface{}{
				"path":    path,
				"content": string(content),
				"exists":  true,
			}
		} else {
			result[name] = map[string]interface{}{
				"path":   path,
				"error":  err.Error(),
				"exists": false,
			}
		}
	}
	
	c.JSON(http.StatusOK, gin.H{
		"data": result,
	})
}

// getMosDNSParsedConfig 获取解析后的MosDNS配置
func (s *Server) getMosDNSParsedConfig(c *gin.Context) {
	localConfig, err := s.configManager.GetMosDNSLocalDNS()
	if err != nil {
		utils.Logger.Errorf("获取本地DNS配置失败: %v", err)
		localConfig = nil
	}
	
	remoteConfig, err := s.configManager.GetMosDNSRemoteDNS()
	if err != nil {
		utils.Logger.Errorf("获取远程DNS配置失败: %v", err)
		remoteConfig = nil
	}
	
	c.JSON(http.StatusOK, gin.H{
		"data": map[string]interface{}{
			"local":  localConfig,
			"remote": remoteConfig,
		},
	})
}

// updateMosDNSParsedConfig 更新解析后的MosDNS配置
func (s *Server) updateMosDNSParsedConfig(c *gin.Context) {
	var req struct {
		Type   string                 `json:"type"`   // "local" 或 "remote"
		Config map[string]interface{} `json:"config"`
	}
	
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "请求参数错误: " + err.Error(),
		})
		return
	}
	
	var err error
	if req.Type == "local" {
		err = s.configManager.UpdateMosDNSLocalDNS(req.Config)
	} else if req.Type == "remote" {
		err = s.configManager.UpdateMosDNSRemoteDNS(req.Config)
	} else {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "类型参数错误，必须是 local 或 remote",
		})
		return
	}
	
	if err != nil {
		utils.Logger.Errorf("更新MosDNS配置失败: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": fmt.Sprintf("更新配置失败: %v", err),
		})
		return
	}
	
	utils.Logger.Infof("MosDNS配置更新成功: %s", req.Type)
	c.JSON(http.StatusOK, gin.H{
		"message": "配置更新成功",
	})
}

// getStaticRoutes 获取静态路由表
func (s *Server) getStaticRoutes(c *gin.Context) {
	// 执行ip route show命令获取路由表
	output, err := utils.RunCommand("ip", "route", "show")
	if err != nil {
		utils.Logger.Errorf("获取路由表失败: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": fmt.Sprintf("获取路由表失败: %v", err),
		})
		return
	}
	
	// 解析路由表输出
	routes := parseRoutes(output)
	
	c.JSON(http.StatusOK, gin.H{
		"data": routes,
	})
}

// getNftablesRules 获取nftables防火墙规则
func (s *Server) getNftablesRules(c *gin.Context) {
	// 执行nft list ruleset命令获取规则
	output, err := utils.RunCommand("nft", "list", "ruleset")
	if err != nil {
		utils.Logger.Errorf("获取nftables规则失败: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": fmt.Sprintf("获取nftables规则失败: %v", err),
		})
		return
	}
	
	// 解析nftables输出
	rules := parseNftablesRules(output)
	
	c.JSON(http.StatusOK, gin.H{
		"data": rules,
	})
}

// parseRoutes 解析路由表输出
func parseRoutes(output string) []map[string]interface{} {
	lines := strings.Split(strings.TrimSpace(output), "\n")
	routes := make([]map[string]interface{}, 0)
	
	for _, line := range lines {
		if strings.TrimSpace(line) == "" {
			continue
		}
		
		fields := strings.Fields(line)
		if len(fields) < 3 {
			continue
		}
		
		route := map[string]interface{}{
			"destination": fields[0],
			"raw":        line,
		}
		
		// 解析路由信息
		for i, field := range fields {
			switch field {
			case "via":
				if i+1 < len(fields) {
					route["gateway"] = fields[i+1]
				}
			case "dev":
				if i+1 < len(fields) {
					route["interface"] = fields[i+1]
				}
			case "src":
				if i+1 < len(fields) {
					route["source"] = fields[i+1]
				}
			case "metric":
				if i+1 < len(fields) {
					route["metric"] = fields[i+1]
				}
			case "scope":
				if i+1 < len(fields) {
					route["scope"] = fields[i+1]
				}
			}
		}
		
		routes = append(routes, route)
	}
	
	return routes
}

// getServiceVersion 获取服务版本信息
func (s *Server) getServiceVersion(c *gin.Context) {
	serviceName := c.Param("service")
	
	var version string
	var branch string
	var versionPath string
	var err error
	
	switch serviceName {
	case "sing-box":
		versionPath = "/etc/sing-box/version"
		
		// 优先通过命令获取版本号
		if output, cmdErr := utils.RunCommand("sing-box", "version"); cmdErr == nil {
			// 解析sing-box version输出
			lines := strings.Split(output, "\n")
			for _, line := range lines {
				if strings.Contains(strings.ToLower(line), "version") {
					parts := strings.Fields(line)
					if len(parts) >= 2 {
						version = parts[len(parts)-1] // 取最后一个字段作为版本号
						break
					}
				}
			}
			if version == "" {
				// 如果没有找到version关键字，尝试解析第一行
				lines = strings.Split(strings.TrimSpace(output), "\n")
				if len(lines) > 0 && lines[0] != "" {
					version = strings.TrimSpace(lines[0])
				}
			}
		} else {
			err = cmdErr
		}
		
		// 读取分支信息
		if content, readErr := os.ReadFile(versionPath); readErr == nil {
			branch = strings.TrimSpace(string(content))
		}
		
	case "mosdns":
		versionPath = "/etc/mosdns/version"
		
		// 优先通过命令获取版本号
		if output, cmdErr := utils.RunCommand("mosdns", "version"); cmdErr == nil {
			version = strings.TrimSpace(output)
		} else {
			err = cmdErr
		}
		
		// 读取分支信息
		if content, readErr := os.ReadFile(versionPath); readErr == nil {
			branch = strings.TrimSpace(string(content))
		}
		
	default:
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "不支持的服务: " + serviceName,
		})
		return
	}
	
	// 检查服务是否安装
	if version == "" && err != nil {
		// 检查是否是"未找到可执行文件"的错误
		if strings.Contains(err.Error(), "executable file not found") || 
		   strings.Contains(err.Error(), "command not found") ||
		   strings.Contains(err.Error(), "not found in $PATH") {
			version = "未安装"
			utils.Logger.Infof("服务 %s 未安装", serviceName)
		} else {
			version = "未知版本"
			utils.Logger.Errorf("获取服务 %s 版本失败: %v", serviceName, err)
		}
	} else {
		utils.Logger.Infof("获取服务 %s 版本信息: %s, 分支: %s", serviceName, version, branch)
	}
	
	response := gin.H{
		"service": serviceName,
		"version": version,
	}
	
	if branch != "" && version != "未安装" {
		response["branch"] = branch
		response["branch_path"] = versionPath
	}
	
	// 只有在版本不是"未安装"时才显示错误信息
	if err != nil && version != "未安装" {
		response["error"] = err.Error()
	}
	
	c.JSON(http.StatusOK, response)
}

// parseNftablesRules 解析nftables规则输出
func parseNftablesRules(output string) map[string]interface{} {
	lines := strings.Split(output, "\n")
	result := map[string]interface{}{
		"raw":    output,
		"tables": make([]map[string]interface{}, 0),
	}
	
	var currentTable map[string]interface{}
	var currentChain map[string]interface{}
	
	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" || strings.HasPrefix(trimmed, "#") {
			continue
		}
		
		if strings.HasPrefix(trimmed, "table ") {
			// 新的表
			parts := strings.Fields(trimmed)
			if len(parts) >= 3 {
				currentTable = map[string]interface{}{
					"family": parts[1],
					"name":   parts[2],
					"chains": make([]map[string]interface{}, 0),
				}
				result["tables"] = append(result["tables"].([]map[string]interface{}), currentTable)
			}
		} else if strings.HasPrefix(trimmed, "chain ") {
			// 新的链
			parts := strings.Fields(trimmed)
			if len(parts) >= 2 && currentTable != nil {
				currentChain = map[string]interface{}{
					"name":  parts[1],
					"rules": make([]string, 0),
				}
				
				// 解析链的类型和钩子
				if strings.Contains(line, "type") {
					for i, part := range parts {
						if part == "type" && i+1 < len(parts) {
							currentChain["type"] = parts[i+1]
						}
						if part == "hook" && i+1 < len(parts) {
							currentChain["hook"] = parts[i+1]
						}
						if part == "priority" && i+1 < len(parts) {
							currentChain["priority"] = parts[i+1]
						}
					}
				}
				
				currentTable["chains"] = append(currentTable["chains"].([]map[string]interface{}), currentChain)
			}
		} else if currentChain != nil && (strings.Contains(trimmed, "accept") || strings.Contains(trimmed, "drop") || strings.Contains(trimmed, "jump") || strings.Contains(trimmed, "return") || strings.Contains(trimmed, "redirect")) {
			// 规则
			currentChain["rules"] = append(currentChain["rules"].([]string), trimmed)
		}
	}
	
	return result
}

// getUpdateInfo 获取更新信息
func (s *Server) getUpdateInfo(c *gin.Context) {
	serviceName := c.Param("service")
	
	// 验证服务名称
	if serviceName != "sing-box" && serviceName != "mosdns" {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "不支持的服务: " + serviceName,
		})
		return
	}
	
	updater := utils.NewCoreUpdater(serviceName)
	
	// 获取系统信息
	systemInfo := updater.GetSystemInfo()
	
	// 获取当前版本
	currentVersion, err := updater.GetCurrentVersion()
	if err != nil {
		utils.Logger.Errorf("获取当前版本失败: %v", err)
		currentVersion = "未知"
	}
	
	// 获取备份列表
	backups, err := updater.ListBackups()
	if err != nil {
		utils.Logger.Errorf("获取备份列表失败: %v", err)
		backups = []string{}
	}
	
	c.JSON(http.StatusOK, gin.H{
		"service":         serviceName,
		"current_version": currentVersion,
		"system_info":     systemInfo,
		"backups":         backups,
	})
}

// updateCore 更新内核
func (s *Server) updateCore(c *gin.Context) {
	serviceName := c.Param("service")
	
	// 验证服务名称
	if serviceName != "sing-box" && serviceName != "mosdns" {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "不支持的服务: " + serviceName,
		})
		return
	}
	
	// 解析请求参数
	var req struct {
		DownloadURL string `json:"download_url" binding:"required"`
	}
	
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "请求参数错误: " + err.Error(),
		})
		return
	}
	
	utils.Logger.Infof("开始更新 %s 内核，下载地址: %s", serviceName, req.DownloadURL)
	
	// 创建更新器并执行更新
	updater := utils.NewCoreUpdater(serviceName)
	result := updater.UpdateCore(req.DownloadURL)
	
	if result.Success {
		utils.Logger.Infof("成功更新 %s 内核: %s", serviceName, result.Message)
		c.JSON(http.StatusOK, result)
	} else {
		utils.Logger.Errorf("更新 %s 内核失败: %s", serviceName, result.Error)
		c.JSON(http.StatusInternalServerError, result)
	}
}

// getUpdateBackups 获取备份列表
func (s *Server) getUpdateBackups(c *gin.Context) {
	serviceName := c.Param("service")
	
	// 验证服务名称
	if serviceName != "sing-box" && serviceName != "mosdns" {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "不支持的服务: " + serviceName,
		})
		return
	}
	
	updater := utils.NewCoreUpdater(serviceName)
	backups, err := updater.ListBackups()
	if err != nil {
		utils.Logger.Errorf("获取备份列表失败: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": "获取备份列表失败: " + err.Error(),
		})
		return
	}
	
	c.JSON(http.StatusOK, gin.H{
		"service": serviceName,
		"backups": backups,
	})
}

// restoreFromBackup 从备份恢复
func (s *Server) restoreFromBackup(c *gin.Context) {
	serviceName := c.Param("service")
	
	// 验证服务名称
	if serviceName != "sing-box" && serviceName != "mosdns" {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "不支持的服务: " + serviceName,
		})
		return
	}
	
	// 解析请求参数
	var req struct {
		BackupPath string `json:"backup_path" binding:"required"`
	}
	
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "请求参数错误: " + err.Error(),
		})
		return
	}
	
	utils.Logger.Infof("开始从备份恢复 %s 内核: %s", serviceName, req.BackupPath)
	
	updater := utils.NewCoreUpdater(serviceName)
	if err := updater.RestoreFromBackup(req.BackupPath); err != nil {
		utils.Logger.Errorf("恢复 %s 内核失败: %v", serviceName, err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"error":   "恢复失败: " + err.Error(),
		})
		return
	}
	
	// 获取恢复后的版本
	newVersion, err := updater.GetCurrentVersion()
	if err != nil {
		utils.Logger.Warnf("获取恢复后版本失败: %v", err)
		newVersion = "未知"
	}
	
	utils.Logger.Infof("成功从备份恢复 %s 内核", serviceName)
	c.JSON(http.StatusOK, gin.H{
		"success":     true,
		"message":     fmt.Sprintf("成功从备份恢复 %s 内核", serviceName),
		"new_version": newVersion,
	})
}

// updateFromGitHub 从 GitHub Release 更新内核
func (s *Server) updateFromGitHub(c *gin.Context) {
	serviceName := c.Param("service")
	
	// 验证服务名称
	if serviceName != "sing-box" && serviceName != "mosdns" {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "不支持的服务: " + serviceName,
		})
		return
	}
	
	// 解析请求参数
	var req struct {
		ReleaseURL string `json:"release_url" binding:"required"`
	}
	
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "请求参数错误: " + err.Error(),
		})
		return
	}
	
	utils.Logger.Infof("开始从 GitHub Release 更新 %s 内核: %s", serviceName, req.ReleaseURL)
	
	// 创建更新器并执行更新
	updater := utils.NewCoreUpdater(serviceName)
	result := updater.UpdateFromGitHubRelease(req.ReleaseURL)
	
	if result.Success {
		utils.Logger.Infof("成功从 GitHub Release 更新 %s 内核: %s", serviceName, result.Message)
		c.JSON(http.StatusOK, result)
	} else {
		utils.Logger.Errorf("从 GitHub Release 更新 %s 内核失败: %s", serviceName, result.Error)
		c.JSON(http.StatusInternalServerError, result)
	}
}
