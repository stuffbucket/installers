<#
.SYNOPSIS
    Installs the latest stuffbucket/lima release on Windows.

.DESCRIPTION
    Downloads and installs the latest lima release from GitHub,
    including the main binaries and additional guest agents.

.PARAMETER InstallPath
    Target installation directory. Defaults to "$env:LOCALAPPDATA\Programs\lima"

.PARAMETER NoPathUpdate
    Skip adding lima to the user's PATH environment variable.

.PARAMETER Force
    Overwrite existing installation without prompting.

.PARAMETER Version
    Install a specific version instead of latest (e.g., "v2.0.0-beta.0.3")

.EXAMPLE
    .\install.ps1
    .\install.ps1 -InstallPath "C:\Tools\lima" -Force
    .\install.ps1 -Version "v2.0.0-beta.0.3"
#>

[CmdletBinding()]
param(
    [string]$InstallPath = "$env:LOCALAPPDATA\Programs\lima",
    [switch]$NoPathUpdate,
    [switch]$Force,
    [string]$Version = "latest"
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$RepoOwner = "stuffbucket"
$RepoName = "lima"

function Get-LatestRelease {
    param([string]$SpecificVersion)

    if ($SpecificVersion -eq "latest") {
        $uri = "https://api.github.com/repos/$RepoOwner/$RepoName/releases/latest"
    } else {
        $tag = if ($SpecificVersion -match "^v") { $SpecificVersion } else { "v$SpecificVersion" }
        $uri = "https://api.github.com/repos/$RepoOwner/$RepoName/releases/tags/$tag"
    }

    Write-Host "[INFO] Fetching release from GitHub..." -ForegroundColor Cyan
    $headers = @{ "User-Agent" = "lima-installer" }
    return Invoke-RestMethod -Uri $uri -Headers $headers -TimeoutSec 30
}

function Find-WindowsAssets {
    <#
    .DESCRIPTION
        Finds both the main lima binary and guest agents for Windows.
        Returns a hashtable with 'main' and 'guestagents' keys.
    #>
    param([object]$Release)

    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "aarch64" } else { "x86_64" }
    Write-Host "[INFO] Architecture: $arch" -ForegroundColor Cyan

    $result = @{
        main = $null
        guestagents = $null
    }

    foreach ($asset in $Release.assets) {
        # Match main lima binary (not guestagents)
        if ($asset.name -match "^lima-[^-]+-Windows-$arch\.zip$" -and $asset.name -notmatch "guestagents") {
            $result.main = $asset
        }
        # Match guest agents
        if ($asset.name -match "lima-additional-guestagents.*Windows-$arch\.zip$") {
            $result.guestagents = $asset
        }
    }

    if (-not $result.main) {
        throw "No Windows lima binary found for $arch. Available: $($Release.assets.name -join ', ')"
    }

    if (-not $result.guestagents) {
        Write-Host "[WARN] No guest agents found for $arch" -ForegroundColor Yellow
    }

    return $result
}

function Install-LimaFiles {
    <#
    .DESCRIPTION
        Extracts and installs lima files to the target directory.
        Handles both main binary and guest agents archives.
    #>
    param(
        [string]$MainArchivePath,
        [string]$GuestAgentsArchivePath,
        [string]$TargetPath,
        [switch]$ForceOverwrite
    )

    if ((Test-Path $TargetPath) -and -not $ForceOverwrite) {
        $response = Read-Host "Existing installation at $TargetPath. Overwrite? [y/N]"
        if ($response -notmatch "^[Yy]") {
            throw "Installation cancelled."
        }
    }

    if (Test-Path $TargetPath) {
        Remove-Item -Path $TargetPath -Recurse -Force
    }

    New-Item -ItemType Directory -Path $TargetPath -Force | Out-Null

    # Extract main lima archive
    Write-Host "[INFO] Extracting lima binaries to $TargetPath..." -ForegroundColor Cyan
    Expand-Archive -Path $MainArchivePath -DestinationPath $TargetPath -Force

    # Extract guest agents (overlay on top of main installation)
    if ($GuestAgentsArchivePath -and (Test-Path $GuestAgentsArchivePath)) {
        Write-Host "[INFO] Extracting guest agents..." -ForegroundColor Cyan
        Expand-Archive -Path $GuestAgentsArchivePath -DestinationPath $TargetPath -Force
        Write-Host "[OK] Guest agents installed." -ForegroundColor Green
    }

    # Verify lima.exe exists somewhere in the extracted content
    $limaExe = Get-ChildItem -Path $TargetPath -Filter "lima.exe" -Recurse | Select-Object -First 1
    if (-not $limaExe) {
        throw "lima.exe not found in archive."
    }

    # Ensure bin directory structure
    $binPath = Join-Path $TargetPath "bin"
    $expectedExe = Join-Path $binPath "lima.exe"

    if ($limaExe.FullName -ne $expectedExe) {
        New-Item -ItemType Directory -Path $binPath -Force | Out-Null
        Move-Item -Path $limaExe.FullName -Destination $expectedExe -Force
    }

    Write-Host "[OK] Installed to $TargetPath" -ForegroundColor Green
}

function Update-UserPath {
    param([string]$BinPath)

    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if (-not $currentPath) {
        $currentPath = ""
    }
    if ($currentPath -split ";" -contains $BinPath) {
        Write-Host "[INFO] PATH already contains $BinPath" -ForegroundColor Cyan
        return
    }

    $newPath = if ($currentPath) { "$currentPath;$BinPath" } else { $BinPath }
    [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
    $env:PATH = "$env:PATH;$BinPath"
    Write-Host "[OK] Added $BinPath to PATH" -ForegroundColor Green
    Write-Host "[WARN] Restart terminal to use lima." -ForegroundColor Yellow
}

# Main
Write-Host ""
Write-Host "--- stuffbucket/lima Installer ---" -ForegroundColor Cyan
Write-Host ""

try {
    $release = Get-LatestRelease -SpecificVersion $Version
    Write-Host "[OK] Found: $($release.tag_name)" -ForegroundColor Green

    $assets = Find-WindowsAssets -Release $release
    Write-Host "[INFO] Main: $($assets.main.name)" -ForegroundColor Cyan
    if ($assets.guestagents) {
        Write-Host "[INFO] Guest Agents: $($assets.guestagents.name)" -ForegroundColor Cyan
    }

    $tempDir = Join-Path $env:TEMP "lima-install"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    # Download main lima archive
    $mainDownloadPath = Join-Path $tempDir $assets.main.name
    $sizeMB = [math]::Round($assets.main.size / 1048576, 2)
    Write-Host "[INFO] Downloading lima ($sizeMB MB)..." -ForegroundColor Cyan

    $webClient = New-Object System.Net.WebClient
    $webClient.Headers.Add("User-Agent", "lima-installer")
    $webClient.DownloadFile($assets.main.browser_download_url, $mainDownloadPath)
    Write-Host "[OK] Lima download complete." -ForegroundColor Green

    # Download guest agents if available
    $guestAgentsDownloadPath = $null
    if ($assets.guestagents) {
        $guestAgentsDownloadPath = Join-Path $tempDir $assets.guestagents.name
        $sizeMB = [math]::Round($assets.guestagents.size / 1048576, 2)
        Write-Host "[INFO] Downloading guest agents ($sizeMB MB)..." -ForegroundColor Cyan
        $webClient.DownloadFile($assets.guestagents.browser_download_url, $guestAgentsDownloadPath)
        Write-Host "[OK] Guest agents download complete." -ForegroundColor Green
    }

    Install-LimaFiles -MainArchivePath $mainDownloadPath -GuestAgentsArchivePath $guestAgentsDownloadPath -TargetPath $InstallPath -ForceOverwrite:$Force

    if (-not $NoPathUpdate) {
        Update-UserPath -BinPath (Join-Path $InstallPath "bin")
    }

    Write-Host ""
    Write-Host "[OK] Installation complete!" -ForegroundColor Green
    Write-Host "[INFO] Version: $($release.tag_name)" -ForegroundColor Cyan
    Write-Host "[INFO] Location: $InstallPath" -ForegroundColor Cyan
    Write-Host "[INFO] Run: lima --version" -ForegroundColor Cyan
    Write-Host ""
}
catch {
    Write-Host "[FAIL] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
finally {
    $tempDir = Join-Path $env:TEMP "lima-install"
    if (Test-Path $tempDir) {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
