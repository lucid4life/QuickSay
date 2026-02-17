# =============================================================================
# QuickSay Release Automation
# Updates version numbers everywhere, compiles, signs, builds installer, and
# creates version.json for the auto-update system.
#
# Usage:
#   .\release.ps1                                    # Auto-detect & bump patch
#   .\release.ps1 -Bump minor                        # Auto-detect & bump minor
#   .\release.ps1 -Bump major                        # Auto-detect & bump major
#   .\release.ps1 -Version "1.6.0"                   # Explicit version
#   .\release.ps1 -Bump minor -Changelog "New feat"  # With changelog
#   .\release.ps1 -Bump minor -SkipSign              # Skip code signing
#   .\release.ps1 -Bump minor -SkipCompile           # Only update version numbers
#   .\release.ps1 -Bump minor -SkipGitHub            # Skip GitHub release creation
#   .\release.ps1 -DryRun                            # Preview changes only
# =============================================================================

param(
    [ValidateSet('patch','minor','major')]
    [string]$Bump = "patch",

    [ValidatePattern('^\d+\.\d+(\.\d+)?$')]
    [string]$Version = "",

    [string]$Changelog = "",
    [switch]$SkipSign,
    [switch]$SkipCompile,
    [switch]$SkipGitHub,
    [switch]$DryRun
)

# ── Strict mode ──────────────────────────────────────────────────────────────
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# ── Auto-detect current version from QuickSay.ahk ───────────────────────────
$devDir = $PSScriptRoot

function Get-CurrentVersion {
    $qsPath = Join-Path $devDir "QuickSay.ahk"
    $content = Get-Content $qsPath -Raw -Encoding UTF8
    if ($content -match 'localVersion := "(\d+\.\d+\.\d+)"') {
        return $matches[1]
    }
    Write-Host "ERROR: Could not detect current version from QuickSay.ahk" -ForegroundColor Red
    exit 1
}

$currentVersion = Get-CurrentVersion

if ($Version -ne "") {
    # Explicit version provided — use it directly
    $newVersion = $Version
} else {
    # Auto-increment based on -Bump
    $cv = $currentVersion.Split('.')
    switch ($Bump) {
        'patch' { $newVersion = "$($cv[0]).$($cv[1]).$([int]$cv[2] + 1)" }
        'minor' { $newVersion = "$($cv[0]).$([int]$cv[1] + 1).0" }
        'major' { $newVersion = "$([int]$cv[0] + 1).0.0" }
    }
}

# ── Parse version components ─────────────────────────────────────────────────
$parts = $newVersion.Split('.')
$major = $parts[0]
$minor = $parts[1]
$patch = if ($parts.Length -ge 3) { $parts[2] } else { "0" }

$semVer      = "$major.$minor.$patch"          # 1.6.0
$fileVer     = "$major.$minor.$patch.0"        # 1.6.0.0
$shortVer    = "$major.$minor"                 # 1.6
$displayVer  = "v$shortVer"                    # v1.6
if ([int]$patch -gt 0) { $displayVer = "v$semVer" }  # v1.6.1 for patches

# ── Paths ────────────────────────────────────────────────────────────────────
$devDir       = $PSScriptRoot                  # C:\QuickSay\Development
$projectRoot  = Split-Path $devDir -Parent     # C:\QuickSay
$websiteDir   = Join-Path $projectRoot "Website"
$installerDir = Join-Path $devDir "installer"

$ahk2exe  = "C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe"
$ahk2base = "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
$iscc     = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"

# Signing config
$dlib      = "C:\Users\abeek\TrustedSigning\bin\x64\Azure.CodeSigning.Dlib.dll"
$metadata  = Join-Path $devDir "signing\metadata.json"
$timestamp = "http://timestamp.acs.microsoft.com"

$installerFilename = "QuickSay_Beta_${displayVer}_Setup.exe"

# ── Helper: colored output ───────────────────────────────────────────────────
function Write-Step($msg)  { Write-Host "`n>> $msg" -ForegroundColor Cyan }
function Write-OK($msg)    { Write-Host "   OK: $msg" -ForegroundColor Green }
function Write-Warn($msg)  { Write-Host "   WARN: $msg" -ForegroundColor Yellow }
function Write-Fail($msg)  { Write-Host "   FAIL: $msg" -ForegroundColor Red }

# ── Helper: regex replace in file ────────────────────────────────────────────
function Update-FileVersion {
    param(
        [string]$Path,
        [string]$Pattern,
        [string]$Replacement,
        [string]$Label
    )
    if (-not (Test-Path $Path)) {
        Write-Warn "$Path not found — skipping"
        return
    }
    $content = Get-Content $Path -Raw -Encoding UTF8
    if ($content -match $Pattern) {
        if (-not $DryRun) {
            $updated = $content -replace $Pattern, $Replacement
            [System.IO.File]::WriteAllText($Path, $updated, [System.Text.UTF8Encoding]::new($false))
        }
        Write-OK $Label
    } else {
        Write-Warn "Pattern not matched for: $Label"
    }
}

# ── Banner ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "============================================" -ForegroundColor Magenta
Write-Host "  QuickSay Release Builder" -ForegroundColor Magenta
Write-Host "============================================" -ForegroundColor Magenta
Write-Host ""
Write-Host "  Current:    $currentVersion" -ForegroundColor Gray
Write-Host "  New:        $semVer ($displayVer)" -ForegroundColor White
Write-Host "  Bump:       $Bump" -ForegroundColor White
Write-Host "  File Ver:   $fileVer" -ForegroundColor White
Write-Host "  Signing:    $(if ($SkipSign) {'SKIP'} else {'Azure Trusted Signing'})" -ForegroundColor White
Write-Host "  Compile:    $(if ($SkipCompile) {'SKIP'} else {'Ahk2Exe + Inno Setup'})" -ForegroundColor White
Write-Host "  GitHub:     $(if ($SkipGitHub) {'SKIP'} else {'Create release + upload'})" -ForegroundColor White
Write-Host "  Mode:       $(if ($DryRun) {'DRY RUN (no files modified)'} else {'LIVE'})" -ForegroundColor $(if ($DryRun) {'Yellow'} else {'White'})
Write-Host ""

if ($currentVersion -eq $semVer) {
    Write-Host "  WARNING: New version is the same as current version!" -ForegroundColor Yellow
    Write-Host ""
}

if (-not $DryRun) {
    # Support piped input (e.g., echo y | release.ps1) and interactive prompts
    if ([Console]::IsInputRedirected) {
        $confirm = [Console]::In.ReadLine()
    } else {
        $confirm = Read-Host "Proceed with release $currentVersion -> ${displayVer}? (y/N)"
    }
    if ($confirm -ne 'y') {
        Write-Host "Aborted." -ForegroundColor Yellow
        exit 0
    }
}

# =============================================================================
# STEP 1: Update version numbers in all files
# =============================================================================
Write-Step "STEP 1: Updating version numbers across all files"

# The old version pattern matches any Beta vX.Y or X.Y.Z pattern
# We use flexible regexes so this works regardless of current version

# ── QuickSay.ahk ────────────────────────────────────────────────────────────
$qsFile = Join-Path $devDir "QuickSay.ahk"

Update-FileVersion $qsFile `
    '(?<=;@Ahk2Exe-SetDescription QuickSay Beta v)\d+\.\d+' `
    $shortVer `
    "QuickSay.ahk — @Ahk2Exe-SetDescription"

Update-FileVersion $qsFile `
    '(?<=;@Ahk2Exe-SetFileVersion )\d+\.\d+\.\d+\.\d+' `
    $fileVer `
    "QuickSay.ahk — @Ahk2Exe-SetFileVersion"

Update-FileVersion $qsFile `
    '(?<=;@Ahk2Exe-SetProductName QuickSay Beta v)\d+\.\d+' `
    $shortVer `
    "QuickSay.ahk — @Ahk2Exe-SetProductName"

Update-FileVersion $qsFile `
    '(?<=;@Ahk2Exe-SetProductVersion )\d+\.\d+\.\d+\.\d+' `
    $fileVer `
    "QuickSay.ahk — @Ahk2Exe-SetProductVersion"

Update-FileVersion $qsFile `
    '(?<=;  QuickSay Beta v)\d+\.\d+' `
    $shortVer `
    "QuickSay.ahk — comment header"

Update-FileVersion $qsFile `
    '(?<=QuickSay\.VoiceToText\.)\d+\.\d+' `
    $shortVer `
    "QuickSay.ahk — AppUserModelID"

Update-FileVersion $qsFile `
    '(?<=StrLen\("QuickSay Beta v)\d+\.\d+' `
    $shortVer `
    "QuickSay.ahk — RelaunchDisplayName StrLen"

Update-FileVersion $qsFile `
    '(?<=StrPut\("QuickSay Beta v)\d+\.\d+' `
    $shortVer `
    "QuickSay.ahk — RelaunchDisplayName StrPut"

Update-FileVersion $qsFile `
    '(?<=; Set RelaunchDisplayNameResource .+ "QuickSay Beta v)\d+\.\d+' `
    $shortVer `
    "QuickSay.ahk — RelaunchDisplayName comment"

Update-FileVersion $qsFile `
    '(?<=localVersion := ")\d+\.\d+\.\d+' `
    $semVer `
    "QuickSay.ahk — localVersion"

# ── onboarding_ui.ahk ───────────────────────────────────────────────────────
$obFile = Join-Path $devDir "onboarding_ui.ahk"

Update-FileVersion $obFile `
    '(?<=;@Ahk2Exe-SetDescription QuickSay Beta v)\d+\.\d+' `
    $shortVer `
    "onboarding_ui.ahk — @Ahk2Exe-SetDescription"

Update-FileVersion $obFile `
    '(?<=;@Ahk2Exe-SetFileVersion )\d+\.\d+\.\d+\.\d+' `
    $fileVer `
    "onboarding_ui.ahk — @Ahk2Exe-SetFileVersion"

Update-FileVersion $obFile `
    '(?<=;@Ahk2Exe-SetProductName QuickSay Beta v)\d+\.\d+' `
    $shortVer `
    "onboarding_ui.ahk — @Ahk2Exe-SetProductName"

Update-FileVersion $obFile `
    '(?<=;@Ahk2Exe-SetProductVersion )\d+\.\d+\.\d+\.\d+' `
    $fileVer `
    "onboarding_ui.ahk — @Ahk2Exe-SetProductVersion"

Update-FileVersion $obFile `
    '(?<=QuickSay\.VoiceToText\.)\d+\.\d+' `
    $shortVer `
    "onboarding_ui.ahk — AppUserModelID"

Update-FileVersion $obFile `
    '(?<=; QuickSay Beta v)\d+\.\d+(?= Onboarding)' `
    $shortVer `
    "onboarding_ui.ahk — comment header"

# ── settings_ui.ahk ─────────────────────────────────────────────────────────
$suFile = Join-Path $devDir "settings_ui.ahk"

Update-FileVersion $suFile `
    '(?<=;@Ahk2Exe-SetDescription QuickSay Beta v)\d+\.\d+' `
    $shortVer `
    "settings_ui.ahk — @Ahk2Exe-SetDescription"

Update-FileVersion $suFile `
    '(?<=;@Ahk2Exe-SetFileVersion )\d+\.\d+\.\d+\.\d+' `
    $fileVer `
    "settings_ui.ahk — @Ahk2Exe-SetFileVersion"

Update-FileVersion $suFile `
    '(?<=;@Ahk2Exe-SetProductName QuickSay Beta v)\d+\.\d+' `
    $shortVer `
    "settings_ui.ahk — @Ahk2Exe-SetProductName"

Update-FileVersion $suFile `
    '(?<=;@Ahk2Exe-SetProductVersion )\d+\.\d+\.\d+\.\d+' `
    $fileVer `
    "settings_ui.ahk — @Ahk2Exe-SetProductVersion"

Update-FileVersion $suFile `
    '(?<=QuickSay\.VoiceToText\.)\d+\.\d+' `
    $shortVer `
    "settings_ui.ahk — AppUserModelID"

Update-FileVersion $suFile `
    '(?<=; QuickSay Beta v)\d+\.\d+(?= Settings)' `
    $shortVer `
    "settings_ui.ahk — comment header"

# ── lib/settings-ui.ahk ─────────────────────────────────────────────────────
$libSuFile = Join-Path $devDir "lib\settings-ui.ahk"

Update-FileVersion $libSuFile `
    '(?<=StrLen\("QuickSay Beta v)\d+\.\d+' `
    $shortVer `
    "lib/settings-ui.ahk — RelaunchDisplayName StrLen"

Update-FileVersion $libSuFile `
    '(?<=StrPut\("QuickSay Beta v)\d+\.\d+' `
    $shortVer `
    "lib/settings-ui.ahk — RelaunchDisplayName StrPut"

Update-FileVersion $libSuFile `
    '(?<=; Set RelaunchDisplayNameResource .+ "QuickSay Beta v)\d+\.\d+' `
    $shortVer `
    "lib/settings-ui.ahk — RelaunchDisplayName comment"

# ── gui/settings.html ────────────────────────────────────────────────────────
$settingsHtml = Join-Path $devDir "gui\settings.html"

Update-FileVersion $settingsHtml `
    '(?<=<div class="about-app-version">Beta v)\d+\.\d+(\.\d+)?' `
    $semVer `
    "settings.html — About tab version"

# ── setup.iss ────────────────────────────────────────────────────────────────
$issFile = Join-Path $devDir "setup.iss"

Update-FileVersion $issFile `
    '(?<=; QuickSay Beta v)\d+\.\d+(?= Installer)' `
    $shortVer `
    "setup.iss — comment line 1"

Update-FileVersion $issFile `
    '(?<=; Beta v)\d+\.\d+(?= Release)' `
    $shortVer `
    "setup.iss — comment line 2"

Update-FileVersion $issFile `
    '(?<=#define MyAppVersion ")\d+\.\d+\.\d+' `
    $semVer `
    "setup.iss — MyAppVersion"

Update-FileVersion $issFile `
    '(?<=#define MyAppVerName "QuickSay Beta v)\d+\.\d+' `
    $shortVer `
    "setup.iss — MyAppVerName"

Update-FileVersion $issFile `
    '(?<=OutputBaseFilename=QuickSay_Beta_v)\d+\.\d+(?=_Setup)' `
    $shortVer `
    "setup.iss — OutputBaseFilename"

Update-FileVersion $issFile `
    '(?<=QuickSay Beta v)\d+\.\d+(?= on your computer)' `
    $shortVer `
    "setup.iss — WelcomeLabel2"

# ── docs/LICENSE_AGREEMENT.rtf ──────────────────────────────────────────────
$licenseRtf = Join-Path $devDir "docs\LICENSE_AGREEMENT.rtf"

Update-FileVersion $licenseRtf `
    '(?<=Version )\d+\.\d+(\.\d+)?' `
    $semVer `
    "LICENSE_AGREEMENT.rtf — version number"

$monthYear = (Get-Date).ToString("MMMM yyyy")
Update-FileVersion $licenseRtf `
    '(?<=Version \d+\.\d+(\.\d+)? \| )\w+ \d{4}' `
    $monthYear `
    "LICENSE_AGREEMENT.rtf — date ($monthYear)"

# ── data/changelog.json (add new version entry) ─────────────────────────────
if ($Changelog -ne "") {
    Write-Step "Updating changelog.json"
    $changelogFile = Join-Path $devDir "data\changelog.json"
    if (Test-Path $changelogFile) {
        $changelogJson = Get-Content $changelogFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $items = $Changelog.Split(',') | ForEach-Object { $_.Trim() }

        # Check if this version already exists
        $existing = $changelogJson | Where-Object { $_.version -eq "$semVer-beta" }
        if ($existing) {
            Write-Warn "Version $semVer-beta already in changelog — skipping"
        } else {
            $newEntry = [PSCustomObject]@{
                version = "$semVer-beta"
                date    = (Get-Date -Format "yyyy-MM-dd")
                changes = @($items)
            }
            # Prepend new entry
            $changelogJson = @($newEntry) + @($changelogJson)
            if (-not $DryRun) {
                $changelogJson | ConvertTo-Json -Depth 10 |
                    Set-Content $changelogFile -Encoding UTF8 -NoNewline
            }
            Write-OK "changelog.json — added $semVer-beta with $($items.Count) changes"
        }
    }
}

Write-Host ""
Write-Host "   Version numbers updated in all files." -ForegroundColor Green

if ($DryRun) {
    Write-Host "`nDry run complete. No files were modified." -ForegroundColor Yellow
    exit 0
}

# =============================================================================
# STEP 2: Compile AHK → EXE
# =============================================================================
if (-not $SkipCompile) {
    Write-Step "STEP 2: Compiling AHK scripts to EXE"

    if (-not (Test-Path $ahk2exe)) {
        Write-Fail "Ahk2Exe not found at: $ahk2exe"
        exit 1
    }

    # Compile QuickSay.ahk → QuickSay.exe
    Write-Host "   Compiling QuickSay.ahk..." -ForegroundColor White
    $qsOut = Join-Path $devDir "QuickSay.exe"
    & $ahk2exe /in $qsFile /out $qsOut /base $ahk2base /compress 0
    Start-Sleep -Seconds 2
    if (-not (Test-Path $qsOut)) {
        Write-Fail "Failed to compile QuickSay.ahk"
        exit 1
    }
    Write-OK "QuickSay.exe"

    # Compile onboarding_ui.ahk → QuickSay-Setup.exe
    Write-Host "   Compiling onboarding_ui.ahk..." -ForegroundColor White
    $obOut = Join-Path $devDir "QuickSay-Setup.exe"
    & $ahk2exe /in $obFile /out $obOut /base $ahk2base /compress 0
    Start-Sleep -Seconds 2
    if (-not (Test-Path $obOut)) {
        Write-Fail "Failed to compile onboarding_ui.ahk"
        exit 1
    }
    Write-OK "QuickSay-Setup.exe"

    # =============================================================================
    # STEP 3: Sign compiled EXE files
    # =============================================================================
    if (-not $SkipSign) {
        Write-Step "STEP 3: Signing compiled EXE files"

        # Check Azure login
        $azCheck = az account show 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "Not logged into Azure. Logging in..."
            az login
        }

        foreach ($exe in @($qsOut, $obOut)) {
            $name = Split-Path $exe -Leaf
            Write-Host "   Signing $name..." -ForegroundColor White
            signtool.exe sign /v /fd SHA256 /tr $timestamp /td SHA256 /dlib $dlib /dmdf $metadata $exe
            if ($LASTEXITCODE -ne 0) {
                Write-Fail "Failed to sign $name"
                exit 1
            }
            Write-OK "$name signed"
        }
    } else {
        Write-Step "STEP 3: Skipping code signing (--SkipSign)"
    }

    # =============================================================================
    # STEP 4: Build installer with Inno Setup
    # =============================================================================
    Write-Step "STEP 4: Building installer with Inno Setup"

    if (-not (Test-Path $iscc)) {
        Write-Fail "ISCC.exe not found at: $iscc"
        exit 1
    }

    # ISCC runs from the directory containing setup.iss
    Push-Location $devDir
    & $iscc $issFile
    $isccResult = $LASTEXITCODE
    Pop-Location

    if ($isccResult -ne 0) {
        Write-Fail "Installer build failed"
        exit 1
    }

    $installerPath = Join-Path $installerDir "QuickSay_Beta_${displayVer}_Setup.exe"
    if (-not (Test-Path $installerPath)) {
        # Try alternate naming (v prefix might not be in OutputBaseFilename)
        $installerPath = Join-Path $installerDir "QuickSay_Beta_v${shortVer}_Setup.exe"
    }
    Write-OK "Installer built: $installerPath"

    # =============================================================================
    # STEP 5: Sign the installer
    # =============================================================================
    if (-not $SkipSign) {
        Write-Step "STEP 5: Signing installer"

        Write-Host "   Signing $(Split-Path $installerPath -Leaf)..." -ForegroundColor White
        signtool.exe sign /v /fd SHA256 /tr $timestamp /td SHA256 /dlib $dlib /dmdf $metadata $installerPath
        if ($LASTEXITCODE -ne 0) {
            Write-Fail "Failed to sign installer"
            exit 1
        }
        Write-OK "Installer signed"

        # Verify signature
        signtool.exe verify /v /pa $installerPath | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-OK "Signature verified"
        } else {
            Write-Warn "Signature verification returned non-zero (may still be valid)"
        }
    } else {
        Write-Step "STEP 5: Skipping installer signing (--SkipSign)"
    }

} else {
    Write-Step "STEPS 2-5: Skipping compile & build (--SkipCompile)"
}

# =============================================================================
# STEP 5b: Upload installer to R2 for website downloads
# =============================================================================
if (-not $SkipCompile) {
    Write-Step "STEP 5b: Uploading installer to Cloudflare R2"

    $r2InstallerName = "QuickSay_Beta_v${shortVer}_Setup.exe"
    $localInstallerPath = Join-Path $installerDir $r2InstallerName
    if (-not (Test-Path $localInstallerPath)) {
        # Fallback: try the displayVer naming
        $localInstallerPath = Join-Path $installerDir "QuickSay_Beta_${displayVer}_Setup.exe"
    }

    if (Test-Path $localInstallerPath) {
        $npxCmd = Get-Command npx -ErrorAction SilentlyContinue
        if ($npxCmd) {
            Push-Location $websiteDir
            $oldEAP = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            npx wrangler r2 object put "quicksay-downloads/$r2InstallerName" --file="$localInstallerPath" --content-type="application/x-msdownload" --remote 2>&1 | Out-Null
            $r2Result = $LASTEXITCODE
            $ErrorActionPreference = $oldEAP
            Pop-Location

            if ($r2Result -eq 0) {
                Write-OK "R2 upload: $r2InstallerName"
            } else {
                Write-Warn "R2 upload failed — upload manually: npx wrangler r2 object put quicksay-downloads/$r2InstallerName --file=$localInstallerPath --remote"
            }
        } else {
            Write-Warn "npx not found — skipping R2 upload. Upload manually."
        }
    } else {
        Write-Warn "Installer not found for R2 upload — skipping"
    }
} else {
    Write-Host "   [SKIP] R2 upload (--SkipCompile)" -ForegroundColor Gray
}

# =============================================================================
# STEP 6: Create/update Website version.json for auto-update
# =============================================================================
Write-Step "STEP 6: Creating version.json for auto-update"

$versionJsonPath = Join-Path $websiteDir "public\version.json"
$versionJsonDir  = Split-Path $versionJsonPath -Parent

if (-not (Test-Path $versionJsonDir)) {
    New-Item -ItemType Directory -Path $versionJsonDir -Force | Out-Null
}

$versionObj = [ordered]@{
    version      = $semVer
    download_url = "https://quicksay.app/download"
    release_date = (Get-Date -Format "yyyy-MM-dd")
    changelog    = if ($Changelog -ne "") {
        $Changelog.Split(',') | ForEach-Object { $_.Trim() }
    } else {
        @("Bug fixes and improvements")
    }
}

$versionObj | ConvertTo-Json -Depth 5 |
    Set-Content $versionJsonPath -Encoding UTF8 -NoNewline

Write-OK "version.json → $semVer"

# Update PAD file (pad.xml) for Softpedia and software directories
$padXmlPath = Join-Path $websiteDir "public\pad.xml"
if (Test-Path $padXmlPath) {
    $padContent = Get-Content $padXmlPath -Raw -Encoding UTF8
    $vParts = $semVer.Split('.')

    # Update version
    $padContent = $padContent -replace '<Program_Version>[^<]*</Program_Version>', "<Program_Version>$semVer</Program_Version>"

    # Update release date
    $now = Get-Date
    $padContent = $padContent -replace '<Program_Release_Month>[^<]*</Program_Release_Month>', "<Program_Release_Month>$($now.ToString('MM'))</Program_Release_Month>"
    $padContent = $padContent -replace '<Program_Release_Day>[^<]*</Program_Release_Day>', "<Program_Release_Day>$($now.ToString('dd'))</Program_Release_Day>"
    $padContent = $padContent -replace '<Program_Release_Year>[^<]*</Program_Release_Year>', "<Program_Release_Year>$($now.Year)</Program_Release_Year>"

    # Update file size if installer exists
    $installerPath = Join-Path $devDir "installer\$installerFilename"
    if (Test-Path $installerPath) {
        $fileBytes = (Get-Item $installerPath).Length
        $fileK = [math]::Floor($fileBytes / 1024)
        $fileMB = [math]::Round($fileBytes / 1048576, 2)
        $padContent = $padContent -replace '<File_Size_Bytes>[^<]*</File_Size_Bytes>', "<File_Size_Bytes>$fileBytes</File_Size_Bytes>"
        $padContent = $padContent -replace '<File_Size_K>[^<]*</File_Size_K>', "<File_Size_K>$fileK</File_Size_K>"
        $padContent = $padContent -replace '<File_Size_MB>[^<]*</File_Size_MB>', "<File_Size_MB>$fileMB</File_Size_MB>"
    }

    # Update changelog
    if ($Changelog -ne "") {
        $changeText = ($Changelog.Split(',') | ForEach-Object { $_.Trim() }) -join '. '
        $padContent = $padContent -replace '<Program_Change_Info>[^<]*</Program_Change_Info>', "<Program_Change_Info>$changeText</Program_Change_Info>"
    }

    Set-Content $padXmlPath -Value $padContent -Encoding UTF8 -NoNewline
    Write-OK "pad.xml → $semVer"
} else {
    Write-Host "   [SKIP] pad.xml not found at $padXmlPath" -ForegroundColor Yellow
}

# =============================================================================
# STEP 7: Update website source files with new version
# =============================================================================
Write-Step "STEP 7: Updating website source files"

$websiteSrcDir = Join-Path $websiteDir "src"

# ── Footer.astro — version link ─────────────────────────────────────────────
$footerFile = Join-Path $websiteSrcDir "components\Footer.astro"
if (Test-Path $footerFile) {
    $footerContent = Get-Content $footerFile -Raw -Encoding UTF8
    if ($footerContent -match 'QuickSay v\d+\.\d+\.\d+') {
        $footerContent = $footerContent -replace 'QuickSay v\d+\.\d+\.\d+', "QuickSay v$semVer"
        [System.IO.File]::WriteAllText($footerFile, $footerContent, [System.Text.UTF8Encoding]::new($false))
        Write-OK "Footer.astro — QuickSay v$semVer"
    } else {
        Write-Warn "Footer.astro — version pattern not found"
    }
} else {
    Write-Warn "Footer.astro not found — skipping"
}

# ── beta/getting-started.astro — version badge ──────────────────────────────
$gsFile = Join-Path $websiteSrcDir "pages\beta\getting-started.astro"
if (Test-Path $gsFile) {
    $gsContent = Get-Content $gsFile -Raw -Encoding UTF8
    if ($gsContent -match 'Beta v\d+\.\d+\.\d+') {
        $gsContent = $gsContent -replace 'Beta v\d+\.\d+\.\d+', "Beta v$semVer"
        [System.IO.File]::WriteAllText($gsFile, $gsContent, [System.Text.UTF8Encoding]::new($false))
        Write-OK "beta/getting-started.astro — Beta v$semVer"
    } else {
        Write-Warn "beta/getting-started.astro — version pattern not found"
    }

    # Update download link to match versioned installer filename
    $gsContent = Get-Content $gsFile -Raw -Encoding UTF8
    if ($gsContent -match 'href="/downloads/QuickSay_Beta_v[\d.]+_Setup\.exe"') {
        $gsContent = $gsContent -replace 'href="/downloads/QuickSay_Beta_v[\d.]+_Setup\.exe"', "href=`"/downloads/QuickSay_Beta_v${shortVer}_Setup.exe`""
        [System.IO.File]::WriteAllText($gsFile, $gsContent, [System.Text.UTF8Encoding]::new($false))
        Write-OK "beta/getting-started.astro — download link → QuickSay_Beta_v${shortVer}_Setup.exe"
    } else {
        Write-Warn "beta/getting-started.astro — download link pattern not found"
    }
} else {
    Write-Warn "beta/getting-started.astro not found — skipping"
}

# ── beta/changelog.astro — prepend new entry to entries array ────────────────
$betaChangelogFile = Join-Path $websiteSrcDir "pages\beta\changelog.astro"
if (Test-Path $betaChangelogFile) {
    $bcContent = Get-Content $betaChangelogFile -Raw -Encoding UTF8

    # Check if this version already exists
    if ($bcContent -match [regex]::Escape("version: 'v$semVer'")) {
        Write-Warn "beta/changelog.astro — v$semVer already exists"
    } else {
        # Build changelog items
        if ($Changelog -ne "") {
            $items = $Changelog.Split(',') | ForEach-Object { $_.Trim() }
        } else {
            $items = @("Bug fixes and improvements")
        }

        $formattedDate = Get-Date -Format "MMMM d, yyyy"

        # Build the changes array entries
        $changesLines = @()
        foreach ($item in $items) {
            # Auto-detect type from prefix keywords
            $type = "Improvement"
            $text = $item
            if ($item -match '^(?:Add|New|Introduce)\b') { $type = "New" }
            elseif ($item -match '^(?:Fix|Resolve|Patch)\b') { $type = "Fix" }

            $changesLines += "      { type: '$type', text: '$($text -replace "'", "''")' },"
        }
        $changesBlock = $changesLines -join "`n"

        $newEntry = @"
  {
    date: '$formattedDate',
    version: 'v$semVer',
    changes: [
$changesBlock
    ],
  },
  {
"@

        # Insert after "const entries: ChangelogEntry[] = [\n"
        $bcContent = $bcContent -replace '(const entries: ChangelogEntry\[\] = \[\s*\n)\s*\{', "`$1$newEntry"
        [System.IO.File]::WriteAllText($betaChangelogFile, $bcContent, [System.Text.UTF8Encoding]::new($false))
        Write-OK "beta/changelog.astro — added v$semVer entry"
    }
} else {
    Write-Warn "beta/changelog.astro not found — skipping"
}

# ── content/changelog/vX.X.X.mdx — create new changelog MDX file ────────────
$mdxDir = Join-Path $websiteSrcDir "content\changelog"
$mdxFile = Join-Path $mdxDir "v$semVer.mdx"
if (Test-Path $mdxFile) {
    Write-Warn "content/changelog/v$semVer.mdx already exists — skipping"
} else {
    if (Test-Path $mdxDir) {
        $releaseDate = Get-Date -Format "yyyy-MM-dd"

        # Build summary from first changelog item or default
        if ($Changelog -ne "") {
            $items = $Changelog.Split(',') | ForEach-Object { $_.Trim() }
            $summary = ($items | Select-Object -First 3) -join ", "
            if ($summary.Length -gt 80) { $summary = $summary.Substring(0, 77) + "..." }
        } else {
            $summary = "Bug fixes and improvements"
        }

        # Build MDX content
        $mdxLines = @()
        $mdxLines += "---"
        $mdxLines += "version: `"$semVer`""
        $mdxLines += "date: `"$releaseDate`""
        $mdxLines += "summary: `"$summary`""
        $mdxLines += "---"
        $mdxLines += ""

        if ($Changelog -ne "") {
            foreach ($item in $items) {
                # Auto-detect tag
                $tag = "Improved"
                if ($item -match '^(?:Add|New|Introduce)\b') { $tag = "Added" }
                elseif ($item -match '^(?:Fix|Resolve|Patch)\b') { $tag = "Fixed" }

                $mdxLines += "- **[$tag]** $item"
            }
        } else {
            $mdxLines += "- **[Improved]** Bug fixes and improvements"
        }
        $mdxLines += ""

        $mdxContent = $mdxLines -join "`n"
        [System.IO.File]::WriteAllText($mdxFile, $mdxContent, [System.Text.UTF8Encoding]::new($false))
        Write-OK "content/changelog/v$semVer.mdx — created"
    } else {
        Write-Warn "content/changelog/ directory not found — skipping MDX"
    }
}

# ── Git commit & push changes ─────────────────────────────────────────────
Write-Step "STEP 7b: Committing and deploying changes"

# Find the git repo that has a remote configured
# Development/ has the GitHub remote; Website/ is a subdirectory of the parent repo
# which may not have a remote. Use the Development repo if it's the one with the remote.
$gitRepoDir = $null
$gitWebPrefix = ""

Push-Location $devDir
$devRemote = git remote get-url origin 2>$null
Pop-Location

if ($devRemote) {
    # Development repo has a remote — check if website is reachable from its root
    Push-Location $devDir
    $devRoot = (git rev-parse --show-toplevel 2>$null)
    Pop-Location

    if ($devRoot) {
        $devRoot = $devRoot.Trim().Replace('/', '\')
        $relWeb = $websiteDir.Replace($devRoot, '').TrimStart('\').Replace('\', '/')
        if ($relWeb -ne $websiteDir) {
            $gitRepoDir = $devRoot
            $gitWebPrefix = $relWeb
        }
    }
}

# Fallback: try the Website directory itself
if (-not $gitRepoDir) {
    Push-Location $websiteDir
    $webRemote = git remote get-url origin 2>$null
    Pop-Location
    if ($webRemote) {
        $gitRepoDir = $websiteDir
        $gitWebPrefix = ""
    }
}

# Fallback: try parent project root
if (-not $gitRepoDir) {
    Push-Location $projectRoot
    $rootRemote = git remote get-url origin 2>$null
    Pop-Location
    if ($rootRemote) {
        $gitRepoDir = $projectRoot
        $gitWebPrefix = "Website"
    }
}

if (-not $gitRepoDir) {
    Write-Warn "No git remote found for website files — commit and push manually"
} else {
    Push-Location $gitRepoDir

    # Build file paths relative to the git repo root
    $webFiles = @()
    $prefixSlash = if ($gitWebPrefix) { "$gitWebPrefix/" } else { "" }
    foreach ($f in @("public/version.json", "public/pad.xml", "src/components/Footer.astro",
                     "src/pages/beta/getting-started.astro", "src/pages/beta/changelog.astro",
                     "src/content/changelog/v$semVer.mdx")) {
        $webFiles += "${prefixSlash}${f}"
    }

    # Stage files — redirect stderr to suppress CRLF warnings (git writes them to stderr
    # and PowerShell's $ErrorActionPreference=Stop treats any stderr output as a terminating error)
    $oldEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    git add $webFiles 2>$null
    $addResult = $LASTEXITCODE
    $ErrorActionPreference = $oldEAP

    if ($addResult -ne 0) {
        Write-Warn "git add returned non-zero — some files may not have been staged"
    }

    $oldEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    git commit -m "release: $displayVer" 2>$null | Out-Null
    $commitResult = $LASTEXITCODE
    $ErrorActionPreference = $oldEAP

    if ($commitResult -eq 0) {
        Write-OK "Committed website changes"

        $ErrorActionPreference = "Continue"
        git push 2>$null | Out-Null
        $pushResult = $LASTEXITCODE
        $ErrorActionPreference = "Stop"

        if ($pushResult -eq 0) {
            Write-OK "Pushed to remote (deploy triggered)"
        } else {
            Write-Warn "Git push failed — push manually: cd $gitRepoDir && git push"
        }
    } else {
        # Check if nothing to commit
        $statusCheck = git status --porcelain 2>$null
        if (-not $statusCheck) {
            Write-Host "   No website changes to commit (already up-to-date)" -ForegroundColor Gray
        } else {
            Write-Warn "Git commit failed — commit manually from: $gitRepoDir"
        }
    }

    Pop-Location
}

# =============================================================================
# STEP 8: Create GitHub Release and Upload Installer
# =============================================================================
if (-not $SkipGitHub -and -not $SkipCompile) {
    Write-Step "STEP 8: Creating GitHub release and uploading installer"

    # Ensure we're in the Development directory (where the GitHub remote is)
    Push-Location $devDir

    # Check if gh CLI is installed
    $ghInstalled = $null -ne (Get-Command gh -ErrorAction SilentlyContinue)
    if (-not $ghInstalled) {
        Write-Warn "GitHub CLI (gh) not installed — skipping GitHub release"
        Write-Host "   Install: winget install --id GitHub.cli" -ForegroundColor Gray
    } else {
        # Check if authenticated
        $ghAuthStatus = gh auth status 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "Not logged into GitHub CLI — skipping GitHub release"
            Write-Host "   Run: gh auth login" -ForegroundColor Gray
        } else {
            # Build release notes from changelog
            $releaseNotes = ""
            if ($Changelog -ne "") {
                $items = $Changelog.Split(',') | ForEach-Object { $_.Trim() }
                $releaseNotes = "## Changes`n`n"
                foreach ($item in $items) {
                    # Auto-detect emoji prefix
                    $emoji = "✨"  # Default: improvement
                    if ($item -match '^(?:Add|New|Introduce)\b') { $emoji = "✨" }
                    elseif ($item -match '^(?:Fix|Resolve|Patch)\b') { $emoji = "🐛" }

                    $releaseNotes += "- $emoji $item`n"
                }
            } else {
                $releaseNotes = "## Changes`n`n- ✨ Bug fixes and improvements"
            }

            $releaseNotes += "`n## Installation`n`n"
            $releaseNotes += "1. Download ``QuickSay_Beta_${displayVer}_Setup.exe`` below`n"
            $releaseNotes += "2. Run the installer`n"
            $releaseNotes += "3. Follow the setup wizard`n"
            $releaseNotes += "`n**Requirements:** Windows 10/11, Free Groq API key ([get one here](https://console.groq.com/))`n"
            $releaseNotes += "`n---`n"
            $releaseNotes += "`n📖 [Documentation](https://quicksay.app/beta/getting-started) • 💬 [Feedback](https://quicksay.app/beta/feedback)"

            # Create release tag and title
            $releaseTag = "v$semVer"
            $releaseTitle = "QuickSay Beta $displayVer"

            # Get installer path
            $installerPath = Join-Path $installerDir $installerFilename
            if (-not (Test-Path $installerPath)) {
                Write-Warn "Installer not found at $installerPath — skipping GitHub release"
            } else {
                # Check if release already exists
                $existingRelease = gh release view $releaseTag 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "   Release $releaseTag already exists — deleting and recreating" -ForegroundColor Yellow
                    gh release delete $releaseTag --yes 2>&1 | Out-Null
                    Start-Sleep -Seconds 2
                }

                # Create GitHub release (pre-release for beta)
                Write-Host "   Creating release $releaseTag..." -ForegroundColor White

                # Save release notes to temp file (gh CLI needs file for multiline notes)
                $notesFile = Join-Path $env:TEMP "quicksay_release_notes.md"
                $releaseNotes | Out-File -FilePath $notesFile -Encoding UTF8 -NoNewline

                gh release create $releaseTag `
                    --title $releaseTitle `
                    --notes-file $notesFile `
                    --prerelease `
                    $installerPath

                Remove-Item $notesFile -Force -ErrorAction SilentlyContinue

                if ($LASTEXITCODE -eq 0) {
                    Write-OK "GitHub release created: $releaseTag"
                    Write-OK "Installer uploaded: $installerFilename"

                    # Get release URL
                    $releaseUrl = "https://github.com/lucid4life/QuickSay/releases/tag/$releaseTag"
                    Write-Host "   $releaseUrl" -ForegroundColor Cyan
                } else {
                    Write-Fail "Failed to create GitHub release"
                }
            }
        }
    }

    Pop-Location
} elseif ($SkipGitHub) {
    Write-Step "STEP 8: Skipping GitHub release (--SkipGitHub)"
} else {
    Write-Step "STEP 8: Skipping GitHub release (--SkipCompile)"
}

# =============================================================================
# STEP 9: Summary
# =============================================================================
Write-Step "RELEASE BUILD COMPLETE"

Write-Host ""
Write-Host "   Version:     $semVer ($displayVer)" -ForegroundColor Green
Write-Host "   Files updated:" -ForegroundColor White
Write-Host "     - QuickSay.ahk          (10 locations)" -ForegroundColor Gray
Write-Host "     - onboarding_ui.ahk     (6 locations)" -ForegroundColor Gray
Write-Host "     - settings_ui.ahk       (6 locations)" -ForegroundColor Gray
Write-Host "     - lib/settings-ui.ahk   (3 locations)" -ForegroundColor Gray
Write-Host "     - gui/settings.html     (1 location)" -ForegroundColor Gray
Write-Host "     - setup.iss             (6 locations)" -ForegroundColor Gray
Write-Host "     - LICENSE_AGREEMENT.rtf (2 locations)" -ForegroundColor Gray
Write-Host "     - version.json          (created)" -ForegroundColor Gray
Write-Host "     - pad.xml              (updated)" -ForegroundColor Gray
if ($Changelog -ne "") {
    Write-Host "     - changelog.json        (updated)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "   Website updated:" -ForegroundColor White
Write-Host "     - Footer.astro          (version link)" -ForegroundColor Gray
Write-Host "     - getting-started.astro  (version badge + download link)" -ForegroundColor Gray
Write-Host "     - beta/changelog.astro  (new entry)" -ForegroundColor Gray
Write-Host "     - changelog/v$semVer.mdx (release notes)" -ForegroundColor Gray
Write-Host "     - version.json          (auto-update)" -ForegroundColor Gray
Write-Host "     - pad.xml               (software dirs)" -ForegroundColor Gray

if (-not $SkipCompile) {
    Write-Host ""
    Write-Host "   Compiled:" -ForegroundColor White
    Write-Host "     - QuickSay.exe" -ForegroundColor Gray
    Write-Host "     - QuickSay-Setup.exe" -ForegroundColor Gray
    Write-Host "     - $installerFilename" -ForegroundColor Gray
    if (-not $SkipSign) {
        Write-Host "     (All signed with Azure Trusted Signing)" -ForegroundColor Gray
    }
    Write-Host "     - R2: QuickSay_Beta_v${shortVer}_Setup.exe (website download)" -ForegroundColor Gray
}

if (-not $SkipGitHub -and -not $SkipCompile) {
    Write-Host ""
    Write-Host "   GitHub Release:" -ForegroundColor White
    Write-Host "     - Created: v$semVer (pre-release)" -ForegroundColor Gray
    Write-Host "     - Uploaded: $installerFilename" -ForegroundColor Gray
    Write-Host "     - URL: https://github.com/lucid4life/QuickSay/releases/tag/v$semVer" -ForegroundColor Gray
}

Write-Host ""
Write-Host "   NEXT STEPS:" -ForegroundColor Yellow
Write-Host "     1. Test the installer on a clean machine" -ForegroundColor White
if ($SkipGitHub -or $SkipCompile) {
    Write-Host "     2. Create GitHub release manually" -ForegroundColor White
    Write-Host "     3. Upload installer to Lemon Squeezy" -ForegroundColor White
} else {
    Write-Host "     2. Upload installer to Lemon Squeezy" -ForegroundColor White
}
Write-Host ""
