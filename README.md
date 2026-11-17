# MagicBook Tool · 荣耀硬件助手

适用于部分荣耀 MagicBook 笔记本的 Windows 桌面工具，用于查看电池状态、切换充电模式和管理常用硬件开关。

[下载 Windows x64 版](https://github.com/miraged3/magicbook-tool/releases) · [反馈问题](https://github.com/miraged3/magicbook-tool/issues)

## 功能

- **充电设置**：查看电量和充电阈值，切换家庭、办公、旅行或不限充模式。
- **其他设置**：控制开盖开机、触控板和触摸屏。
- **应用设置**：可选开机自动启动、关闭窗口时隐藏到托盘，支持明暗主题。

## 下载与使用

1. 在 [Releases](https://github.com/miraged3/magicbook-tool/releases) 的 Assets 中下载 `HonorHardwareManager-v*-windows-x64.zip`，并完整解压。
2. 双击解压目录里的 `HonorHardwareManager.exe`，按 Windows 提示以管理员权限启动。

需要 Windows x64、.NET Framework 4.6.2 或更新版本、[Microsoft Edge WebView2 Runtime](https://developer.microsoft.com/en-us/microsoft-edge/webview2/) 和适配机型的荣耀 WMI 桥接驱动。驱动请从设备厂商官方渠道获取。

想先看界面，可以在解压目录运行 `.\HonorHardwareManager.exe --demo`，使用模拟数据体验。

## 兼容性

目前仅在 **荣耀 MagicBook Pro 14 2025 款触屏版（型号 FMB-P，Intel Core Ultra 5 225H，32 GB 内存，1 TB 存储）** 上做过部分实测，其他配置及机型尚未验证。详见[硬件与实测记录](docs/hardware-notes.md)。本项目与荣耀官方无关。

## 源码与许可

[源码构建说明](docs/development.md) · [MIT 许可证](LICENSE)
