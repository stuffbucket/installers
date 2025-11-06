# Stuffbucket Installers

This repository contains pre-built installer packages for stuffbucket projects.

## macOS Packages

Download the latest installers from [Releases](https://github.com/stuffbucket/installers/releases).

### Available Packages

1. **stuffbucket-homebrew-*.pkg** - Sets up stuffbucket Homebrew tap
2. **stuffbucket-lima-*.pkg** - Installs Lima virtual machines
3. **stuffbucket-vscode-lima-*.pkg** - Installs VS Code Lima extension

### Installation Order

Install in this sequence:
```bash
# 1. Install Homebrew tap setup
open stuffbucket-homebrew-*.pkg

# 2. Install Lima
open stuffbucket-lima-*.pkg

# 3. (Optional) Install VS Code extension
open stuffbucket-vscode-lima-*.pkg
```

### Verification
Each release includes a SHA256SUMS file for verification:

```bash
shasum -a 256 -c SHA256SUMS
```

### Version Information
Check versions.json in each release for package versions, build timestamps, and source commit hash.

### Alternative Installation
If you prefer using Homebrew directly:

```bash
brew tap stuffbucket/tap
brew install stuffbucket/tap/lima
brew install stuffbucket/tap/vscode-lima
```

### Source
All packages are built from formulas in stuffbucket/homebrew-tap.

### License
See individual package licenses in the source repository.


**Note:** This repository is automatically updated by CI from [stuffbucket/homebrew-tap](https://github.com/stuffbucket/homebrew-tap).
