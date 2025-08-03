
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
***requires: Powershell 7 and [Everything by VoidTools](https://www.voidtools.com/) version 1.4x***


1. open Powershell 7
2. type this comand in the interface ```$PROFILE```
3. check if such directory is created ```C:\Users\YourUserName\Documents\PowerShell```
4. (*optional*) if not, you can create new folder and name it ```PowerShell```
5. type this in your Powershell 7 interface ```cd C:\Users\YourUserName\Documents\PowerShell```
6. type this in your Powershell 7 interface ```
git clone https://github.com/MozzarellaARC/the-all-powershell.git```
7. (*optional*) or if you don't have git installed you can clone this repo
8. type this in your PowerShell 7 ```. $PROFILE``` (don't *forget the dots*)

***CAVEATS: Everything app must run in the background for a more precision search querries !!!***

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