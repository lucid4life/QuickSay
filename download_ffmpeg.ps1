# Download FFmpeg essentials and extract just ffmpeg.exe
$ErrorActionPreference = "Stop"

$downloadUrl = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip"
$tempDir = "$env:TEMP\quicksay_ffmpeg"
$zipFile = "$tempDir\ffmpeg-essentials.zip"
$outputDir = "$PSScriptRoot\ffmpeg"

Write-Host "=== FFmpeg Download for QuickSay ==="
Write-Host ""

# Create temp directory
if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
New-Item -ItemType Directory -Path $tempDir | Out-Null

# Download
Write-Host "Downloading FFmpeg essentials (~101 MB)..."
Write-Host "Source: $downloadUrl"
$ProgressPreference = 'SilentlyContinue'  # Speed up download
Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFile -UseBasicParsing
$ProgressPreference = 'Continue'
$zipSize = [math]::Round((Get-Item $zipFile).Length / 1MB, 1)
Write-Host "Downloaded: $zipSize MB"

# Extract
Write-Host "Extracting..."
Expand-Archive -Path $zipFile -DestinationPath $tempDir -Force

# Find ffmpeg.exe in the extracted folder
$ffmpegExe = Get-ChildItem $tempDir -Recurse -Filter "ffmpeg.exe" | Select-Object -First 1
if (-not $ffmpegExe) {
    Write-Host "ERROR: ffmpeg.exe not found in archive!" -ForegroundColor Red
    exit 1
}

Write-Host "Found: $($ffmpegExe.FullName)"
$exeSize = [math]::Round($ffmpegExe.Length / 1MB, 1)
Write-Host "Size: $exeSize MB"

# Copy to output directory
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}
Copy-Item $ffmpegExe.FullName "$outputDir\ffmpeg.exe" -Force
Write-Host ""
Write-Host "Saved to: $outputDir\ffmpeg.exe"

# Also get version info
$version = & "$outputDir\ffmpeg.exe" -version 2>&1 | Select-Object -First 1
Write-Host "Version: $version"

# Cleanup temp
Remove-Item $tempDir -Recurse -Force
Write-Host ""
Write-Host "Done! FFmpeg is ready for bundling."
