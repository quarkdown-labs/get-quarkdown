#Requires -Version 5.1

param(
    [string]$Prefix = "$env:LOCALAPPDATA\Quarkdown",
    [switch]$NoPM,
    [string]$PuppeteerPrefix = "",
    [string]$Tag = ""
)

$ErrorActionPreference = "Stop"

# Check Java
if (-not (Get-Command java -ErrorAction SilentlyContinue)) {
    Write-Host "Java not found."

    if (-not $NoPM) {
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Host ""
            Write-Host "Installing Java using winget..."
            winget install --id Microsoft.OpenJDK.17 --accept-source-agreements --accept-package-agreements
        } elseif (Get-Command choco -ErrorAction SilentlyContinue) {
            Write-Host ""
            Write-Host "Installing Java using choco..."
            choco install openjdk17 -y
        } elseif (Get-Command scoop -ErrorAction SilentlyContinue) {
            Write-Host ""
            Write-Host "Installing Java using scoop..."
            scoop bucket add java
            scoop install openjdk17
        }
    }

    # Refresh PATH after install
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")

    if (-not (Get-Command java -ErrorAction SilentlyContinue)) {
        Write-Error "Java is still not installed. Please install JDK 17 manually."
    }
}

# Check Node.js
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Host "Node.js not found."

    if (-not $NoPM) {
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Host ""
            Write-Host "Installing Node.js using winget..."
            winget install --id OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements
        } elseif (Get-Command choco -ErrorAction SilentlyContinue) {
            Write-Host ""
            Write-Host "Installing Node.js using choco..."
            choco install nodejs-lts -y
        } elseif (Get-Command scoop -ErrorAction SilentlyContinue) {
            Write-Host ""
            Write-Host "Installing Node.js using scoop..."
            scoop install nodejs-lts
        }
    }

    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")

    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        Write-Error "Node.js is still not installed. Please install Node.js manually."
    }
}

# Check npm
if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    Write-Host "npm not found."

    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")

    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        Write-Error "npm is still not installed. Please install npm manually."
    }
}

$QdNpmPrefix = "$Prefix\lib"

# Check if puppeteer path is provided via -PuppeteerPrefix
if ($PuppeteerPrefix -and (Test-Path "$PuppeteerPrefix\node_modules\puppeteer")) {
    $QdNpmPrefix = $PuppeteerPrefix
    $PuppeteerCacheDir = "$env:USERPROFILE\.cache\puppeteer"
} else {
    # Install Puppeteer using npm
    $PuppeteerCacheDir = "$Prefix\lib\puppeteer_cache"
    New-Item -ItemType Directory -Force -Path $PuppeteerCacheDir | Out-Null
    $env:PUPPETEER_CACHE_DIR = $PuppeteerCacheDir
    npm init -y --prefix "$Prefix\lib" | Out-Null
    npm install puppeteer --prefix "$Prefix\lib" | Out-Null
    npm install --prefix "$Prefix\lib\node_modules\puppeteer"
}

Write-Host "Installing Quarkdown to $Prefix..."
Write-Host ""

$TmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Force -Path $TmpDir | Out-Null

# Determine download URL based on tag option
if (-not $Tag) {
    $DownloadUrl = "https://github.com/iamgio/quarkdown/releases/latest/download/quarkdown.zip"
} else {
    $DownloadUrl = "https://github.com/iamgio/quarkdown/releases/download/$Tag/quarkdown.zip"
}

$ZipPath = "$TmpDir\quarkdown.zip"
Invoke-WebRequest -Uri $DownloadUrl -OutFile $ZipPath -UseBasicParsing

Expand-Archive -Path $ZipPath -DestinationPath $TmpDir -Force

New-Item -ItemType Directory -Force -Path $Prefix | Out-Null
Copy-Item -Path "$TmpDir\quarkdown\*" -Destination $Prefix -Recurse -Force

# Create wrapper script in the install directory
$WrapperPath = "$Prefix\quarkdown.cmd"
$WrapperContent = @"
@echo off
set "QD_NPM_PREFIX=$QdNpmPrefix"
set "PUPPETEER_CACHE_DIR=$PuppeteerCacheDir"
"$Prefix\bin\quarkdown.bat" %*
"@
Set-Content -Path $WrapperPath -Value $WrapperContent

# Add to user PATH if not already present
$UserPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
if ($UserPath -notlike "*$Prefix*") {
    [System.Environment]::SetEnvironmentVariable("PATH", "$UserPath;$Prefix", "User")
    $env:PATH = "$env:PATH;$Prefix"
    Write-Host "Added $Prefix to user PATH."
}

Remove-Item -Path $TmpDir -Recurse -Force

Write-Host ""
Write-Host "Quarkdown is now installed!"
Write-Host ""
Write-Host "To uninstall, remove $Prefix and its entry from your PATH."
