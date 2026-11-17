$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$web = Join-Path $root 'web'
Push-Location $web
try {
    npm ci
    if ($LASTEXITCODE -ne 0) { throw 'npm install failed' }
    $zip = Join-Path $web 'webview2.zip'
    Invoke-WebRequest 'https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/1.0.3537.50' -UseBasicParsing -OutFile $zip
    Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $web 'webview2') -Force
    Remove-Item -LiteralPath $zip
} finally { Pop-Location }
