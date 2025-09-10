#Requires AutoHotkey v2.0

#HotIf WinActive("ahk_class ConsoleWindowClass") ; CMD or PowerShell
!F4::return

#HotIf WinActive("ahk_exe WindowsTerminal.exe") ; Windows Terminal
!F4::return

#HotIf ; Reset context for other windows
