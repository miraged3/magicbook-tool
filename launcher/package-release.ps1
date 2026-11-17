param(
    [ValidatePattern('^v[0-9]+\.[0-9]+\.[0-9]+$')]
    [string]$Tag,
    [string]$BuildDirectory = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$build = (Resolve-Path -LiteralPath $BuildDirectory).Path
$exe = Get-Item -LiteralPath (Join-Path $build 'HonorHardwareManager.exe')
$version = $exe.VersionInfo.ProductVersion
if ($version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+$') { throw "Invalid executable version: $version" }
if ($Tag -and $Tag -cne "v$version") { throw "Tag $Tag does not match executable version $version." }

$entries = [ordered]@{
    'HonorHardwareManager.exe' = $exe.FullName
    'Microsoft.Web.WebView2.Core.dll' = Join-Path $build 'Microsoft.Web.WebView2.Core.dll'
    'Microsoft.Web.WebView2.Wpf.dll' = Join-Path $build 'Microsoft.Web.WebView2.Wpf.dll'
    'WebView2Loader.dll' = Join-Path $build 'WebView2Loader.dll'
    'LICENSE' = Join-Path $build 'LICENSE'
    'ThirdParty/WebView2/LICENSE.txt' = Join-Path $build 'web\webview2\LICENSE.txt'
    'ThirdParty/WebView2/NOTICE.txt' = Join-Path $build 'web\webview2\NOTICE.txt'
}

$assets = Join-Path $build 'web-dist'
if (-not (Test-Path -LiteralPath (Join-Path $assets 'index.html') -PathType Leaf)) {
    throw 'Web UI is missing. Run build.ps1 first.'
}
foreach ($file in Get-ChildItem -LiteralPath $assets -Recurse -File) {
    $relativeName = $file.FullName.Substring($assets.Length + 1).Replace('\', '/')
    $entries["web-dist/$relativeName"] = $file.FullName
}

$web = Join-Path $build 'web'
Push-Location $web
try {
    $runtimePackages = @(node -e "const lock = require('./package-lock.json'); for (const [dir, pkg] of Object.entries(lock.packages)) if (dir && !pkg.dev) console.log(dir);")
    if ($LASTEXITCODE -ne 0) { throw 'Could not read npm lockfile.' }
} finally { Pop-Location }

# Include Tailwind's license and tslib, which npm also marks as a build dependency.
$sharedPackages = @('node_modules/tailwindcss', 'node_modules/tslib')
foreach ($package in ($runtimePackages + $sharedPackages | Sort-Object -Unique)) {
    if ($package -notmatch '^node_modules/(?:@[^/]+/)?[^/]+(?:/node_modules/(?:@[^/]+/)?[^/]+)*$' -or $package -match '[\\:]|(^|/)\.\.(/|$)') {
        throw "Unexpected package path in lockfile: $package"
    }
    $path = Join-Path $web $package
    if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw "Install npm dependency first: $package" }
    $notices = @(Get-ChildItem -LiteralPath $path -File | Where-Object {
        $_.Name -match '^(LICENSE|LICENCE|NOTICE|COPYING|CopyrightNotice)([.-].*)?$'
    })
    if ($notices.Count -eq 0) { throw "No license notice found for $package" }
    foreach ($notice in $notices) {
        $entries["ThirdParty/npm/$($package.Substring('node_modules/'.Length))/$($notice.Name)"] = $notice.FullName
    }
}

foreach ($inputFile in $entries.Values) {
    if (-not (Test-Path -LiteralPath $inputFile -PathType Leaf)) { throw "Missing release input: $inputFile" }
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$name = "HonorHardwareManager-v$version-windows-x64.zip"
$zip = Join-Path (Resolve-Path -LiteralPath $OutputDirectory).Path $name
$archive = [IO.Compression.ZipFile]::Open($zip, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($item in $entries.GetEnumerator()) {
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $archive, $item.Value, $item.Key, [IO.Compression.CompressionLevel]::Optimal
        ) | Out-Null
    }
} finally { $archive.Dispose() }

$hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText("$zip.sha256", ("$hash  $name" + [char]10), [Text.Encoding]::ASCII)
Write-Output $zip
Write-Output "$zip.sha256"
