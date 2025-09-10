; AutoHotkey v2 script to restart Windows Terminal
; Hotkey: Windows + Shift + Backtick (`)
#Requires AutoHotkey v2.0+

#+`:: {
    ProcessClose("WindowsTerminal.exe")
    Run("wt.exe")
}