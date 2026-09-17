<#
.SYNOPSIS
    terminal-rice installer — PowerShell profile + WezTerm config

.DESCRIPTION
    Downloads a snapshot of the terminal-rice repo and installs the
    PowerShell profile and/or WezTerm config, backing up anything that
    already exists first. No external dependencies required.

.NOTES
    Usage (from a fresh Windows install, in PowerShell):
        irm https://raw.githubusercontent.com/<YOUR_USER>/terminal-rice/main/install.ps1 | iex

    Prefer to inspect before running it? Open the same URL in a browser,
    or clone the repo and read this file directly.
#>

$ErrorActionPreference = 'Stop'

# ---- Config: update these to match your repo -------------------------------
$RepoUser = "itsWindi"
$RepoName = "terminal-rice"
$Branch   = "master"
$ZipUrl   = "https://github.com/$RepoUser/$RepoName/archive/refs/heads/$Branch.zip"

$NerdFontWingetId = "DEVCOM.JetBrainsMonoNerdFont"
# Different Nerd Fonts packagings register under different names — some use the
# full "Nerd Font" suffix, others the abbreviated "NF" (e.g. "JetBrainsMono NF Medium").
# Match both so a font already installed some other way is still detected correctly.
$NerdFontPatterns = @("*JetBrains*Nerd*", "*JetBrainsMono*NF*")
# ------------------------------------------------------------------------------

function Write-Step  ($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Warn2 ($msg) { Write-Host "!!  $msg" -ForegroundColor Yellow }
function Write-Ok    ($msg) { Write-Host "OK  $msg" -ForegroundColor Green }

function Backup-Existing {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Label)

    if (-not (Test-Path $Path)) { return }

    $stamp   = Get-Date -Format "yyyyMMdd-HHmmss"
    $backup  = "$Path.backup-$stamp"
    $suffix  = 1
    while (Test-Path $backup) {
        $backup = "$Path.backup-$stamp-$suffix"
        $suffix++
    }

    Move-Item -Path $Path -Destination $backup -Force
    Write-Warn2 "Existing $Label found — backed up to:`n    $backup"
}

function Invoke-Winget {
    # Runs a winget install and returns $true/$false based on the actual exit code,
    # since winget is an external exe and a failed install usually does NOT throw
    # a terminating error that try/catch would catch.
    param([Parameter(Mandatory)][string[]]$WingetArgs)

    & winget @WingetArgs
    return ($LASTEXITCODE -eq 0)
}

function Test-NerdFontInstalled {
    param([string[]]$Patterns = $NerdFontPatterns)

    # Fonts can be registered per-user (HKCU — e.g. installed via the "Install for me
    # only" right-click option, which is what the per-user AppData\...\Fonts path means)
    # or machine-wide (HKLM), so both locations need checking.
    $fontKeys = @(
        'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts',
        'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
    )
    foreach ($key in $fontKeys) {
        if (Test-Path $key) {
            $names = (Get-ItemProperty -Path $key).PSObject.Properties.Name
            foreach ($pattern in $Patterns) {
                if ($names -like $pattern) { return $true }
            }
        }
    }
    return $false
}

Write-Host ""
Write-Host "terminal-rice installer" -ForegroundColor Magenta
Write-Host "Source: https://github.com/$RepoUser/$RepoName ($Branch)`n"

# ---- Ask what to install ----------------------------------------------------
$choice = $null
while ($choice -notin @('1', '2', '3')) {
    Write-Host "What would you like to install?"
    Write-Host "  [1] PowerShell profile only"
    Write-Host "  [2] WezTerm config only"
    Write-Host "  [3] Both"
    $choice = Read-Host "Enter choice (1/2/3)"
}
$installPwsh = $choice -in @('1', '3')
$installWez  = $choice -in @('2', '3')

# ---- Download + extract repo snapshot --------------------------------------
Write-Step "Downloading repo snapshot..."
$tempDir = Join-Path $env:TEMP "terminal-rice-install-$(Get-Random)"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
$zipPath = Join-Path $tempDir "repo.zip"

try {
    Invoke-WebRequest -Uri $ZipUrl -OutFile $zipPath -UseBasicParsing
}
catch {
    Write-Error "Failed to download $ZipUrl`n$_"
    exit 1
}

Write-Step "Extracting..."
Expand-Archive -Path $zipPath -DestinationPath $tempDir -Force

$extractedRoot = Get-ChildItem -Path $tempDir -Directory |
    Where-Object { $_.Name -like "$RepoName-*" } |
    Select-Object -First 1

if (-not $extractedRoot) {
    Write-Error "Could not find extracted repo folder inside the zip."
    exit 1
}
$sourceRoot = $extractedRoot.FullName

# ---- Install PowerShell profile (targets PowerShell 7 specifically) --------
if ($installPwsh) {
    $applyPwshProfile = $false

    Write-Step "Checking for PowerShell 7..."
    $pwshInstalled = [bool](Get-Command pwsh -ErrorAction SilentlyContinue)

    if ($pwshInstalled) {
        Write-Ok "PowerShell 7 is already installed."
        $applyPwshProfile = $true
    }
    else {
        Write-Warn2 "This profile is written for PowerShell 7 and may not work correctly on Windows PowerShell 5.1."
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if ($winget) {
            $resp = Read-Host "PowerShell 7 not found. Install it now via winget? (Y/n)"
            if ($resp -eq '' -or $resp -match '^[Yy]') {
                Write-Step "Installing PowerShell 7 via winget..."
                if (Invoke-Winget @('install', '--id', 'Microsoft.PowerShell', '-e', '--accept-source-agreements', '--accept-package-agreements')) {
                    Write-Ok "PowerShell 7 installed. Open a new 'pwsh' window to use it."
                    # Don't re-check via Get-Command here — PATH won't refresh until a new
                    # shell opens, so a successful winget exit code is the real signal.
                    $applyPwshProfile = $true
                }
                else {
                    Write-Warn2 "winget install failed. Get PowerShell 7 manually from:"
                    Write-Warn2 "    https://aka.ms/powershell-release?tag=stable"
                    Write-Warn2 "Skipping PowerShell profile install."
                }
            }
            else {
                Write-Warn2 "Skipping PowerShell 7 install and profile setup."
            }
        }
        else {
            Write-Warn2 "winget is unavailable on this system. Get PowerShell 7 manually from:"
            Write-Warn2 "    https://aka.ms/powershell-release?tag=stable"
            Write-Warn2 "Skipping PowerShell profile install."
        }
    }

    if ($applyPwshProfile) {
        Write-Step "Installing PowerShell profile..."
        $srcProfileDir = Join-Path $sourceRoot "powershell"
        $srcProfile = Get-ChildItem -Path $srcProfileDir -Filter "*.ps1" -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if (-not $srcProfile) {
            Write-Warn2 "No .ps1 file found in the 'powershell' folder — skipping."
        }
        else {
            # Target PS7's CurrentUserAllHosts profile explicitly (Documents\PowerShell\profile.ps1),
            # rather than $PROFILE — which would point at Windows PowerShell 5.1's path if this
            # installer happens to be running under 5.1 (the default on a fresh Windows install).
            $docs = [Environment]::GetFolderPath('MyDocuments')
            $destDir = Join-Path $docs "PowerShell"
            $destProfile = Join-Path $destDir "profile.ps1"

            if (-not (Test-Path $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }

            Backup-Existing -Path $destProfile -Label "PowerShell profile"
            Copy-Item -Path $srcProfile.FullName -Destination $destProfile -Force
            Write-Ok "PowerShell profile installed to:`n    $destProfile"
        }
    }
}

# ---- Install WezTerm config (+ install WezTerm and required font if missing) -----
if ($installWez) {
    $applyWezConfig = $false

    Write-Step "Checking for WezTerm..."
    $wezInstalled = [bool](Get-Command wezterm -ErrorAction SilentlyContinue)

    if ($wezInstalled) {
        Write-Ok "WezTerm is already installed."
        $applyWezConfig = $true
    }
    else {
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if ($winget) {
            $resp = Read-Host "WezTerm not found. Install it now via winget? (Y/n)"
            if ($resp -eq '' -or $resp -match '^[Yy]') {
                Write-Step "Installing WezTerm via winget..."
                if (Invoke-Winget @('install', '--id', 'wez.wezterm', '-e', '--accept-source-agreements', '--accept-package-agreements')) {
                    Write-Ok "WezTerm installed via winget."
                    $applyWezConfig = $true
                }
                else {
                    Write-Warn2 "winget install failed. Download WezTerm manually from:"
                    Write-Warn2 "    https://wezterm.org/installation.html"
                }
            }
            else {
                Write-Warn2 "Skipping WezTerm install."
            }
        }
        else {
            Write-Warn2 "WezTerm not found and winget is unavailable on this system."
            Write-Warn2 "Download it manually from:"
            Write-Warn2 "    https://wezterm.org/installation.html"
        }
    }

    if (-not $applyWezConfig) {
        Write-Warn2 "WezTerm is not installed — stopping WezTerm setup."
    }
    else {
        # ---- JetBrains Mono Nerd Font (required by the WezTerm config) ----
        Write-Step "Checking for JetBrains Mono Nerd Font..."
        if (Test-NerdFontInstalled) {
            Write-Ok "JetBrains Mono Nerd Font is already installed."
        }
        else {
            Write-Warn2 "JetBrains Mono Nerd Font not found (the WezTerm config expects it, Medium weight)."
            $winget = Get-Command winget -ErrorAction SilentlyContinue
            if ($winget) {
                $resp = Read-Host "Install it now via winget? (Y/n)"
                if ($resp -eq '' -or $resp -match '^[Yy]') {
                    Write-Step "Installing JetBrains Mono Nerd Font via winget..."
                    if (Invoke-Winget @('install', '--id', $NerdFontWingetId, '-e', '--accept-source-agreements', '--accept-package-agreements')) {
                        Write-Ok "Font installed (includes the Medium weight used by the config)."
                    }
                    else {
                        Write-Warn2 "winget install failed. Get the font manually from:"
                        Write-Warn2 "    https://www.nerdfonts.com/font-downloads (JetBrainsMono)"
                    }
                }
                else {
                    Write-Warn2 "Skipping font install — WezTerm may render icons/glyphs incorrectly without it."
                }
            }
            else {
                Write-Warn2 "winget is unavailable. Get the font manually from:"
                Write-Warn2 "    https://www.nerdfonts.com/font-downloads (JetBrainsMono)"
            }
        }

        # ---- Config copy ----
        Write-Step "Installing WezTerm config..."
        $srcWezDir  = Join-Path $sourceRoot "wezterm"
        $destWezDir = Join-Path $env:USERPROFILE ".config\wezterm"

        if (-not (Test-Path $srcWezDir)) {
            Write-Warn2 "No 'wezterm' folder found in the repo snapshot — skipping."
        }
        else {
            Backup-Existing -Path $destWezDir -Label "WezTerm config folder"
            New-Item -ItemType Directory -Path (Split-Path $destWezDir -Parent) -Force | Out-Null
            Copy-Item -Path $srcWezDir -Destination $destWezDir -Recurse -Force
            Write-Ok "WezTerm config installed to:`n    $destWezDir"
        }
    }
}

# ---- Cleanup -----------------------------------------------------------------
Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Done. Restart your terminal to pick up the changes." -ForegroundColor Magenta
