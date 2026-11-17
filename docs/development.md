# 从源码构建

需要 Windows x64、Windows PowerShell 5.1 和 Node.js 24（含 npm）。在仓库根目录运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\launcher\setup-web.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\launcher\build.ps1
```

第一步安装锁定版本的前端依赖并下载 WebView2 SDK。第二步构建前端和 Windows 桌面程序。生成的 EXE、WebView2 DLL 和 `web-dist/` 都位于仓库根目录，运行时请保留它们的相对位置。

重新构建前请退出正在运行的程序。如果窗口已隐藏到托盘，从托盘菜单选择「退出」。

- `wpf/` 包含 C# 窗口宿主、应用设置和 WMI 硬件接口。
- `web/` 包含 React、Tailwind CSS 和 Lucide 界面。
- `honor-charge.ps1` 是可选的 PowerShell 命令行工具，见[硬件与实测记录](hardware-notes.md)。
