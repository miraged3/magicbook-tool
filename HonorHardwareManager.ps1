Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    try {
        Start-Process powershell.exe -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $PSCommandPath + '"'))
    } catch {
        [System.Windows.Forms.MessageBox]::Show('需要管理员权限才能访问荣耀硬件接口。', '荣耀硬件助手') | Out-Null
    }
    exit
}

[System.Windows.Forms.Application]::EnableVisualStyles()
$backend = Join-Path $PSScriptRoot 'honor-charge.ps1'
if (-not (Test-Path -LiteralPath $backend)) {
    [System.Windows.Forms.MessageBox]::Show('找不到 honor-charge.ps1，请将它与本工具放在同一目录。', '荣耀硬件助手') | Out-Null
    exit
}

$form = New-Object System.Windows.Forms.Form
$form.Text = '荣耀硬件助手'
$form.ClientSize = New-Object System.Drawing.Size(680, 610)
$form.MinimumSize = New-Object System.Drawing.Size(696, 649)
$form.StartPosition = 'CenterScreen'
$form.BackColor = [Drawing.Color]::FromArgb(245,247,251)
$form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)

function Add-Label($parent, [string]$text, [int]$x, [int]$y, [int]$w, [int]$h, [int]$size=9, [bool]$bold=$false) {
    $label = New-Object Windows.Forms.Label
    $label.Text = $text; $label.Location = New-Object Drawing.Point($x,$y); $label.Size = New-Object Drawing.Size($w,$h)
    $style = if ($bold) { [Drawing.FontStyle]::Bold } else { [Drawing.FontStyle]::Regular }
    $label.Font = New-Object Drawing.Font('Microsoft YaHei UI', $size, $style)
    $label.ForeColor = [Drawing.Color]::FromArgb(39,48,65)
    $parent.Controls.Add($label)
    return $label
}
function Add-Card([int]$top, [int]$height) {
    $panel = New-Object Windows.Forms.Panel
    $panel.Location = New-Object Drawing.Point(24,$top); $panel.Size = New-Object Drawing.Size(632,$height)
    $panel.BackColor = [Drawing.Color]::White; $form.Controls.Add($panel)
    return $panel
}
function Add-Button($parent, [string]$text, [int]$x, [int]$y, [int]$w) {
    $button = New-Object Windows.Forms.Button
    $button.Text=$text; $button.Location=New-Object Drawing.Point($x,$y); $button.Size=New-Object Drawing.Size($w,34)
    $button.FlatStyle='Flat'; $button.FlatAppearance.BorderColor=[Drawing.Color]::FromArgb(210,218,231)
    $button.BackColor=[Drawing.Color]::FromArgb(248,250,253); $button.Cursor=[Windows.Forms.Cursors]::Hand
    $parent.Controls.Add($button); return $button
}
function Invoke-Backend([string[]]$arguments) {
    $parameters = @{}
    for ($i=0; $i -lt $arguments.Count; $i++) {
        $key = $arguments[$i].TrimStart('-')
        if ($key -in @('Get','Set','ThresholdOnly','GetLid','GetTouchpad')) {
            $parameters[$key] = $true
        } else {
            $i++
            if ($i -ge $arguments.Count) { throw "Missing value for $key" }
            $parameters[$key] = $arguments[$i]
        }
    }
    $output = & $backend @parameters 2>&1
    return (($output | Out-String).Trim())
}
function Show-Error($err) {
    $status.Text = '操作失败，请检查驱动与管理员权限'
    [Windows.Forms.MessageBox]::Show($form, ($err.Exception.Message + "`r`n`r`n请确认荣耀 WMI 驱动已安装。"), '操作失败', 'OK', 'Error') | Out-Null
}
function Refresh-Power {
    $power = [Windows.Forms.SystemInformation]::PowerStatus
    $battery = if ($power.BatteryLifePercent -ge 0) { '{0}%' -f [math]::Round($power.BatteryLifePercent * 100) } else { '未知' }
    $online = if ($power.PowerLineStatus -eq 'Online') { '已连接' } elseif ($power.PowerLineStatus -eq 'Offline') { '未连接' } else { '未知' }
    $state = '未知'
    try {
        $items = @(Get-CimInstance -Namespace root/wmi -ClassName BatteryStatus -ErrorAction Stop)
        if ($items.Count -gt 0) {
            if (@($items | Where-Object { $_.Charging -eq $true }).Count -gt 0) { $state = '充电中' }
            elseif (@($items | Where-Object { $_.Discharging -eq $true }).Count -gt 0) { $state = '放电中' }
            elseif (@($items | Where-Object { $_.Charging -eq $false -and $_.Discharging -eq $false }).Count -eq $items.Count) { $state = '未充电' }
        }
    } catch { $state = '未知' }
    $powerInfo.Text = "电池 $battery  ·  电源：$online  ·  状态：$state"
}
function Refresh-Hardware {
    $status.Text='正在读取状态...'; $form.Refresh()
    Refresh-Power
    try {
        $charge=Invoke-Backend @('-Get')
        if ($charge -match 'Low=(\d+) High=(\d+) Mode=(-?\d+)') {
            $low=[int]$Matches[1]; $high=[int]$Matches[2]; $mode=$Matches[3]
            $name = switch ("$low/$high") { '40/70' {'家庭模式'} '70/90' {'办公模式'} '95/100' {'旅行模式'} '0/100' {'无限充'} default {'未识别的组合'} }
            $chargeInfo.Text = "当前：$name  ·  恢复 $low% / 上限 $high%  ·  Mode $mode"
        } else { throw "充电状态读取失败：$charge" }
        $lid=Invoke-Backend @('-GetLid')
        $lidInfo.Text= if ($lid -match 'on \(1\)') {'当前：开启'} elseif ($lid -match 'off \(0\)') {'当前：关闭'} else {'当前：未知'}
        $pad=Invoke-Backend @('-GetTouchpad')
        $padInfo.Text= if ($pad -match 'on \(1\)') {'当前：开启'} elseif ($pad -match 'off \(0\)') {'当前：关闭'} else {'当前：未知'}
        $status.Text='状态已更新  ·  实际限充效果以充电状态为准'
    } catch { Show-Error $_ }
}
function Set-Device([string[]]$arguments, [string]$message) {
    try { $status.Text='正在设置...'; $form.Refresh(); $null=Invoke-Backend $arguments; $status.Text=$message; Refresh-Hardware }
    catch { Show-Error $_ }
}

$null=Add-Label $form '荣耀硬件助手' 24 18 400 36 18 $true
$powerInfo=Add-Label $form '正在读取电池状态' 26 58 450 22 9
$refresh=Add-Button $form '刷新状态' 548 24 108
$card=Add-Card 92 150
$null=Add-Label $card '电池充电模式' 18 14 300 25 12 $true
$chargeInfo=Add-Label $card '当前：正在读取' 19 48 590 25 9
$house=Add-Button $card '家庭 40–70%' 18 91 132
$work=Add-Button $card '办公 70–90%' 160 91 132
$travel=Add-Button $card '旅行 95–100%' 302 91 142
$full=Add-Button $card '不限充 0–100%' 454 91 155
$card2=Add-Card 254 100
$null=Add-Label $card2 '开盖开机' 18 12 200 25 12 $true
$lidInfo=Add-Label $card2 '当前：正在读取' 19 51 280 24
$lidOn=Add-Button $card2 '开启' 410 43 90
$lidOff=Add-Button $card2 '关闭' 510 43 90
$card3=Add-Card 366 100
$null=Add-Label $card3 '触摸屏' 18 12 200 25 12 $true
$null=Add-Label $card3 '开关可设置；当前状态暂无法可靠读取' 19 51 365 26
$touchOn=Add-Button $card3 '开启' 410 43 90
$touchOff=Add-Button $card3 '关闭' 510 43 90
$card4=Add-Card 478 91
$null=Add-Label $card4 '触控板' 18 10 200 25 12 $true
$padInfo=Add-Label $card4 '当前：正在读取' 19 45 280 24
$padOn=Add-Button $card4 '开启' 410 38 90
$padOff=Add-Button $card4 '关闭' 510 38 90
$status=Add-Label $form '准备就绪' 26 580 630 23

$refresh.Add_Click({ Refresh-Hardware })
$house.Add_Click({ Set-Device @('-Set','-ThresholdOnly','-Low','40','-High','70') '已设置家庭模式' })
$work.Add_Click({ Set-Device @('-Set','-ThresholdOnly','-Low','70','-High','90') '已设置办公模式' })
$travel.Add_Click({ Set-Device @('-Set','-ThresholdOnly','-Low','95','-High','100') '已设置旅行模式' })
$full.Add_Click({ Set-Device @('-Set','-ThresholdOnly','-Low','0','-High','100') '已取消限充' })
$lidOn.Add_Click({ Set-Device @('-SetLid','on') '已发送开盖开机设置' })
$lidOff.Add_Click({ Set-Device @('-SetLid','off') '已发送开盖开机设置' })
$touchOn.Add_Click({ Set-Device @('-SetTouch','on') '已发送触摸屏设置' })
$touchOff.Add_Click({ Set-Device @('-SetTouch','off') '已发送触摸屏设置' })
$padOn.Add_Click({ Set-Device @('-SetTouchpad','on') '已发送触控板设置' })
$padOff.Add_Click({ Set-Device @('-SetTouchpad','off') '已发送触控板设置' })
$powerTimer = New-Object Windows.Forms.Timer
$powerTimer.Interval = 10000
$powerTimer.Add_Tick({ Refresh-Power })
$form.Add_Shown({ Refresh-Hardware })
$form.Add_Shown({ $powerTimer.Start() })
$form.Add_FormClosed({ $powerTimer.Stop(); $powerTimer.Dispose() })
[void]$form.ShowDialog()
