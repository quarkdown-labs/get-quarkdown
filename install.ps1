#Requires -Version 5.1

param(
    [string]$Prefix = "$env:LOCALAPPDATA\Quarkdown",
    [switch]$NoPM,
    [string]$PuppeteerPrefix = "",
    [string]$Tag = ""
)

$ErrorActionPreference = "Stop"

function Normalize-PathEntry {
    param([string]$PathEntry)

    if ([string]::IsNullOrWhiteSpace($PathEntry)) {
        return ""
    }

    $Trimmed = $PathEntry.Trim()
    try {
        return [System.IO.Path]::GetFullPath($Trimmed).TrimEnd('\\')
    } catch {
        return $Trimmed.TrimEnd('\\')
    }
}

function Test-PathValueContainsEntry {
    param(
        [string]$PathValue,
        [string]$Entry
    )

    $NormalizedEntry = Normalize-PathEntry -PathEntry $Entry
    foreach ($PathPart in ($PathValue -split ';')) {
        if ([string]::IsNullOrWhiteSpace($PathPart)) {
            continue
        }

        $NormalizedPart = Normalize-PathEntry -PathEntry $PathPart
        if ($NormalizedPart.Equals($NormalizedEntry, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

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

Write-Host "Installing Quarkdown to $Prefix..."
Write-Host ""

# Download and extract to a temp directory before touching the existing installation
$TmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())

try {
    New-Item -ItemType Directory -Force -Path $TmpDir | Out-Null

    if (-not $Tag) {
        $DownloadUrl = "https://github.com/iamgio/quarkdown/releases/latest/download/quarkdown.zip"
    } else {
        $DownloadUrl = "https://github.com/iamgio/quarkdown/releases/download/$Tag/quarkdown.zip"
    }

    $ZipPath = "$TmpDir\quarkdown.zip"
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $ZipPath -UseBasicParsing

    Expand-Archive -Path $ZipPath -DestinationPath $TmpDir -Force

    $QdNpmPrefix = "$Prefix\lib"

    # Check if puppeteer path is provided via -PuppeteerPrefix
    if ($PuppeteerPrefix -and (Test-Path "$PuppeteerPrefix\node_modules\puppeteer")) {
        $QdNpmPrefix = $PuppeteerPrefix
        $PuppeteerCacheDir = "$env:USERPROFILE\.cache\puppeteer"
    } else {
        # Install Puppeteer into the staging directory
        $PuppeteerCacheDir = "$TmpDir\quarkdown\lib\puppeteer_cache"
        New-Item -ItemType Directory -Force -Path $PuppeteerCacheDir | Out-Null
        $env:PUPPETEER_CACHE_DIR = $PuppeteerCacheDir
        npm init -y --prefix "$TmpDir\quarkdown\lib" | Out-Null
        npm install puppeteer --prefix "$TmpDir\quarkdown\lib" | Out-Null
        $PuppeteerCacheDir = "$Prefix\lib\puppeteer_cache"
    }

    # Clean previous installation only after download and Puppeteer install succeed
    if (Test-Path $Prefix) {
        if (-not (Test-Path "$Prefix\bin\quarkdown.bat")) {
            Write-Error "$Prefix exists but does not contain a Quarkdown installation. Aborting."
        }
        Write-Host "Removing previous installation at $Prefix..."
        Remove-Item -Path $Prefix -Recurse -Force
    }

    New-Item -ItemType Directory -Force -Path $Prefix | Out-Null
    Copy-Item -Path "$TmpDir\quarkdown\*" -Destination $Prefix -Recurse -Force

    # Resolve JAVA_HOME at install time (works through shims)
    $PrevPref = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $JavaHome = (java -XshowSettings:property -version 2>&1 | Select-String 'java\.home\s*=\s*(.+)').Matches.Groups[1].Value.Trim()
    $ErrorActionPreference = $PrevPref

    # Create wrapper script with baked-in JAVA_HOME and runtime fallback
    $WrapperPath = "$Prefix\quarkdown.cmd"
    $WrapperContent = @"
@echo off
set "JAVA_HOME=$JavaHome"
if exist "%JAVA_HOME%\bin\java.exe" goto :run
set "JAVA_HOME="
for /f "tokens=2 delims==" %%a in ('java -XshowSettings:property -version 2^>^&1 ^| findstr "java.home"') do set "JAVA_HOME=%%a"
if defined JAVA_HOME set "JAVA_HOME=%JAVA_HOME:~1%"
:run
set "PATH=%JAVA_HOME%\bin;$Prefix\bin;%PATH%"
set "QD_NPM_PREFIX=$QdNpmPrefix"
set "PUPPETEER_CACHE_DIR=$PuppeteerCacheDir"
"$Prefix\bin\quarkdown.bat" %*
"@
    Set-Content -Path $WrapperPath -Value $WrapperContent

    # Git Bash does not resolve .cmd wrappers by name; provide an extensionless shim.
    $BashWrapperPath = "$Prefix\quarkdown"
    $BashWrapperContent = @'
#!/usr/bin/env sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/quarkdown.cmd" "$@"
'@
    [System.IO.File]::WriteAllText(
        $BashWrapperPath,
        $BashWrapperContent.Replace("`r`n", "`n"),
        [System.Text.UTF8Encoding]::new($false)
    )

    # Add to user PATH only when the exact installation directory is missing.
    $UserPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
    if (-not (Test-PathValueContainsEntry -PathValue $UserPath -Entry $Prefix)) {
        $NewUserPath = if ([string]::IsNullOrWhiteSpace($UserPath)) { $Prefix } else { "$UserPath;$Prefix" }
        [System.Environment]::SetEnvironmentVariable("PATH", $NewUserPath, "User")

        if (-not (Test-PathValueContainsEntry -PathValue $env:PATH -Entry $Prefix)) {
            $env:PATH = if ([string]::IsNullOrWhiteSpace($env:PATH)) { $Prefix } else { "$env:PATH;$Prefix" }
        }

        Write-Host "Added $Prefix to user PATH."
    }
}
finally {
    if ($TmpDir -and (Test-Path $TmpDir)) {
        try {
            Remove-Item -Path $TmpDir -Recurse -Force -ErrorAction Stop
        } catch {
            Write-Warning "Failed to remove temporary directory $TmpDir: $($_.Exception.Message)"
        }
    }
}

Write-Host ""
Write-Host "Quarkdown is now installed!"
Write-Host ""
Write-Host "To uninstall, remove $Prefix and its entry from your PATH."
