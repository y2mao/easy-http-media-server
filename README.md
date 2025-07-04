# HTTP Media Server v2

一个用Go语言编写的轻量级HTTP媒体服务器，可以通过Web界面浏览和访问本地文件目录，特别适合与Kodi等媒体播放器配合使用。

## 功能特性

- 🌐 基于HTTP的文件服务器
- 📁 美观的目录浏览界面
- 🎬 支持视频、音频、图片等多媒体文件
- 🔄 支持HTTP Range请求，兼容流媒体播放
- ⚙️ 通过YAML配置文件进行配置
- 🔒 路径安全检查，防止目录遍历攻击
- 📱 响应式设计，支持移动设备
- 🎯 完全兼容Kodi媒体播放器
- 🏥 健康检查端点，便于监控
- 📊 性能监控和测试工具
- 🐳 Docker支持，容器化部署
- 📝 详细的日志记录和错误处理

## 快速开始

### 1. 编译程序

```bash
go mod tidy
go build -o http-media-server
```

### 2. 生成默认配置文件

```bash
./http-media-server -gen-config
```

### 3. 编辑配置文件

编辑生成的 `config.yaml` 文件：

```yaml
server:
  port: 8080
  host: "0.0.0.0"

media:
  directory: "./media"
```

### 4. 启动服务器

```bash
./http-media-server
```

服务器启动后，访问 `http://localhost:8080` 即可浏览文件。

## 命令行选项

```bash
./http-media-server [选项]

选项:
  -config string
        配置文件路径 (默认 "config.yaml")
  -gen-config
        生成默认配置文件
  -help
        显示帮助信息
  -version
        显示版本信息
```

## 配置文件说明

配置文件使用YAML格式：

```yaml
# 服务器配置
server:
  # 监听端口
  port: 8080
  
  # 绑定地址
  # "0.0.0.0" - 监听所有网络接口
  # "127.0.0.1" - 仅监听本地回环接口
  host: "0.0.0.0"

# 媒体文件配置
media:
  # 媒体文件目录路径
  # 可以是绝对路径如 "/home/user/videos"
  # 或相对路径如 "./media"
  directory: "./media"
```

## 使用示例

### 基本使用

1. 将媒体文件放入 `media` 目录
2. 启动服务器：`./http-media-server`
3. 浏览器访问：`http://localhost:8080`

### 自定义配置

```bash
# 使用自定义配置文件
./http-media-server -config /path/to/custom-config.yaml

# 生成配置文件到指定位置
./http-media-server -gen-config -config /etc/media-server/config.yaml
```

### 与Kodi配合使用

1. 在Kodi中添加媒体源
2. 选择"添加网络位置"
3. 协议选择"HTTP"
4. 服务器地址：你的服务器IP
5. 端口：配置文件中设置的端口（默认8080）
6. 路径：留空或根据需要设置子目录

例如：`http://192.168.1.100:8080/`

## 支持的文件类型

### 视频文件
- MP4, AVI, MKV, MOV, WMV, FLV, WebM

### 音频文件  
- MP3, WAV, FLAC, AAC, OGG, M4A

### 图片文件
- JPG, JPEG, PNG, GIF, BMP, WebP

### 其他文件
- 所有其他文件类型都可以下载

## 网络访问

### 局域网访问

如果要让局域网内其他设备访问：

1. 确保配置文件中 `host` 设置为 `"0.0.0.0"`
2. 确保防火墙允许对应端口的连接
3. 使用服务器的局域网IP地址访问

### 端口转发

如果需要从互联网访问，需要在路由器上设置端口转发：

1. 登录路由器管理界面
2. 找到端口转发/虚拟服务器设置
3. 添加规则：外部端口 → 内部IP:端口

**安全提醒**：从互联网开放服务存在安全风险，建议使用VPN等更安全的方式。

## 安全特性

- ✅ 路径验证：防止目录遍历攻击
- ✅ 隐藏文件过滤：不显示以 `.` 开头的隐藏文件
- ✅ CORS支持：允许跨域访问
- ✅ 安全的文件服务：只能访问配置目录内的文件

## 故障排除

### 常见问题

**Q: 无法访问服务器**
- 检查防火墙设置
- 确认端口没有被其他程序占用
- 检查配置文件中的host和port设置

**Q: Kodi无法播放视频**
- 确认文件格式被Kodi支持
- 检查网络连接
- 尝试直接在浏览器中访问文件URL

**Q: 目录显示为空**
- 检查媒体目录路径是否正确
- 确认目录权限可读
- 查看服务器日志输出

### 日志信息

程序会输出详细的日志信息，包括：
- 服务器启动信息
- 每个HTTP请求
- 错误和警告信息

## 性能优化

- 使用SSD存储媒体文件可提高访问速度
- 对于大型媒体库，建议使用有线网络连接
- 可以通过反向代理（如nginx）来提供额外的缓存和压缩

## API端点

服务器提供以下API端点：

- `GET /` - 浏览文件和目录
- `GET /health` - 健康检查端点
- `GET /api/info` - 服务器信息API

### 健康检查

```bash
curl http://localhost:8080/health
```

返回示例：
```json
{
  "status": "healthy",
  "timestamp": "2024-01-15T10:30:00Z",
  "media_directory": "./media"
}
```

## Docker 部署

### 使用 Docker 构建和运行

```bash
# 构建镜像
docker build -t http-media-server .

# 运行容器
docker run -d \
  --name media-server \
  -p 8080:8080 \
  -v /path/to/your/media:/app/media:ro \
  -v /path/to/config.yaml:/app/config.yaml:ro \
  http-media-server
```

### 使用 Docker Compose

```bash
# 启动服务
docker-compose up -d

# 查看日志
docker-compose logs -f

# 停止服务
docker-compose down
```

## 实用脚本

项目包含多个实用脚本，位于 `scripts/` 目录：

### 备份脚本 (`scripts/backup.sh`)

```bash
# 完整备份
./scripts/backup.sh

# 仅备份配置
./scripts/backup.sh --config-only

# 压缩备份
./scripts/backup.sh --compress

# 预览备份内容
./scripts/backup.sh --dry-run
```

### 监控脚本 (`scripts/monitor.sh`)

```bash
# 启动监控
./scripts/monitor.sh

# 单次检查
./scripts/monitor.sh --once

# 后台监控
./scripts/monitor.sh --daemon

# 带邮件报警
./scripts/monitor.sh --email admin@example.com

# 带Webhook报警
./scripts/monitor.sh --webhook http://your-webhook-url
```

### 性能测试脚本 (`scripts/bench.sh`)

```bash
# 运行所有测试
./scripts/bench.sh --all-tests

# 创建测试文件
./scripts/bench.sh --create-test-files

# 目录浏览性能测试
./scripts/bench.sh --directory-test -c 20 -d 60

# 文件服务性能测试
./scripts/bench.sh --file-test --apache-bench
```

## 开发

### 项目结构

```
.
├── main.go                     # 程序入口点
├── config.go                   # 配置文件处理
├── server.go                   # HTTP服务器实现
├── config.yaml                 # 默认配置文件
├── go.mod                      # Go模块定义
├── Makefile                    # 构建脚本
├── Dockerfile                  # Docker镜像构建
├── docker-compose.yml          # Docker Compose配置
├── install.sh                  # Linux安装脚本
├── http-media-server.service   # systemd服务文件
├── scripts/                    # 实用脚本目录
│   ├── backup.sh              # 备份脚本
│   ├── monitor.sh             # 监控脚本
│   └── bench.sh               # 性能测试脚本
├── media/                      # 默认媒体目录
└── README.md                   # 项目文档
```

### 构建

使用 Makefile 进行构建：

```bash
# 查看所有可用命令
make help

# 安装依赖
make deps

# 构建当前平台
make build

# 构建所有平台
make build-all

# 运行程序
make run

# 生成配置文件
make config

# 创建发布包
make release

# 清理构建文件
make clean
```

手动构建：

```bash
# 本地构建
go build -o http-media-server

# 交叉编译 (Linux)
GOOS=linux GOARCH=amd64 go build -o http-media-server-linux

# 交叉编译 (Windows)
GOOS=windows GOARCH=amd64 go build -o http-media-server.exe
```

## 许可证

MIT License

## 贡献

欢迎提交Issue和Pull Request！

## 更新日志

### v2.0.0
- 重写项目架构
- 改进Web界面设计
- 增强Kodi兼容性
- 添加更多文件格式支持
- 优化性能和安全性
- 新增健康检查和API端点
- 添加Docker支持
- 集成监控和备份脚本
- 改进日志记录和错误处理
- 添加性能测试工具