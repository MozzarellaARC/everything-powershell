
## Everything Powershell (epwsh)
A PowerShell 7 configuration to navigate and launch applications quickly from Windows 11 via the terminal. (Name retained; original dependency on Everything SDK has been removed.)

Deprecated Notice:
The previous integration with the Everything SDK has been removed (SDK deprecated in this project context). A new pluggable fast search backend will be introduced. See TODO section below.

## *Functions overview:*
- Application openner through Powershell using `open yourapplicationnamehere`
- Appication directory openner through Powershell using `open-dir yourfilenamehere`
- (temporarily disabled) Full filesystem instant search. `es` now only reports a placeholder until a new backend is added.

## *How does it work?*
The code parse strings from data that is created when you open up an application, so if you have an application that is not yet open the first time or an app that is being used without installation this script may not work properly.

- suitable for user that hates finding app through icons
- very save and optimized, uses cache method to save memory for consecutive run
- easy syntax for example to open Google Chrome you can just type:
```open chrome```


*Before installing it might not work on Windows 10 and PowerShell below version 7*

### *Installation:*
***Requires: PowerShell 7. Optional historical dependency on Everything removed.***


Windows 11:
right click open in terminal on your PowerShell folder in documents if not exists make one then run this into your terminal/powershell
```
git clone https://github.com/MozzarellaARC/everything-powershell.git .
```
```
. $PROFILE
```

### *List of command:*

```
o       -Open application
od      -Open the directory of entered args
oget    -Initialize directory cache (not needed to do this manually, debugging purposes only)
oclear  -Clear cache

(deprecated)oref -Refresh cache, use this if you have newly added apps(deprecated)

es      -Placeholder (previously Everything-backed search). Will be replaced by a new search provider.
```

### *Command Aliasses:*

```
0 as open
od as open-dir
oget as open-pwsh-get
oclear as open-pwsh-clear
(deprecated) oref as open-pwsh-refresh

### TODO (Planned Search Backend Replacement)

- Evaluate alternative search providers:
	- Windows Search (SystemIndex) via OLE DB / COM
	- External tools (fd, ripgrep) with caching layer
	- Custom lightweight indexer (USN Journal + persisted metadata)
	- Optional: simple PowerShell recursive fallback (current interim solution)
- Implement provider abstraction: `Search-Provider -Query <string> -Type Files|Apps`.
- Reinstate `es` to call the new provider with filtering (extensions / path scope / fuzzy matching).

Contributions or suggestions welcome.
```