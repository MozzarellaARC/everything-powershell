
## Everything Powershell (epwsh)
A Powershell 7 configuration, which enables user to be able to navigate through their Windows 11 operating system from Powershell ***solo no diff***

Powered by:
Everything SDK

## *Functions overview:*
- Application openner through Powershell using `open yourapplicationnamehere`
- Appication directory openner through Powershell using `open-dir yourfilenamehere`
- Everything Search inside Powershell using `es yourqueryhere`

## *How does it work?*
The code parse strings from data that is created when you open up an application, so if you have an application that is not yet open the first time or an app that is being used without installation this script may not work properly.

- suitable for user that hates finding app through icons
- very save and optimized, uses cache method to save memory for consecutive run
- easy syntax for example to open Google Chrome you can just type:
```open chrome```


*Before installing it might not work on Windows 10 and Powershell bellow version 7*

### *Installation:*
***Requires: Powershell 7 and optionally [Everything by VoidTools](https://www.voidtools.com/) version 1.4x***


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

es      -Perfrom directory search using Everything SDK (need Everything app run in the background)
```

### *Command Aliasses:*

```
0 as open
od as open-dir
oget as open-pwsh-get
oclear as open-pwsh-clear
(deprecated) oref as open-pwsh-refresh
```