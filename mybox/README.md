# MyBox v1.0.6

MyBox 是一个现代化的代理服务控制中心，专为管理 Sing-Box 和 MosDNS 服务而设计。提供直观的 Web 界面，支持配置管理、服务控制和实时监控。

## ✨ 版本特性

### v1.0.6 (2025-01-09)

#### 🚀 MosDNS远程访问增强
- **取消按钮**: 输入框旁新增取消按钮，支持快速清空输入内容
- **多地址管理**: 支持保存和管理多个MosDNS服务器地址
- **地址列表**: 显示所有已保存地址，支持一键切换和删除
- **当前使用显示**: 清楚标识当前正在使用的服务器地址
- **智能管理**: 防重复添加、自动切换、批量清理等功能

#### 🎨 用户体验优化
- **视觉层次**: 蓝色背景突出当前使用的地址
- **状态标识**: "使用中"和"(自定义)"标签提升可读性
- **动画效果**: 平滑的淡入淡出和滑动动画
- **响应式布局**: 适配移动端的按钮和间距设计

#### 🔧 技术改进
- **数据持久化**: LocalStorage自动保存多地址配置
- **向后兼容**: 自动迁移旧版本单IP配置到新系统
- **错误修复**: 修复Vue模板函数导出问题
- **状态同步**: 所有相关组件状态实时同步更新

### v1.0.5 (2025-01-09)

#### 🚀 重大功能更新
- **MosDNS WebUI 集成**: 在MosDNS管理页面添加WebUI和Web日志访问按钮
- **远程访问支持**: 支持配置自定义MosDNS服务器IP，访问远程服务器的WebUI和日志
- **服务控制集成**: 在Sing-Box和MosDNS管理页面直接添加启动、停止、重启按钮
- **菜单界面优化**: 紧凑化菜单设计，PC端和移动端显示一致性优化

#### 🔧 技术改进
- **CPU使用率修复**: 修复CPU使用率计算逻辑，增加边界检查和异常值处理
- **采样间隔优化**: CPU采样间隔从100ms增加到200ms，提高准确性
- **状态管理优化**: 改进服务状态显示和控制按钮的集成方式
- **UI/UX 改进**: 菜单宽度优化、图标对齐、响应式布局改进

#### 🌐 MosDNS 增强
- **WebUI 按钮**: 直接访问 `ip:9099/graphic` 管理界面
- **Web日志按钮**: 直接访问 `ip:9099/rlog` 日志界面
- **自定义IP配置**: 支持输入远程MosDNS服务器IP地址
- **智能按钮状态**: 根据MosDNS安装状态自动启用/禁用按钮

### v1.0.2 (2024-12-19)

#### 🚀 重大功能更新
- **撤销功能**: 添加配置撤销按钮，允许用户在保存配置后撤销更改
- **持久化撤销**: 撤销功能支持跨页面刷新，备份配置自动保存到localStorage
- **智能备份管理**: 24小时过期清理机制，避免累积无用数据
- **IP配置修复**: 修复路由规则IP配置验证问题，使用正确的`ip_cidr`字段格式
- **按钮状态优化**: 修复保存后按钮显示逻辑，用户体验更流畅

#### 🔧 技术改进
- **API端点修复**: 撤销功能使用正确的API端点和请求格式
- **状态管理**: 改进按钮显示逻辑，保存后"保存并重启"按钮保持可用
- **错误处理**: 增强配置验证和错误提示机制
- **代码简化**: 移除复杂的策略组自动配置，专注手动精确配置

### v1.0.1 (2024-12-19)

#### 🎯 核心功能
- **Web 管理界面**: 现代化的 Vue.js 单页应用
- **服务管理**: Sing-Box 和 MosDNS 服务的启动、停止、重启
- **配置管理**: 可视化编辑和管理配置文件
- **实时监控**: 服务状态监控和网络信息显示

#### 🚀 Sing-Box 管理
- **入站配置**: 显示所有入站配置（只读模式）
- **出站配置**: 完整的出站配置管理
  - 支持 Direct、Selector、URLTest 类型
  - 手动选择节点和策略组
  - 分组显示：代理节点、出站配置、系统出站
  - 智能防循环引用
- **路由规则**: 拖拽排序的路由规则管理
  - 系统规则锁定保护
  - 规则集管理集成
  - 双栏布局（规则 + 规则集）
- **代理节点**: 简化的 JSON 配置管理
- **DNS 配置**: 只读显示当前 DNS 设置
- **网络状态**: 实时显示路由表和防火墙规则

#### 🌐 MosDNS 管理
- **服务状态**: 显示 MosDNS 运行状态
- **配置说明**: 引导用户直接在服务器上管理配置

#### 🎨 用户界面
- **响应式设计**: 完美适配桌面端和移动端
- **隐藏式菜单**: 支持汉堡菜单（桌面+移动）
- **页面持久化**: 刷新页面保持当前位置
- **加载状态**: 按钮加载动画和禁用机制
- **双栏布局**: 路由规则和规则集的并列显示

#### 🔧 技术改进
- **版本显示**: 侧边栏显示版本号徽章
- **配置分离**: 保存配置和重启服务分离
- **错误处理**: 完善的错误提示和异常处理
- **性能优化**: 并行 API 调用和数据缓存

## 📦 安装部署

### 系统要求
- Linux 系统 (推荐 Ubuntu 20.04+)
- Root 权限
- 8080 端口可用


#### 访问Web界面
```
http://your-server-ip:8080
```

### 自定义端口
```bash
# 指定端口启动
sudo mybox server --port 8081
```

## 🚀 使用指南

### Web 界面功能

#### 📊 仪表盘
- 系统概览和服务状态
- 快速操作按钮
- 实时状态更新

#### 🚀 Sing-Box 管理
1. **入站配置**: 查看当前入站设置
2. **出站配置**: 
   - 点击"添加出站"创建新配置
   - 选择类型：Direct / Selector / URLTest
   - 手动选择节点和策略组
   - 支持系统出站（direct、block、dns-out）
3. **路由规则**:
   - 拖拽调整规则顺序
   - 系统规则自动锁定
   - 双栏查看规则和规则集
4. **代理节点**: JSON 模式编辑节点配置
5. **DNS 设置**: 查看当前 DNS 配置
6. **网络状态**: 查看路由表和防火墙规则

#### 🌐 MosDNS 管理
- 查看服务运行状态
- 配置文件直接在服务器编辑

### 命令行工具

```bash
# 查看版本信息
mybox version

# 查看服务状态
mybox status

# 服务管理
mybox start sing-box      # 启动 Sing-Box
mybox stop sing-box       # 停止 Sing-Box
mybox restart sing-box    # 重启 Sing-Box
mybox start mosdns        # 启动 MosDNS
mybox stop mosdns         # 停止 MosDNS
mybox restart mosdns      # 重启 MosDNS

# Web 服务器
mybox server              # 启动 Web 服务器 (端口 8080)
mybox server --port 8081  # 指定端口启动

# 帮助信息
mybox help
```

## 🎯 配置示例

### Selector 出站配置
```json
{
  "tag": "🇭🇰 香港节点",
  "type": "selector",
  "outbounds": ["节点1", "节点2", "direct"]
}
```

### URLTest 出站配置
```json
{
  "tag": "⚡ 自动选择",
  "type": "urltest",
  "outbounds": ["节点1", "节点2"],
  "url": "https://www.gstatic.com/generate_204",
  "interval": "300s"
}
```

### 路由规则配置
- 支持拖拽排序
- 系统规则自动保护
- 规则集集成管理

## 🔧 高级特性

### 响应式设计
- **桌面端**: 侧边栏导航 + 主内容区
- **移动端**: 汉堡菜单 + 全屏内容
- **自适应**: 自动检测设备类型切换布局

### 智能管理
- **防循环引用**: 出站配置自动排除当前编辑项
- **分组显示**: 代理节点、出站配置、系统出站分类
- **状态持久化**: 页面刷新保持当前位置

### 安全特性
- **Root 权限检查**: 确保足够权限管理系统服务
- **配置验证**: 保存前验证配置格式
- **系统规则保护**: 重要规则锁定防误删

## 🐛 问题排查

### 常见问题

1. **端口被占用**
   ```bash
   # 检查端口占用
   sudo netstat -tlnp | grep :8080
   
   # 使用其他端口
   sudo mybox server --port 8081
   ```

2. **权限不足**
   ```bash
   # 确保使用 root 权限
   sudo mybox
   ```

3. **服务启动失败**
   ```bash
   # 检查服务状态
   mybox status
   
   # 查看系统日志
   sudo journalctl -u sing-box -f
   sudo journalctl -u mosdns -f
   ```

4. **Web 界面访问问题**
   ```bash
   # 检查防火墙设置
   sudo ufw status
   sudo ufw allow 8080/tcp
   
   # 检查服务运行状态
   ps aux | grep mybox
   ```

## 📈 版本历史

### v1.0.6 (2025-01-09)
- ✅ 增强MosDNS远程访问配置，支持多地址管理
- ✅ 新增取消按钮和地址列表功能
- ✅ 优化用户界面，增加状态标识和动画效果
- ✅ 改进数据持久化和向后兼容性
- ✅ 修复Vue模板函数导出问题

### v1.0.5 (2025-01-09)
- ✅ 集成MosDNS WebUI和Web日志访问功能
- ✅ 添加远程MosDNS服务器IP配置支持
- ✅ 在服务管理页面直接集成启动、停止、重启按钮
- ✅ 优化菜单界面，实现紧凑化和一致性设计
- ✅ 修复CPU使用率计算问题，提高系统监控准确性
- ✅ 改进UI/UX，优化响应式布局和用户体验

### v1.0.2 (2024-12-19)
- ✅ 添加配置撤销功能，支持一键回退到保存前状态
- ✅ 实现撤销功能的localStorage持久化，刷新页面后仍可撤销
- ✅ 修复路由规则IP配置验证问题，使用正确的ip_cidr字段
- ✅ 优化按钮状态逻辑，保存后"保存并重启"按钮保持可用
- ✅ 增强错误处理和用户体验

### v1.0.1 (2024-12-19)
- ✅ 移除复杂的策略组自动配置选项
- ✅ 简化为纯手动选择模式
- ✅ 优化用户界面和交互体验
- ✅ 完善版本显示和文档

### v1.0.0 (2024-12-18)
- 🎉 首个正式版本发布
- ✅ 完整的 Sing-Box 和 MosDNS 管理功能
- ✅ 现代化 Web 界面
- ✅ 响应式设计支持

## 🤝 贡献指南

### 开发环境
```bash
# 克隆项目
git clone https://github.com/herozmy/StoreHouse.git
cd StoreHouse/mybox

# 查看支持的平台
./build.sh list

# 构建默认平台 (Linux AMD64 + ARM64)
./build.sh

# 构建单个平台
./build.sh single linux-amd64
./build.sh single linux-arm64

# 构建多个平台
./build.sh build linux-amd64 linux-arm64

# 构建所有支持的平台
./build.sh build-all

# 创建发布包
./build.sh package

# 运行测试
go test ./...
```

### 构建脚本说明

MyBox 提供了强大的多平台构建脚本 `build.sh`：

#### 支持的平台
- **Linux AMD64**: 传统x86_64服务器
- **Linux ARM64**: ARM架构服务器 (如树莓派4、Apple Silicon服务器等)
- **macOS AMD64**: Intel Mac (开发测试用)
- **macOS ARM64**: Apple Silicon Mac (开发测试用) 
- **Windows AMD64**: Windows服务器 (测试用)

#### 构建命令
```bash
# 查看帮助
./build.sh help

# 列出支持的平台
./build.sh list

# 默认构建 (Linux AMD64 + ARM64)
./build.sh

# 构建单个平台
./build.sh single <platform>

# 构建多个指定平台
./build.sh build <platform1> <platform2> ...

# 构建所有支持的平台
./build.sh build-all

# 创建发布包
./build.sh package

# 清理构建目录
./build.sh clean
```

#### 环境变量
```bash
# 指定版本号
VERSION=1.1.0 ./build.sh

# 示例：构建自定义版本的Linux平台
VERSION=1.1.0-beta ./build.sh build linux-amd64 linux-arm64
```

### 目录结构
```
mybox/
├── main.go                 # 主程序入口
├── build.sh               # 多平台构建脚本
├── internal/
│   ├── api/               # Web API 服务
│   ├── config/            # 配置管理
│   ├── service/           # 服务管理
│   ├── utils/             # 工具函数
│   └── embed/             # 嵌入资源
│       ├── web/           # Web 界面
│       └── config/        # 默认配置
├── build/
│   ├── dist/              # 构建的二进制文件
│   └── releases/          # 发布包
└── README.md              # 项目文档
```

## 📄 许可证

本项目采用 MIT 许可证，详见 [LICENSE](LICENSE) 文件。

## 🔗 相关链接

- **项目主页**: https://github.com/herozmy/StoreHouse
- **问题反馈**: https://github.com/herozmy/StoreHouse/issues
- **讨论区**: https://github.com/herozmy/StoreHouse/discussions

## 🙏 致谢

感谢以下开源项目的支持：
- [Sing-Box](https://github.com/SagerNet/sing-box) - 通用代理工具
- [MosDNS](https://github.com/IrineSistiana/mosdns) - DNS 转发器
- [Vue.js](https://vuejs.org/) - 前端框架
- [Gin](https://github.com/gin-gonic/gin) - Go Web 框架

---

**MyBox v1.0.6** - 让代理服务管理更简单 🚀