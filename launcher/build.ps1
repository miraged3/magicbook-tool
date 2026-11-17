$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$framework = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
$wpf = Join-Path $framework 'WPF'
$package = Join-Path $root 'web\webview2'
if (-not (Test-Path (Join-Path $package 'lib\net462\Microsoft.Web.WebView2.Core.dll'))) { throw 'WebView2 SDK missing. Run launcher\setup-web.ps1 first.' }
Push-Location (Join-Path $root 'web')
try { npm run build; if ($LASTEXITCODE -ne 0) { throw 'Web build failed' } } finally { Pop-Location }
$core = Join-Path $package 'lib\net462\Microsoft.Web.WebView2.Core.dll'
$webwpf = Join-Path $package 'lib\net462\Microsoft.Web.WebView2.Wpf.dll'
Copy-Item $core,$webwpf -Destination $root -Force
Copy-Item (Join-Path $package 'runtimes\win-x64\native\WebView2Loader.dll') -Destination $root -Force
$output = Join-Path $root 'HonorHardwareManager.exe'
$sources = @('Program.cs','Hardware.cs','AppPreferences.cs','TrayIconResource.cs','WebWindow.cs') | ForEach-Object { Join-Path $root "wpf\$_" }
$arguments = @('/nologo','/target:winexe','/platform:x64','/codepage:65001','/reference:System.Windows.Forms.dll','/reference:System.Management.dll','/reference:System.Drawing.dll','/reference:System.Web.Extensions.dll',"/reference:$wpf\WindowsBase.dll","/reference:$wpf\PresentationCore.dll","/reference:$wpf\PresentationFramework.dll","/reference:$framework\System.Xaml.dll","/reference:$core","/reference:$webwpf","/win32manifest:$PSScriptRoot\app.manifest","/out:$output")
$icon = Join-Path $PSScriptRoot 'app.ico'
if (Test-Path -LiteralPath $icon) { $arguments += "/win32icon:$icon" }
$arguments += $sources
& $compiler $arguments
if ($LASTEXITCODE -ne 0) { throw "Build failed with exit code $LASTEXITCODE" }
Write-Host "Built $output"
