# T1.7 Fix (c) — hotkey conflict detection live test.
# Launches the real QuickSay.ahk twice (reserved combo, then default) and asserts
# the hotkeyConflict flag is written / cleared in config.json by the real RegisterHotkey path.
# Assumes config.json is already backed up by the caller and no QuickSay is running.

$ErrorActionPreference = 'Continue'
$dev = "C:\QuickSay\Development"
$ahk = "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
$cfgPath = "$dev\config.json"
$pass = 0; $fail = 0
function Ok($m){ Write-Host "  PASS  $m" -ForegroundColor Green; $script:pass++ }
function Fail($m){ Write-Host "  FAIL  $m" -ForegroundColor Red; $script:fail++ }

function Set-Hotkey($hk) {
    $c = Get-Content $cfgPath -Raw | ConvertFrom-Json
    $c.PSObject.Properties.Remove('hotkeyConflict')
    $c.PSObject.Properties.Remove('hotkeyConflictMsg')
    if ($c.PSObject.Properties.Name -contains 'hotkey') { $c.hotkey = $hk }
    else { $c | Add-Member -NotePropertyName hotkey -NotePropertyValue $hk }
    $c | ConvertTo-Json -Depth 20 | Set-Content $cfgPath -Encoding UTF8
}

function Launch-And-Wait($seconds = 5) {
    $errLog = "$env:TEMP\qs-t17-ahk-err.txt"
    if (Test-Path $errLog) { Remove-Item $errLog -Force }
    $p = Start-Process -FilePath $ahk -ArgumentList "/ErrorStdOut", "`"$dev\QuickSay.ahk`"" `
        -RedirectStandardError $errLog -PassThru -WindowStyle Hidden
    Start-Sleep -Seconds $seconds
    return @{ Proc = $p; ErrLog = $errLog }
}

function Kill-Instance($info) {
    try { if ($info.Proc -and -not $info.Proc.HasExited) { Stop-Process -Id $info.Proc.Id -Force -ErrorAction SilentlyContinue } } catch {}
    # also sweep any QuickSay AHK instance
    Get-CimInstance Win32_Process -Filter "Name='AutoHotkey64.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*QuickSay.ahk*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Milliseconds 500
}

Write-Host "`n=== Case 1: Windows-reserved hotkey (#l) → expect conflict flag ===" -ForegroundColor Cyan
Set-Hotkey '#l'
$info = Launch-And-Wait 6
$errContent = if (Test-Path $info.ErrLog) { (Get-Content $info.ErrLog -Raw) } else { '' }
$startupErr = $errContent -and $errContent.Trim().Length -gt 0
$alive = $info.Proc -and -not $info.Proc.HasExited
if ($alive) { Ok "process survived startup (no crash)" } else { Fail "process exited during startup" }
if (-not $startupErr) { Ok "no AHK startup errors emitted" } else { Fail "AHK startup error: $(Get-Content $info.ErrLog -Raw)" }
$c1 = Get-Content $cfgPath -Raw | ConvertFrom-Json
if ($c1.hotkeyConflict -eq $true) { Ok "hotkeyConflict=true written for reserved combo" } else { Fail "hotkeyConflict not set (got: $($c1.hotkeyConflict))" }
if ($c1.hotkeyConflictMsg) { Ok "hotkeyConflictMsg present: '$($c1.hotkeyConflictMsg.Substring(0,[Math]::Min(50,$c1.hotkeyConflictMsg.Length)))...'" } else { Fail "hotkeyConflictMsg missing" }
Kill-Instance $info

Write-Host "`n=== Case 2: default hotkey (^LWin) → expect flag cleared ===" -ForegroundColor Cyan
Set-Hotkey '^LWin'
# pre-seed a stale conflict flag to prove it gets cleared
$c = Get-Content $cfgPath -Raw | ConvertFrom-Json
$c | Add-Member -NotePropertyName hotkeyConflict -NotePropertyValue $true -Force
$c | Add-Member -NotePropertyName hotkeyConflictMsg -NotePropertyValue 'stale' -Force
$c | ConvertTo-Json -Depth 20 | Set-Content $cfgPath -Encoding UTF8
$info2 = Launch-And-Wait 6
$alive2 = $info2.Proc -and -not $info2.Proc.HasExited
if ($alive2) { Ok "process survived startup with default hotkey" } else { Fail "process exited during startup" }
$c2 = Get-Content $cfgPath -Raw | ConvertFrom-Json
$hasFlag = ($c2.PSObject.Properties.Name -contains 'hotkeyConflict') -and ($c2.hotkeyConflict -eq $true)
if (-not $hasFlag) { Ok "stale hotkeyConflict flag cleared on successful default registration" } else { Fail "stale flag NOT cleared (hotkeyConflict=$($c2.hotkeyConflict))" }
Kill-Instance $info2

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "$pass passed, $fail failed" -ForegroundColor ($fail -eq 0 ? 'Green' : 'Red')
exit ($fail -gt 0 ? 1 : 0)
