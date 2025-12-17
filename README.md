# Stuffbucket Installers

Pre-built installer packages for stuffbucket projects.

## Platforms

| Platform | Description |
|----------|-------------|
| [**macOS**](macos/README.md) | `.pkg` installers via Homebrew tap |
| [**Windows**](windows/lima/README.md) | PowerShell install scripts |

## Quick Install

### macOS

```bash
# Via Homebrew (recommended)
brew tap stuffbucket/tap
brew install stuffbucket/tap/lima

# Or download .pkg from Releases
open stuffbucket-lima-2.pkg
```

### Windows

```powershell
irm https://raw.githubusercontent.com/stuffbucket/installers/main/windows/lima/install.ps1 | iex
```

## VS Code Extension

The Lima extension is available in the VS Code marketplace:

```bash
code --install-extension stuffbucket.vscode-lima
```

## License

See individual package licenses in the source repositories.
