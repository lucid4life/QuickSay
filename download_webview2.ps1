# Download WebView2 Evergreen Bootstrapper
$ErrorActionPreference = "Stop"

$downloadUrl = "https://go.microsoft.com/fwlink/p/?LinkId=2124703"
$outputDir = "$PSScriptRoot\redist"

Write-Host "=== WebView2 Bootstrapper Download ==="

if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}

$outFile = "$outputDir\MicrosoftEdgeWebview2Setup.exe"

Write-Host "Downloading from: $downloadUrl"
$ProgressPreference = 'SilentlyContinue'
Invoke-WebRequest -Uri $downloadUrl -OutFile $outFile -UseBasicParsing
$ProgressPreference = 'Continue'

$size = [math]::Round((Get-Item $outFile).Length / 1MB, 2)
Write-Host "Downloaded: $outFile ($size MB)"
Write-Host "Done!"
