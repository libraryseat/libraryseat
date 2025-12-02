# Library Seat Management System

图书馆座位管理系统 - 完整的前后端项目

A complete full-stack application for managing library seats with real-time detection, reporting, and admin management features.

## 📋 项目概述 / Overview

本项目包含：
- **后端 (Backend)**: FastAPI + YOLOv11 座位检测系统
- **前端 (Frontend)**: Flutter 移动应用

This project includes:
- **Backend**: FastAPI + YOLOv11 seat detection system
- **Frontend**: Flutter mobile application

## 🏗️ 项目结构 / Project Structure

```
libraryseat/
├── backend/              # FastAPI 后端应用
│   ├── routes/          # API 路由
│   ├── services/        # 业务逻辑服务
│   ├── models.py        # 数据库模型
│   ├── schemas.py       # Pydantic 模式
│   └── main.py          # 应用入口
├── config/              # 配置文件
│   ├── floors/         # 楼层 ROI 配置
│   └── report/         # 举报图片存储
├── yolov11/            # YOLOv11 模型代码和权重
├── tools/              # 工具脚本
│   ├── annotate_roi.py # ROI 标注工具
│   └── export.py       # 数据导出工具
├── outputs/            # 导出数据
│   ├── YYYY-MM-DD/     # 每日导出
│   └── monthly/        # 每月导出
├── lib/                # Flutter 前端代码
│   ├── pages/         # 页面
│   ├── services/      # API 服务
│   ├── models/        # 数据模型
│   └── utils/         # 工具类
└── pubspec.yaml        # Flutter 依赖配置
```

## 🚀 快速开始 / Quick Start

### 后端启动 / Backend

```bash
# 1. 进入项目目录
cd BACKEND  # 或项目根目录

# 2. 创建并激活 Conda 环境
conda create -n YOLO python=3.9 -y
conda activate YOLO

# 3. 安装依赖
pip install -r requirements.txt

# 4. 下载 YOLOv11 权重文件
# 访问: https://github.com/ultralytics/assets/releases/download/v8.3.0/yolo11x.pt
# 保存到: yolov11/weights/yolo11x.pt

# 5. 创建测试用户
python -m backend.manage_users create --username admin --password 123456 --role admin
python -m backend.manage_users create --username user --password 123456 --role student

# 6. 启动服务器
uvicorn backend.main:app --reload --host 0.0.0.0
```

服务器将在 `http://localhost:8000` 启动，API 文档可在 `http://localhost:8000/docs` 查看。

### 前端启动 / Frontend

```bash
# 1. 进入前端目录（如果前端代码在单独目录）
cd FRONTEND  # 或项目根目录

# 2. 安装依赖
flutter pub get

# 3. 运行应用
flutter run
```

**注意**: 确保后端服务器已启动，前端才能正常工作。

## ✨ 功能特性 / Features

### 用户功能 / User Features
- ✅ 用户登录和注册
- ✅ 楼层地图可视化
- ✅ 实时座位状态查看
- ✅ 座位举报功能（支持文字和图片）
- ✅ 多语言支持（English / 简体中文 / 繁體中文）

### 管理员功能 / Admin Features
- ✅ 异常座位列表管理
- ✅ 举报详情查看（文字、图片）
- ✅ 确认/清除异常座位
- ✅ 座位锁定功能（5分钟）
- ✅ 楼层刷新功能
- ✅ 可疑座位标记（仅管理员可见）

### 后端功能 / Backend Features
- ✅ YOLOv11 实时座位检测
- ✅ 自动定时刷新（默认60秒）
- ✅ 每日/每月数据导出
- ✅ JWT 身份认证
- ✅ RESTful API
- ✅ CORS 支持

## 🎨 颜色规则 / Color Rules

### 座位颜色（学生视角）
- 🟢 **绿色** (#60D937): 空闲座位（无插座）
- 🔵 **蓝色** (#00A1FF): 空闲座位（有插座）
- ⚫ **灰色** (#929292): 已占用
- 🟡 **黄色** (#FEAE03): 可疑占座（仅管理员可见）

### 楼层颜色
- 🟢 **绿色**: 空座率 > 50%
- 🟡 **黄色**: 空座率 0-50%
- 🔴 **红色**: 空座率 = 0%

## 📡 API 端点 / API Endpoints

### 认证 / Authentication
- `POST /auth/login` - 用户登录
- `POST /auth/register` - 用户注册
- `GET /auth/me` - 获取当前用户信息

### 座位和楼层 / Seats and Floors
- `GET /seats` - 获取座位列表（可选楼层筛选）
- `GET /seats/{seatId}` - 获取单个座位信息
- `GET /floors` - 获取楼层摘要
- `POST /floors/{floor}/refresh` - 手动刷新楼层

### 举报 / Reports
- `POST /reports` - 提交座位举报（支持文字和图片）

### 管理员 / Admin (需要管理员权限)
- `GET /admin/anomalies` - 获取异常座位列表
- `GET /admin/reports/{report_id}` - 获取举报详情
- `POST /admin/reports/{report_id}/confirm` - 确认/取消异常
- `DELETE /admin/anomalies/{seat_id}` - 清除异常
- `POST /admin/seats/{seat_id}/lock` - 锁定座位

### 其他 / Others
- `GET /health` - 健康检查
- `GET /stats/seats/{seatId}` - 座位统计信息

完整 API 文档: `http://localhost:8000/docs` (Swagger UI)

## 🛠️ 工具 / Tools

### ROI 标注工具
用于标注座位的 ROI（感兴趣区域）：

```bash
python -m tools.annotate_roi --video {video_path} --floor-id F1 --out config/floors/F1.json
```

**操作说明**:
- 左键: 添加点
- 右键: 删除最后一个点
- Enter: 完成当前多边形并输入座位信息
- N: 清除当前多边形
- S: 保存为 JSON
- Q: 退出

### 数据导出工具
手动生成每日/每月统计数据：

```bash
python tools/export.py
```

## ⚙️ 配置 / Configuration

### 环境变量
- `REFRESH_INTERVAL_SECONDS`: 楼层刷新间隔（秒），默认 60
- `JWT_SECRET_KEY`: JWT 签名密钥，默认 `dev-secret-change`
- `JWT_ALGORITHM`: JWT 算法，默认 `HS256`
- `JWT_EXPIRE_MINUTES`: Token 过期时间（分钟），默认 120

### 目录结构
- `config/floors/`: 楼层 ROI JSON 配置文件
- `config/report/`: 举报图片存储目录
- `outputs/`: 数据导出目录
- `yolov11/weights/`: YOLO 模型权重文件

## 📱 前端配置 / Frontend Configuration

前端 API 配置位于 `lib/config/api_config.dart`:

```dart
class ApiConfig {
  // 本地开发
  static const String baseUrl = 'http://localhost:8000';
  
  // 真机测试（使用 Mac 的局域网 IP）
  // static const String baseUrl = 'http://192.168.1.105:8000';
}
```

## 👥 用户管理 / User Management

数据库在首次运行时自动创建。使用 CLI 管理用户：

```bash
# 创建用户
python -m backend.manage_users create --username admin --password 123456 --role admin

# 重置密码
python -m backend.manage_users passwd --username admin --password 654321

# 更改角色
python -m backend.manage_users role --username user --role student

# 列出所有用户
python -m backend.manage_users list
```

## 🔄 定时任务 / Scheduling

- **楼层刷新**: 每 60 秒自动刷新一次（可通过环境变量配置）
- **每日导出**: 每天 00:00 自动导出数据并重置计数器
- **每月导出**: 每月第一天 00:00 导出上月数据并重置月度计数器
- **离线处理**: 启动时检查离线期间是否跨日/跨月，自动执行相应导出

## 📚 文档 / Documentation

项目根目录包含详细文档：
- `COMMANDS.md` - 常用命令速查
- `BACKEND_SETUP_MACOS.md` - macOS 环境配置
- `WINDOWS_SETUP.md` - Windows 环境配置
- `START_SERVER.md` - 服务器启动指南
- `FRONTEND_TEST_GUIDE.md` - 前端测试指南
- `GIT_UPDATE_GUIDE.md` - Git 更新指南
- `REGISTER_FEATURE.md` - 注册功能文档

## 🧪 测试账号 / Test Accounts

默认测试账号：
- **管理员**: `admin` / `123456`
- **普通用户**: `user` / `123456`

## 🔧 技术栈 / Tech Stack

### 后端
- FastAPI - Web 框架
- SQLAlchemy - ORM
- YOLOv11 - 目标检测
- SQLite - 数据库
- APScheduler - 定时任务

### 前端
- Flutter - 跨平台框架
- Dio - HTTP 客户端
- SharedPreferences - 本地存储

## 📝 API 使用示例 / API Usage Examples

### 登录
```bash
curl -X POST \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin&password=123456" \
  http://localhost:8000/auth/login
```

### 获取座位列表
```bash
curl -H "Authorization: Bearer YOUR_TOKEN" \
  http://localhost:8000/seats?floor=F1
```

### 提交举报
```bash
curl -X POST \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -F "seat_id=F1-01" \
  -F "reporter_id=1" \
  -F "text=占座" \
  -F "images=@/path/to/image.jpg" \
  http://localhost:8000/reports
```

## 🤝 贡献者 / Contributors

- @chengu-123 - Chenhao Guan
- @HongtianChan - Hongtian Chan

## 📄 许可证 / License

本项目为团队项目，版权归 libraryseat 组织所有。

---

**注意**: 首次运行前请确保：
1. ✅ 已安装 Python 3.9+ 和 Conda
2. ✅ 已下载 YOLOv11 权重文件
3. ✅ 已创建至少一个管理员账号
4. ✅ 已配置楼层 ROI 文件（如需要）

更多详细信息请参考项目文档。
