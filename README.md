# AimiliVPN 🌐

Bilingual: [中文](#中文) | [English](#english)

---

## 中文

[![Telegram](https://img.shields.io/badge/TG交流群-arestemple-2CA5E0?style=flat-square&logo=telegram&logoColor=white)](https://t.me/arestemple)
[![Forum](https://img.shields.io/badge/交流论坛-339936.xyz-orange?style=flat-square&logo=discourse&logoColor=white)](https://339936.xyz)
[![YouTube](https://img.shields.io/badge/视频教程-YouTube-red?style=flat-square&logo=youtube&logoColor=white)](https://www.youtube.com/watch?v=s-ATfXR8BpI)
[![Email](https://img.shields.io/badge/Bug反馈-yaohunse7@gmail.com-red?style=flat-square&logo=gmail&logoColor=white)](mailto:yaohunse7@gmail.com)

---

**AimiliVPN** 是一个专为 Linux VPS 设计的智能 VPN 代理网关管理器。它能够自动采集 VPNGate 开放节点，进行多线程可用性测试与延迟过滤，利用 OpenVPN 隧道与策略路由（Policy Routing）实现出站网络，并在本地提供高性能的 HTTP/SOCKS5 代理网关服务，非常适合用作 3x-ui / Xray 的落地出站代理，解锁流媒体与锁区网站。

---

### 🚀 快速开始 (一键部署)

只需一行命令，支持多种主流 Linux 发行版，自动识别并配置系统服务：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/baoweise-bot/aimili-vpngate/main/install.sh)
```

> **支持的操作系统**：
> - **Ubuntu / Debian** (Systemd)
> - **Alpine Linux** (OpenRC)
> - **CentOS / RHEL / Rocky Linux / AlmaLinux / Fedora** (Systemd)

---

### 🛠️ 快捷命令行管理工具 `ml`

安装完成后，直接在终端输入 `ml`（或 `ml status`）即可打开交互式菜单，或直接使用以下子命令：

- **`ml`** 或 **`ml status`**：查看运行状态（代理端口、活动节点、延迟、网页登录后台等）。
- **`ml start`** / **`ml stop`** / **`ml restart`**：启动/停止/重启服务。
- **`ml logs`**：查看实时运行日志。
- **`ml web`**：修改网页面板的绑定地址（如仅允许 127.0.0.1 本地或 0.0.0.0 公网访问）并随机重置安全后缀。
- **`ml port`** / **`ml password`**：修改网页管理端口及重置管理密码。
- **`ml update`**：一键检测并更新至远程最新源码。
- **`ml uninstall`**：完全卸载 AimiliVPN 并清理环境。

---

### 💡 小白避坑指南（常见问题解决）

#### 1. 极简系统缺少基础命令导致一键脚本报错
如果您的 VPS 是纯净版系统，可能会缺少 `curl`。请根据系统类型先运行以下命令安装：
- **Ubuntu/Debian**: `apt-get update && apt-get install -y curl ca-certificates`
- **Alpine**: `apk add curl ca-certificates`
- **CentOS/Rocky/Alma/Fedora**: `yum install -y curl ca-certificates`

#### 2. Ubuntu/Debian 系统提示包管理器被占用 (Apt Lock)
若安装时提示 `Could not get lock /var/lib/dpkg/lock-frontend` 等错误，可运行以下指令一键解锁后重新安装：
```bash
sudo systemctl stop unattended-upgrades 2>/dev/null
sudo killall apt apt-get dpkg 2>/dev/null
sudo rm -f /var/lib/dpkg/lock* /var/lib/apt/lists/lock /var/cache/apt/archives/lock
sudo dpkg --configure -a && sudo apt-get update
```

---

### ⚙️ 系统架构

```
   [ 3x-ui / Xray ] 
         │ (HTTP / SOCKS5)
         ▼
   [ 本地代理服务器 ] (Port 7928) ──(强制绑定 SO_BINDTODEVICE)──► [ tun0 虚拟网卡 ]
         │                                                            │
         │ (SSH, Web UI, etc. 依然走物理路由)                           │ (策略路由表 100)
         ▼                                                            ▼
   [ 物理网卡 eth0 ] ◄───────────────────────────────────────── [ OpenVPN 加密隧道 ]
         │                                                            │
         ▼ (真实服务器 IP 出站)                                         ▼ (VPNGate 落地节点出站)
    (国内直连流量)                                               (解锁流媒体、锁区网站)
```

---

## English

[![Telegram](https://img.shields.io/badge/Telegram-arestemple-2CA5E0?style=flat-square&logo=telegram&logoColor=white)](https://t.me/arestemple)
[![Forum](https://img.shields.io/badge/Forum-339936.xyz-orange?style=flat-square&logo=discourse&logoColor=white)](https://339936.xyz)
[![Email](https://img.shields.io/badge/Bug%20Report-yaohunse7@gmail.com-red?style=flat-square&logo=gmail&logoColor=white)](mailto:yaohunse7@gmail.com)

---

**AimiliVPN** is an intelligent VPN proxy gateway manager designed specifically for Linux VPS. It automatically collects open VPNGate nodes, conducts multi-threaded availability testing and latency filtering, establishes secure tunnels via OpenVPN and policy routing (to **prevent VPS lockout**), and hosts a high-performance local SOCKS5/HTTP proxy gateway. It is highly optimized to serve as a residential/unlocked egress node for upstream proxies like 3x-ui / Xray.

---

### 🚀 Quick Start (One-Click Deployment)

Copy and paste the command below to deploy AimiliVPN. The script will automatically detect your OS, install dependencies, and configure the background service:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/baoweise-bot/aimili-vpngate/main/install.sh)
```

> **Supported Operating Systems**:
> - **Ubuntu / Debian** (Systemd)
> - **Alpine Linux** (OpenRC)
> - **CentOS / RHEL / Rocky Linux / AlmaLinux / Fedora** (Systemd)

---

### 🛠️ CLI Helper Commands (`ml`)

Once installed, use the global command `ml` to launch the interactive helper menu, or use the shortcuts below:

- **`ml`** or **`ml status`**: Check system running status (active nodes, proxy ports, latency, URLs).
- **`ml start`** / **`ml stop`** / **`ml restart`**: Start/Stop/Restart the gateway service.
- **`ml logs`**: View real-time service logs.
- **`ml web`**: Toggle Web UI accessibility (127.0.0.1 or 0.0.0.0) and random-reset suffix paths.
- **`ml port`** / **`ml password`**: Update Web Console port and admin credentials.
- **`ml update`**: One-click check and update to the latest codebase.
- **`ml uninstall`**: Completely remove the service and repository files from your VPS.

---

### 💡 Troubleshooting & Pre-installation Guide

#### 1. Missing `curl` on Brand New Minimal OS
If the install command fails due to a missing `curl` utility, install it manually according to your OS:
- **Ubuntu/Debian**: `apt-get update && apt-get install -y curl ca-certificates`
- **Alpine**: `apk add curl ca-certificates`
- **CentOS/Rocky/Alma/Fedora**: `yum install -y curl ca-certificates`

#### 2. Package Manager Locked (`apt`/`dpkg` lock errors on Ubuntu/Debian)
If you see `Could not get lock /var/lib/dpkg/lock-frontend` error, run the following commands to unlock and retry:
```bash
sudo systemctl stop unattended-upgrades 2>/dev/null
sudo killall apt apt-get dpkg 2>/dev/null
sudo rm -f /var/lib/dpkg/lock* /var/lib/apt/lists/lock /var/cache/apt/archives/lock
sudo dpkg --configure -a && sudo apt-get update
```
