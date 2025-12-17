<#
.SYNOPSIS
    Installs the latest stuffbucket/lima release on Windows.

.DESCRIPTION
    Downloads and installs the latest lima release from GitHub.
    Supports checksum verification, custom install paths, and unattended installation.

.PARAMETER InstallPath
    Target installation directory. Defaults to "$env:LOCALAPPDATA\Programs\lima"

.PARAMETER NoPathUpdate
    Skip adding lima to the user's PATH environment variable.

.PARAMETER Force
    Overwrite existing installation without prompting.

.PARAMETER Version
    Install a specific version instead of latest (e.g., "v2.0.0-beta.0.3")

.EXAMPLE
    # Interactive installation with defaults
    .\install.ps1

.EXAMPLE
    # Unattended installation to custom path
    .\install.ps1 -InstallPath "C:\Tools\lima" -Force

.EXAMPLE
    # Install specific version
    .\install.ps1 -Version "v2.0.0-beta.0.3"

.NOTES
    Requires: PowerShell 5.1+ or PowerShell Core 7+
    Source: https://github.com/stuffbucket/lima
#>

[CmdletBinding()]
param(
    [string]$InstallPath = "$env:LOCALAPPDATA\Programs\lima",
    [switch]$NoPathUpdate,
    [switch]$Force,
    [string]$Version = "latest"
)

# Strict mode for boundary detection
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

#region Configuration
$Script:RepoOwner = "stuffbucket"
$Script:RepoName = "lima"
$Script:GitHubApiBase = "https://api.github.com"
$Script:GitHubReleasesBase = "https://github.com/$Script:RepoOwner/$Script:RepoName/releases"
#endregion

#region Helper Functions

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] " -ForegroundColor Cyan -NoNewline
    Write-Host $Message
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] " -ForegroundColor Green -NoNewline
    Write-Host $Message
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[WARN] " -ForegroundColor Yellow -NoNewline
    Write-Host $Message
}

function Write-Fail {
    param([string]$Message)
    Write-Host "[FAIL] " -ForegroundColor Red -NoNewline
    Write-Host $Message
}

function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-LatestRelease {
    <#
    .DESCRIPTION
        Fetches the latest release metadata from GitHub API.
        Handles rate limiting and network failures at the boundary.
    #>
    param([string]$SpecificVersion)

    $uri = if ($SpecificVersion -eq "latest") {
        "$Script:GitHubApiBase/repos/$Script:RepoOwner/$Script:RepoName/releases/latest"
    } else {
        # Normalize version tag
        $tag = if ($SpecificVersion -match "^v") { $SpecificVersion } else { "v$SpecificVersion" }
        "$Script:GitHubApiBase/repos/$Script:RepoOwner/$Script:RepoName/releases/tags/$tag"
    }

    Write-Info "Fetching release information from GitHub..."

    try {
        # TLS 1.2 minimum - security boundary
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

        $response = Invoke-RestMethod -Uri $uri -Headers @{
            "Accept" = "application/vnd.github+json"
            "User-Agent" = "stuffbucket-lima-installer/1.0"
        } -TimeoutSec 30

        return $response
    }
    catch {
        # Boundary condition: API failure modes
        if ($_.Exception.Response.StatusCode -eq 404) {
            throw "Release not found: $SpecificVersion. Check available versions at $Script:GitHubReleasesBase"
        }
        elseif ($_.Exception.Response.StatusCode -eq 403) {
            throw "GitHub API rate limit exceeded. Try again later or use a GitHub token."
        }
        else {
            throw "Failed to fetch release: $($_.Exception.Message)"
        }
    }
}

function Find-WindowsAsset {
    <#
    .DESCRIPTION
        Identifies the correct Windows binary from release assets.
        Handles architecture detection and naming convention variations.
    #>
    param([object]$Release)

    # Architecture detection - boundary between user's system and our expectations
    $arch = switch ($env:PROCESSOR_ARCHITECTURE) {
        "AMD64" { "amd64", "x64", "x86_64" }
        "ARM64" { "arm64", "aarch64" }
        default { throw "Unsupported architecture: $env:PROCESSOR_ARCHITECTURE" }
    }

    Write-Info "Detected architecture: $($arch[0])"

    # Pattern matching for Windows assets - anacoluthon detection for naming inconsistencies
    $windowsPatterns = @(
        "windows.*$($arch[0]).*\.zip$",
        "windows.*$($arch[1]).*\.zip$",
        "win.*$($arch[0]).*\.zip$",
        "$($arch[0]).*windows.*\.zip$",
        ".*windows.*\.exe$"  # Fallback to standalone exe
    )

    foreach ($pattern in $windowsPatterns) {
        $asset = $Release.assets | Where-Object { $_.name -match $pattern } | Select-Object -First 1
        if ($asset) {
            Write-Info "Found asset: $($asset.name)"
            return $asset
        }
    }

    # Boundary: No compatible asset found
    $available = ($Release.assets | ForEach-Object { $_.name }) -join ", "
    throw "No Windows binary found for $($arch[0]). Available assets: $available"
}

function Get-FileChecksum {
    param([string]$FilePath)
    return (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash.ToLower()
}

function Get-ExpectedChecksum {
    <#
    .DESCRIPTION
        Attempts to fetch checksum from release assets (SHA256SUMS file).
        Handles various checksum file naming conventions.
    #>
    param(
        [object]$Release,
        [string]$AssetName
    )

    $checksumPatterns = @("SHA256SUMS", "checksums.txt", "sha256sums.txt", "$AssetName.sha256")

    foreach ($pattern in $checksumPatterns) {
        $checksumAsset = $Release.assets | Where-Object { $_.name -eq $pattern } | Select-Object -First 1
        if ($checksumAsset) {
            try {
                $checksumContent = Invoke-RestMethod -Uri $checksumAsset.browser_download_url -TimeoutSec 30
                # Parse checksum file - format: "hash  filename" or "hash filename"
                $lines = $checksumContent -split "`n"
                foreach ($line in $lines) {
                    if ($line -match "^([a-f0-9]{64})\s+\*?(.+)$") {
                        if ($Matches[2].Trim() -eq $AssetName) {
                            return $Matches[1].ToLower()
                        }
                    }
                }
            }
            catch {
                Write-Warn "Could not fetch checksum file: $pattern"
            }
        }
    }

    return $null
}

function Install-LimaFiles {
    <#
    .DESCRIPTION
        Extracts and installs lima files to the target directory.
        Handles existing installations and permission boundaries.
    #>
    param(
        [string]$ArchivePath,
        [string]$TargetPath,
        [bool]$ForceOverwrite
    )

    # Pre-flight check: existing installation
    if (Test-Path $TargetPath) {
        $existingExe = Join-Path $TargetPath "bin\lima.exe"
        if (Test-Path $existingExe) {
            if (-not $ForceOverwrite) {
                $response = Read-Host "Existing installation found at $TargetPath. Overwrite? [y/N]"
                if ($response -notmatch "^[Yy]") {
                    throw "Installation cancelled by user."
                }
            }
            Write-Info "Removing existing installation..."
            Remove-Item -Path $TargetPath -Recurse -Force
        }
    }

    # Create target directory
    New-Item -ItemType Directory -Path $TargetPath -Force | Out-Null

    Write-Info "Extracting to $TargetPath..."

    if ($ArchivePath -match "\.zip$") {
        Expand-Archive -Path $ArchivePath -DestinationPath $TargetPath -Force
    }
    elseif ($ArchivePath -match "\.exe$") {
        # Standalone executable
        $binPath = Join-Path $TargetPath "bin"
        New-Item -ItemType Directory -Path $binPath -Force | Out-Null
        Copy-Item -Path $ArchivePath -Destination (Join-Path $binPath "lima.exe")
    }
    else {
        throw "Unsupported archive format: $ArchivePath"
    }

    # Verify installation - boundary check
    $expectedBin = Join-Path $TargetPath "bin\lima.exe"
    
    # Handle different archive structures
    if (-not (Test-Path $expectedBin)) {
        # Try to find lima.exe in extracted content
        $foundExe = Get-ChildItem -Path $TargetPath -Filter "lima.exe" -Recurse | Select-Object -First 1
        if ($foundExe) {
            # Restructure if needed
            $binPath = Join-Path $TargetPath "bin"
            if (-not (Test-Path $binPath)) {
                New-Item -ItemType Directory -Path $binPath -Force | Out-Null
            }
            Move-Item -Path $foundExe.FullName -Destination $expectedBin -Force
            Write-Info "Reorganized installation structure."
        }
        else {
            throw "Installation verification failed: lima.exe not found in archive."
        }
    }

    Write-Success "Files installed to $TargetPath"
}

function Update-UserPath {
    <#
    .DESCRIPTION
        Adds lima to user's PATH environment variable.
        Handles idempotency and path format boundaries.
    #>
    param([string]$BinPath)

    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    $pathParts = $currentPath -split ";"

    # Idempotency check - don't add if already present
    if ($pathParts -contains $BinPath) {
        Write-Info "PATH already contains $BinPath"
        return
    }

    # Append to PATH
    $newPath = "$currentPath;$BinPath"
    [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")

    # Update current session
    $env:PATH = "$env:PATH;$BinPath"

    Write-Success "Added $BinPath to user PATH"
    Write-Warn "Restart your terminal or run 'refreshenv' to use lima immediately."
}

#endregion

#region Main Installation Flow

function Install-Lima {
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║         stuffbucket/lima Installer for Windows           ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    # Boundary: Administrator check (warning, not blocker)
    if (Test-Administrator) {
        Write-Warn "Running as Administrator. lima will be installed to user directory by default."
        Write-Warn "Use -InstallPath to specify a system-wide location if intended."
    }

    # Step 1: Fetch release metadata
    $release = Get-LatestRelease -SpecificVersion $Version
    Write-Success "Found release: $($release.tag_name)"

    # Step 2: Find Windows asset
    $asset = Find-WindowsAsset -Release $release
    $downloadUrl = $asset.browser_download_url
    $assetName = $asset.name

    # Step 3: Create temp directory for download
    $tempDir = Join-Path $env:TEMP "lima-install-$(Get-Date -Format 'yyyyMMddHHmmss')"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    $downloadPath = Join-Path $tempDir $assetName

    try {
        # Step 4: Download asset
        Write-Info "Downloading $assetName ($([math]::Round($asset.size / 1MB, 2)) MB)..."
        
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("User-Agent", "stuffbucket-lima-installer/1.0")
        $webClient.DownloadFile($downloadUrl, $downloadPath)

        Write-Success "Download complete."

        # Step 5: Verify checksum (if available)
        $expectedHash = Get-ExpectedChecksum -Release $release -AssetName $assetName
        if ($expectedHash) {
            Write-Info "Verifying checksum..."
            $actualHash = Get-FileChecksum -FilePath $downloadPath
            if ($actualHash -ne $expectedHash) {
                throw "Checksum verification failed!`nExpected: $expectedHash`nActual: $actualHash"
            }
            Write-Success "Checksum verified."
        }
        else {
            Write-Warn "No checksum file found. Skipping verification."
        }

        # Step 6: Install files
        Install-LimaFiles -ArchivePath $downloadPath -TargetPath $InstallPath -ForceOverwrite $Force

        # Step 7: Update PATH
        if (-not $NoPathUpdate) {
            $binPath = Join-Path $InstallPath "bin"
            Update-UserPath -BinPath $binPath
        }

        # Step 8: Verification
        Write-Host ""
        Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Green
        Write-Success "Installation complete!"
        Write-Host ""
        Write-Info "Installed version: $($release.tag_name)"
        Write-Info "Location: $InstallPath"
        Write-Host ""
        Write-Info "Try running: lima --version"
        Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Green
    }
    finally {
        # Cleanup temp files
        if (Test-Path $tempDir) {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# Entry point
try {
    Install-Lima
}
catch {
    Write-Host ""
    Write-Fail $_.Exception.Message
    Write-Host ""
    exit 1
}
#endregion
