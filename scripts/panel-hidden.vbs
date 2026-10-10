' SpeedWatch - opens the control panel without a console window.
' WScript starts the process with SW_HIDE (the 0 below). Nothing clever,
' nothing that resembles an evasion technique - just a normal hidden launch.
Option Explicit
Dim sh, here, cmd
Set sh = CreateObject("WScript.Shell")
here = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\"))
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File """ & here & "panel.ps1"""
sh.Run cmd, 0, False
