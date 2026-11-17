# Honor hardware control tool (standalone, no Honor PC Manager needed).
# Supports:
#   1. Battery charge threshold (电池充电阈值):
#        .\honor-charge.ps1 -Get
#        .\honor-charge.ps1 -Set -Low 70 -High 80
#   2. Power on lid open (开盖开机):
#        .\honor-charge.ps1 -GetLid
#        .\honor-charge.ps1 -SetLid on|off
#   3. Touchscreen switch (触摸屏开关):
#        .\honor-charge.ps1 -GetTouch
#        .\honor-charge.ps1 -SetTouch on|off
#   4. Touchpad EC switch (触控板开关):
#        .\honor-charge.ps1 -GetTouchpad
#        .\honor-charge.ps1 -SetTouchpad on|off
#   5. Query all statuses (查询全部状态):
#        .\honor-charge.ps1 -GetAll
#
# Run PowerShell as Administrator.

param(
  [switch]$Get,
  [switch]$Set,
  [switch]$ThresholdOnly,
  [int]$Low,
  [int]$High,
  [ValidateRange(1,6)]
  [int]$Mode = 0,
  [switch]$GetLid,
  [ValidateSet('on','off','1','0')]
  [string]$SetLid,
  [switch]$GetTouch,
  [ValidateSet('on','off','1','0')]
  [string]$SetTouch,
  [switch]$GetTouchpad,
  [ValidateSet('on','off','1','0')]
  [string]$SetTouchpad,
  [switch]$GetAll
)

$ErrorActionPreference = 'Stop'

function Invoke-HonorWmi([byte[]]$cmd) {
  $in = New-Object byte[] 64
  [Array]::Copy($cmd, $in, $cmd.Length)
  $inst = Get-CimInstance -Namespace root/wmi -ClassName OemWMIMethod | Select-Object -First 1
  if (-not $inst) {
    throw "OemWMIMethod not found in root\wmi. Ensure HNOs2Ec10x64.sys driver is installed and run as Administrator."
  }
  $r = Invoke-CimMethod -InputObject $inst -MethodName OemWMIfun -Arguments @{ u8Input = [byte[]]$in }
  return ,[byte[]]$r.u8Output
}

function ConvertTo-EnableByte([string]$val) {
  if ($val -in @('on', '1')) { return [byte]1 }
  return [byte]0
}

function Sync-HonorChargeRegistry([int]$targetMode) {
  # SmartChargePlugin.dll (SmartChargeEvent::StartMonitor @ 0x180013696) reads
  # HKLM\Software\PCManager\MBAPowerManager on startup and sends 03 15 <savedMode> 0x48 <Low> <High> to EC.
  # Syncing this registry key prevents Honor PC Manager (if still installed) from reverting EC to Mode 1.
  $regPath = 'HKLM:\Software\PCManager\MBAPowerManager'
  if (Test-Path $regPath) {
    $enabled = if ($targetMode -gt 3 -and $targetMode -lt 7) { 1 } else { 0 }
    Set-ItemProperty -Path $regPath -Name 'SmartChargeMode' -Value "$targetMode" -Type String -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $regPath -Name 'PowerSafeManagerStatus' -Value "$enabled" -Type String -ErrorAction SilentlyContinue
  }
  $cuPath = 'HKCU:\Software\PCManager\MBAPowerManager'
  if (Test-Path $cuPath) {
    $enabledDword = if ($targetMode -gt 3 -and $targetMode -lt 7) { 1 } else { 0 }
    Set-ItemProperty -Path $cuPath -Name 'PowerSafeManagerStatus' -Value $enabledDword -Type DWord -ErrorAction SilentlyContinue
  }
}

$didAction = $false

# 1. Battery Charge Threshold & EC Smart Charge Mode
#    - HardwareHal.dll       : Get Threshold = 0x1103 (03 11), Set Threshold = 0x1003 (03 10 <Low> <High>)
#    - SmartChargePlugin.dll : Get Mode      = 0x1603 (03 16), Set Mode+Thr  = 0x1503 (03 15 <Mode> 0x48 <Low> <High>)
# Mode semantics vary by firmware. On the tested device 1 and 2 correlated with 40/70 and 70/90.
if ($Get -or $GetAll) {
  $didAction = $true
  $o = Invoke-HonorWmi @(0x03, 0x11)
  if ($o[0] -ne 0) { throw "Get charge threshold failed, WMI status code $($o[0])" }
  $m = Invoke-HonorWmi @(0x03, 0x16)
  $ecMode = if ($m[0] -eq 0) { $m[1] } else { -1 }
  $modeDesc = switch ($ecMode) {
    1 { 'Mode 1; observed with 40/70 on tested device' }
    2 { 'Mode 2; observed with 70/90 on tested device' }
    0 { 'Mode 0; observed with non-preset thresholds on tested device' }
    -1 { 'Mode query failed' }
    default { "Mode $ecMode; meaning unverified" }
  }
  $modeDesc += '; actual charge limiting requires verification'
  if ($GetAll) {
    "ChargeThreshold : Low=$($o[1])% High=$($o[2])% [$modeDesc]"
  } else {
    "Low=$($o[1]) High=$($o[2]) Mode=$ecMode ($modeDesc)"
  }
}

if ($Set) {
  $didAction = $true
  if ($Low -lt 0 -or $High -gt 100 -or $Low -gt $High) {
    throw "Need 0 <= Low <= High <= 100"
  }
  # Determine EC SmartChargeMode:
  #   Mode 4 = Smart Charge / threshold limit active (3 < mode < 7 in SmartChargePlugin.dll)
  #   Mode 1 = Smart Charge disabled / full charge to 100% (0 < mode <= 3)
  $targetMode = if ($Mode -ge 1 -and $Mode -le 6) {
    $Mode
  } elseif ($High -lt 100 -or $Low -gt 0) {
    4
  } else {
    1
  }

  # Step 1: Send SmartChargePlugin.dll command 03 15 <Mode> 0x48 <Low> <High> (0x180020fc0)
  #         Firmware behavior varies; successful return does not prove enforcement.
  if (-not $ThresholdOnly) {
    $oMode = Invoke-HonorWmi @(0x03, 0x15, [byte]$targetMode, 0x48, [byte]$Low, [byte]$High)
    if ($oMode[0] -ne 0) { throw "Set EC Smart Charge mode (03 15) failed, WMI status code $($oMode[0])" }
  }

  # Step 2: Send HardwareHal.dll command 03 10 <Low> <High> (0x180013f80)
  #         Ensures custom Low/High registers are also updated directly.
  $oThr = Invoke-HonorWmi @(0x03, 0x10, [byte]$Low, [byte]$High)
  if ($oThr[0] -ne 0) { throw "Set charge threshold (03 10) failed, WMI status code $($oThr[0])" }

  # Step 3: Sync registry so Honor PC Manager (if running) won't overwrite EC back to Mode 1.
  if (-not $ThresholdOnly) { Sync-HonorChargeRegistry -targetMode $targetMode }

  if ($ThresholdOnly) {
    "Threshold command accepted: Low=$Low High=$High. No separate mode command or registry write; firmware may change mode. Actual charge limiting is not verified."
  } else {
    "Commands accepted: Low=$Low High=$High requested Mode=$targetMode. Actual charge limiting is not verified."
  }
}

# 2. Power On Lid Open / 开盖开机 (MonPowerPlugin.dll: Get=0x1E06, Set=0x1D06)
if ($GetLid -or $GetAll) {
  $didAction = $true
  $o = Invoke-HonorWmi @(0x06, 0x1E)
  if ($o[0] -ne 0) { throw "Get lid-open power-on status failed, WMI status code $($o[0])" }
  $state = if ($o[1] -eq 1) { "on (1)" } else { "off ($($o[1]))" }
  "LidOpenPowerOn  : $state"
}

if ($PSBoundParameters.ContainsKey('SetLid')) {
  $didAction = $true
  $en = ConvertTo-EnableByte $SetLid
  $o = Invoke-HonorWmi @(0x06, 0x1D, $en)
  if ($o[0] -ne 0) { throw "Set lid-open power-on failed, WMI status code $($o[0])" }
  "OK: LidOpenPowerOn=$(if ($en -eq 1) { 'on' } else { 'off' })"
}

# 3. Touchscreen Switch: 02 15 sets state; a reliable read command is not known.
# A present/started touchscreen HID device does not imply touch is enabled.
if ($GetTouch -or $GetAll) {
  $didAction = $true
  "Touchscreen     : unknown (no verified state query; HID presence is not reliable)"
}

if ($PSBoundParameters.ContainsKey('SetTouch')) {
  $didAction = $true
  $en = ConvertTo-EnableByte $SetTouch
  $o = Invoke-HonorWmi @(0x02, 0x15, $en)
  if ($o[0] -ne 0) { throw "Set touchscreen failed, WMI status code $($o[0])" }
  "OK: Touchscreen=$(if ($en -eq 1) { 'on' } else { 'off' })"
}

# 4. Touchpad EC Switch / 触控板开关 (MagicTouchPadPlugin.dll: Get=0x0F02, Set=0x1002)
if ($GetTouchpad -or $GetAll) {
  $didAction = $true
  $o = Invoke-HonorWmi @(0x02, 0x0F)
  if ($o[0] -ne 0) { throw "Get touchpad status failed, WMI status code $($o[0])" }
  $state = if ($o[1] -eq 1) { "on (1)" } else { "off ($($o[1]))" }
  "Touchpad        : $state"
}

if ($PSBoundParameters.ContainsKey('SetTouchpad')) {
  $didAction = $true
  $en = ConvertTo-EnableByte $SetTouchpad
  $o = Invoke-HonorWmi @(0x02, 0x10, $en)
  if ($o[0] -ne 0) { throw "Set touchpad failed, WMI status code $($o[0])" }
  "OK: Touchpad=$(if ($en -eq 1) { 'on' } else { 'off' })"
}

if (-not $didAction) {
  @"
Usage (run PowerShell as Administrator):
  .\honor-charge.ps1 -GetAll                     # Query all statuses
  .\honor-charge.ps1 -Get                        # Query battery charge threshold
  .\honor-charge.ps1 -Set -Low 70 -High 80       # Set battery charge threshold (70% start, 80% stop)
  .\honor-charge.ps1 -Set -ThresholdOnly -Low 40 -High 70 # Set threshold only
  .\honor-charge.ps1 -Set -Low 0  -High 100      # Restore full charging (0% - 100%)
  .\honor-charge.ps1 -GetLid                     # Query power-on-lid-open (开盖开机)
  .\honor-charge.ps1 -SetLid on|off              # Enable/disable power-on-lid-open
  .\honor-charge.ps1 -GetTouch                   # Query touchscreen status (触摸屏状态)
  .\honor-charge.ps1 -SetTouch on|off            # Enable/disable touchscreen (触摸屏开关)
  .\honor-charge.ps1 -GetTouchpad                # Query touchpad EC status (触控板状态)
  .\honor-charge.ps1 -SetTouchpad on|off         # Enable/disable touchpad via EC
"@
}
