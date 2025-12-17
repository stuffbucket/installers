# Lima Installer for Windows

PowerShell-based installer for [stuffbucket/lima](https://github.com/stuffbucket/lima) on Windows.

## Opening PowerShell on Windows 11

> **Note:** PowerShell scripts (`.ps1` files) cannot be run by double-clicking in File Explorer—they open in Notepad instead. You must run them from within PowerShell.

### Method 1: From Start Menu

1. Press **Win** key or click Start
2. Type **PowerShell**
3. Click **Windows PowerShell** (no admin needed for user install)

### Method 2: From File Explorer

1. Navigate to the folder where you want to run the script
2. Click the address bar and type `powershell`, then press **Enter**
3. PowerShell opens in that directory

### Method 3: Right-Click Context Menu

1. Right-click in empty space in File Explorer (or **Shift + Right-click**)
2. Select **Open in Terminal** (opens Windows Terminal with PowerShell)

### Method 4: Windows Terminal

1. Press **Win + X**
2. Select **Terminal** (or **Windows Terminal**)

### Administrator Permissions

**Not required** for the default installation (installs to your user folder). If you want to install system-wide, right-click PowerShell and select **Run as administrator**.

---

## Quick Install

Run in PowerShell:

```powershell
irm https://raw.githubusercontent.com/stuffbucket/installers/main/windows/lima/install.ps1 | iex
```

Or download and run manually:

```powershell
# Download
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/stuffbucket/installers/main/windows/lima/install.ps1" -OutFile "install.ps1"

# Run
.\install.ps1
```

## Installation Options

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-InstallPath` | `%LOCALAPPDATA%\Programs\lima` | Target installation directory |
| `-NoPathUpdate` | `$false` | Skip adding lima to PATH |
| `-Force` | `$false` | Overwrite existing installation without prompting |
| `-Version` | `latest` | Install specific version (e.g., `v2.0.0-beta.0.3`) |

### Examples

```powershell
# Install latest to default location
.\install.ps1

# Install to custom directory
.\install.ps1 -InstallPath "C:\Tools\lima"

# Install specific version silently
.\install.ps1 -Version "v2.0.0-beta.0.3" -Force

# Install without modifying PATH
.\install.ps1 -NoPathUpdate
```

## Requirements

- Windows 10/11 or Windows Server 2016+
- PowerShell 5.1+ or PowerShell Core 7+
- Internet connectivity to GitHub

## What Gets Installed

```
%LOCALAPPDATA%\Programs\lima\
├── bin\
│   └── lima.exe
└── [additional files from release]
```

The installer automatically adds `lima\bin` to your user PATH.

## Verification

After installation:

```powershell
# Check version
lima --version

# Verify PATH
where.exe lima
```

## Uninstallation

```powershell
# Remove installation directory
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\Programs\lima"

# Remove from PATH (manual step)
# Edit System Properties > Environment Variables > User PATH
```

## Troubleshooting

### "Execution of scripts is disabled"

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### "lima not found" after installation

Restart your terminal or run:

```powershell
$env:PATH = [Environment]::GetEnvironmentVariable("PATH", "User") + ";" + [Environment]::GetEnvironmentVariable("PATH", "Machine")
```

### Proxy/Network Issues

```powershell
# Set proxy if needed
[System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
```

## Security Notes

- Downloads are verified against SHA256 checksums when available
- Uses TLS 1.2+ for all network connections
- Installs to user directory (no admin required)
- Script can be reviewed before execution

## Future: Winget Package

A Winget package submission is planned. Once approved:

```powershell
winget install stuffbucket.lima
```

## License

See [stuffbucket/lima](https://github.com/stuffbucket/lima) for license information.
