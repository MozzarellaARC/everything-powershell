
## Everything PowerShell (epwsh)

***Binary locations:***
```
exe
C:\Users\UserName
C:\Program Files
C:\Users\UserName\AppData\Local\Programs
C:\Users\UserName\AppData\Local\Microsoft\WinGet\Packages

ilk
C:\ProgramData\Microsoft\Windows\Start Menu\Programs
C:\Users\UserName\AppData\Roaming\Microsoft\Windows\Start Menu\Programs
```

Minimal PowerShell 7 utilities to quickly launch applications, open their install directories, and search the filesystem from the terminal on Windows 11. Originally backed by the (now removed) Everything SDK; now uses the blazingly fast [`fd`](https://github.com/sharkdp/fd) exclusively.

### Deprecation Note
The embedded Everything SDK integration was removed. The project keeps its name for continuity. Search now routes solely through `fd`.

## Features
* `open <name>` – Launch an application (Start Menu shortcut match first, then executable discovery).
* `open-dir <name>` – Open the install folder of an executable.
* `es <pattern>` – General file/dir search (fd) with extension filtering, scope paths, and limits.
* Caching of Start Menu shortcuts for fast repeated launches.
* Fast, deterministic search powered by `fd` (required).

## How It Works (High Level)
1. Start Menu Parsing: Recursively finds `.lnk` shortcuts under ProgramData and user AppData; caches results.
2. Launch Workflow (`open`):
	* Match shortcut names first (case-insensitive substring).
	* If none: call executable search.
3. Executable Search: `fd` restricted to common install roots (Program Files, Program Files (x86), LocalAppData, ProgramData). If it returns zero results, that's the final result (no built-in PowerShell crawl anymore).
4. `es` leverages `fd` (files, dirs, extensions, search paths). `fd` is required; the command errors if missing.

## Requirements
* PowerShell 7+
* Windows 11 (most functions likely fine on Windows 10, but not tested)
* `fd` in `PATH` (required)

## Installation
Open a PowerShell terminal inside (or create) your `Documents\PowerShell` folder:
```pwsh
git clone https://github.com/MozzarellaARC/everything-powershell.git .
. $PROFILE
* `open <name>` – Launch an application (Start Menu shortcut match first, then executable discovery).
* `open -Dir <name>` – Open the install folder (directory mode via switch; legacy `open-dir` wrapper still present).
> If you already have a profile, ensure it dot-sources or imports these scripts (or copy the functions you need).

### Install fd (Recommended)
Simplest (scoop):
open -Dir unity
scoop install fd
```
Or via Cargo:
```pwsh
open / o              Launch application
open -Dir <name>      Open install directory (preferred)
open-dir / od         (Deprecated wrapper for: open -Dir)
```pwsh
fd --version
```

od     -> open-dir (deprecated; use: open -Dir)
```
Launch VS Code using alias:
```pwsh
open vsc
```
open-dir / od  Use open -Dir instead
oref           Old manual refresh (not needed)
```pwsh
open-dir unity
```
Search for PowerShell scripts anywhere under current directory (fd path scoping optional):
```pwsh
es -ext ps1 profile
```
Directories only under specific roots:
```pwsh
es -dirs -path C:\Projects -path D:\Work build
```
Files with multiple extensions:
```pwsh
es -files -ext ps1 -ext psd1 module
```

## Commands
```
open / o       Launch application
open-dir / od  Open directory of selected executable
oget           (Re)populate Start Menu cache (normally automatic)
oclear         Clear cached Start Menu entries
es             File / directory search (fd)
```

Deprecated (kept for reference, may be removed later):
```
oref           Old manual refresh (not needed)
```

## Aliases
```
o      -> open
od     -> open-dir
oget   -> Get-Apps
oclear -> Clear-AppCache
```

## Search Behavior Details
Executable discovery roots with `fd` (in order):
1. Program Files
2. Program Files (x86)
3. LocalAppData
4. ProgramData

No PowerShell filesystem crawl fallback is included; install and keep `fd` available for all search features.

## License
See `LICENSE` file.

---
Found something off or have a feature request? Open an issue or drop a PR. ❤️