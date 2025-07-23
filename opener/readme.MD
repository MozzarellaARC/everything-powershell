### Application Opener using Powershell 7+

This script intended to create a function so that you can open application through Powershell 7+


## *How does it work?*
The code parse strings from data that is created when you open up an application, so if you have an application that is not yet open the first time or an app that is being used without instalation this script may not work properly.

- suitable for user that hates finding app through icons
- very save and optimized, uses cache method to save memory for consecutive run
- easy syntax for example to open Google Chrome you can just type:
```open chrome```


*Before installing it might not work on Windows 10 and Powershell bellow version 7*

## *Installation*
- clone this repo
- open ```profile_initiator.bat``` to create .ps1(file) Powershell profile on your document so that Powershell can call this function
- open up your Powershell 7.x
- type ```open``` + your app you want to open
- when using the first time it will build cache, wait for couples of second
- the function smart enough to detect multiple application with the same name, so if you have app like Office 2024 and Office 2025 the list will show both of them before opening the app
- type the index number shown in the list and press enter to pick the application you want to open

Have fun typing!