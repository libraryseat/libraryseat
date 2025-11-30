# 项目完整文档

本文档整合了项目的所有重要信息，包括快速启动、环境配置、常见问题等。

---

## 📋 目录

1. [快速启动](#快速启动)
2. [环境配置](#环境配置)
3. [常用命令](#常用命令)
4. [真机运行](#真机运行)
5. [常见问题](#常见问题)
6. [项目结构](#项目结构)

---

## 🚀 快速启动

### 启动前准备

1. **检查环境**
   - ✅ Python 3.9+ 和 Conda 已安装
   - ✅ Flutter SDK 已安装
   - ✅ YOLOv11 权重文件已下载到 `libraryseat_backend/yolov11/weights/yolo11x.pt`

2. **创建测试用户（首次运行）**
   ```bash
   cd ~/Desktop/Fluuter/libraryseat_backend
   conda activate YOLO
   python -m backend.manage_users create --username admin --password 123456 --role admin
   python -m backend.manage_users create --username user --password 123456 --role student
   ```

### 启动步骤

#### 步骤 1: 启动后端服务器

打开**第一个终端窗口**：

```bash
# 1. 进入后端目录
cd ~/Desktop/Fluuter/libraryseat_backend

# 2. 激活 Conda 环境
conda activate YOLO

# 3. 启动服务器（开发模式，支持热重载，允许局域网访问）
python -m uvicorn backend.main:app --reload --host 0.0.0.0
```

**成功标志**：
```
INFO:     Uvicorn running on http://0.0.0.0:8000 (Press CTRL+C to quit)
INFO:     Started reloader process
INFO:     Started server process
INFO:     Application startup complete.
```

**验证后端**：
- 访问 http://localhost:8000/docs 查看 API 文档
- 访问 http://localhost:8000/health 检查健康状态

#### 步骤 2: 启动前端应用

打开**第二个终端窗口**（保持后端运行）：

```bash
# 1. 进入前端目录
cd ~/Desktop/Fluuter/libraryseat_frontend

# 2. 安装依赖（首次运行）
flutter pub get

# 3. 运行应用
flutter run
```

**选择运行设备**：
- 按 `1` 选择 Chrome（Web 浏览器）
- 按 `2` 选择 iOS 模拟器（如果已安装）
- 按 `3` 选择 Android 模拟器（如果已安装）
- 或连接真机设备

### 使用应用

**登录账号**：
- **管理员账号**: `admin` / `123456`
- **普通用户**: `user` / `123456`

**功能**：
- 查看楼层地图和座位状态
- 举报异常座位
- 管理员可以管理异常列表

---

## 🔧 环境配置

### macOS 后端环境配置

#### 前置要求
- macOS 操作系统
- 已安装 Homebrew（如果没有，先安装：`/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`）

#### 步骤 1: 安装 Conda

**使用 Homebrew 安装 Miniconda（推荐）**：
```bash
brew install miniconda
```

**或者下载安装包**：
访问 [Miniconda 官网](https://docs.conda.io/en/latest/miniconda.html) 下载 macOS 安装包并安装。

安装完成后，初始化 conda：
```bash
conda init zsh  # 如果使用 zsh（macOS 默认）
# 或
conda init bash  # 如果使用 bash
```

重新打开终端或运行：
```bash
source ~/.zshrc  # 或 source ~/.bash_profile
```

#### 步骤 2: 创建 Conda 环境并安装依赖

```bash
# 创建 Python 3.10 环境（推荐，兼容性更好）
conda create -n YOLO python=3.10 -y

# 激活环境
conda activate YOLO

# 更新 pip
pip install --upgrade pip

# 修复 requirements.txt 中的拼写错误（如果存在）
sed -i '' 's/altralytics/ultralytics/g' requirements.txt

# 安装依赖
cd ~/Desktop/Fluuter/libraryseat_backend
pip install -r requirements.txt
```

#### 步骤 3: 下载 YOLOv11 模型权重

```bash
# 创建权重目录
mkdir -p yolov11/weights

# 下载权重文件
cd yolov11/weights
curl -L -o v11_x.pt "https://github.com/Shohruh72/YOLOv11/releases/download/v1.0.0/v11_x.pt"

# 创建符号链接（如果需要）
ln -s v11_x.pt yolo11x.pt
cd ../..
```

#### 步骤 4: 创建必要的目录结构

```bash
mkdir -p config/floors config/report outputs yolov11/input
```

---

## 💻 常用命令

### 后端服务器命令

**启动服务器**：
```bash
cd ~/Desktop/Fluuter/libraryseat_backend
conda activate YOLO
python -m uvicorn backend.main:app --reload --host 0.0.0.0
```

**停止服务器**：
在运行服务器的终端按：`CTRL + C`

**查看服务器状态**：
```bash
curl http://localhost:8000/health
open http://localhost:8000/docs
```

### 用户管理命令

**创建用户**：
```bash
conda activate YOLO
python -m backend.manage_users create --username admin --password 123456 --role admin
python -m backend.manage_users create --username user --password 123456 --role student
```

**查看用户列表**：
```bash
python -m backend.manage_users list
```

**删除用户**：
```bash
python -m backend.manage_users delete --username <用户名>
```

### 前端开发命令

**启动 Flutter 应用**：
```bash
cd ~/Desktop/Fluuter/libraryseat_frontend
flutter run
```

**获取依赖**：
```bash
flutter pub get
```

**清理构建**：
```bash
flutter clean
flutter pub get
```

### 网络和 IP 命令

**查看 Mac 局域网 IP**：
```bash
ifconfig | grep "inet " | grep -v 127.0.0.1
```

**测试后端连接**：
```bash
curl http://localhost:8000/health
```

**查看端口占用**：
```bash
lsof -i :8000
kill -9 $(lsof -ti:8000)  # 杀死占用进程
```

---

## 📱 真机运行

### 快速启动步骤

#### 1. 启动后端服务器（重要：必须使用 --host 0.0.0.0）

```bash
cd ~/Desktop/Fluuter/libraryseat_backend
conda activate YOLO
python -m uvicorn backend.main:app --reload --host 0.0.0.0
```

**关键点**：
- ✅ 必须使用 `--host 0.0.0.0` 才能从真机访问
- ✅ 如果只使用 `--host 127.0.0.1` 或默认，真机无法连接

#### 2. 验证后端运行

在 Mac 上测试：
```bash
curl http://localhost:8000/health
# 应该返回: {"status":"ok"}
```

在真机上测试（使用浏览器）：
```
http://192.168.1.109:8000/health
```

#### 3. 启动 Flutter 应用

```bash
cd ~/Desktop/Fluuter/libraryseat_frontend
flutter run
```

**选择设备**：
- 连接真机后，按设备编号选择
- 确保 Mac 和真机在同一 Wi-Fi 网络

### 真机连接检查清单

启动前确认：
- [ ] Mac 和真机在同一 Wi-Fi 网络
- [ ] 后端使用 `--host 0.0.0.0` 启动
- [ ] 后端服务器正在运行（`lsof -ti:8000` 有输出）
- [ ] 前端 `api_config.dart` 中的 IP 是正确的（当前：`192.168.1.109`）
- [ ] 防火墙允许 8000 端口

### 如果 IP 地址变化

1. **获取新 IP**：
   ```bash
   ipconfig getifaddr en0 || ipconfig getifaddr en1
   ```

2. **更新配置文件**：
   - `libraryseat_frontend/lib/config/api_config.dart`
   
   将 IP 地址替换为新 IP

3. **重启应用**：
   - 停止后端服务器（Ctrl+C）
   - 重新启动后端
   - 重启 Flutter 应用

---

## ⚠️ 常见问题

### 后端无法启动

**错误**: `ModuleNotFoundError: No module named 'backend'`

**解决**:
1. 确保在 `libraryseat_backend` 目录下运行
2. 使用 `python -m uvicorn` 而不是直接 `uvicorn`
3. 确保已激活 `YOLO` conda 环境

### 前端无法连接后端

**错误**: "cannot connect to server check ip and cors"

**解决**:
1. 检查后端是否正在运行（访问 http://localhost:8000/health）
2. 如果使用真机，修改 `libraryseat_frontend/lib/config/api_config.dart`：
   ```dart
   static const String baseUrl = 'http://YOUR_MAC_IP:8000';
   ```
   例如：`http://192.168.1.109:8000`

### 端口被占用

**错误**: `Address already in use`

**解决**:
```bash
# 查找占用 8000 端口的进程
lsof -ti:8000

# 杀死进程
kill -9 $(lsof -ti:8000)
```

### Conda 命令未找到

**错误**: `conda: command not found`

**解决**:
```bash
# 初始化 conda
conda init zsh  # 或 conda init bash

# 重新加载配置
source ~/.zshrc  # 或 source ~/.bash_profile

# 重新打开终端
```

### 依赖安装失败

**问题：`ERROR: No matching distribution found for altralytics`**

这是拼写错误，应该是 `ultralytics`。修复方法：
```bash
# 修复 requirements.txt 中的拼写错误
sed -i '' 's/altralytics/ultralytics/g' requirements.txt

# 然后重新安装
pip install -r requirements.txt
```

**问题：bcrypt 版本兼容性错误**

如果遇到 `AttributeError: module 'bcrypt' has no attribute '__about__'`：
```bash
# 降级 bcrypt 到 3.x 版本（推荐）
pip install "bcrypt<4.0.0"
```

### 真机无法连接后端

**解决方案**：
1. 检查后端是否使用 `--host 0.0.0.0`
2. 检查 Mac 和真机是否在同一网络
3. 在真机浏览器访问 `http://YOUR_MAC_IP:8000/health` 测试

### 防火墙阻止连接

**解决方案**：
1. 系统偏好设置 > 安全性与隐私 > 防火墙
2. 允许 8000 端口的入站连接
3. 或临时关闭防火墙测试

---

## 📁 项目结构

```
Fluuter/
├── libraryseat_frontend/     # Flutter 前端应用
│   ├── lib/                  # Flutter 源代码
│   │   ├── pages/           # 页面文件
│   │   ├── models/          # 数据模型
│   │   └── config/          # 配置文件
│   └── ...
├── libraryseat_backend/      # FastAPI 后端服务
│   ├── backend/             # 后端源代码
│   │   ├── main.py         # 应用入口
│   │   ├── routes/         # API 路由
│   │   ├── services/       # 业务逻辑
│   │   └── models/         # 数据模型
│   ├── yolov11/            # YOLOv11 检测
│   │   └── weights/        # 模型权重
│   ├── config/             # 配置文件
│   └── tools/              # 工具脚本
└── README.md               # 项目说明
```

---

## 🛑 停止服务

### 停止后端
在运行后端的终端按 `Ctrl + C`

### 停止前端
在运行前端的终端按 `Ctrl + C` 或 `q`

---

## 📝 测试账号

| 用户名 | 密码 | 角色 | 说明 |
|--------|------|------|------|
| `admin` | `123456` | 管理员 | 可以查看异常座位、管理举报 |
| `user` | `123456` | 学生 | 普通用户，可以查看座位和举报 |

---

## 🔗 相关资源

- **后端仓库**: https://github.com/libraryseat/libraryseat.github.io
- **前端仓库**: https://github.com/libraryseat/libraryseat
- **API 文档**: http://localhost:8000/docs（启动后端后访问）

---

**提示**: 首次运行需要一些时间来初始化数据库和加载模型，请耐心等待。

