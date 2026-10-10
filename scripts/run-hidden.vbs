' SpeedWatch - starts the daily test with no console window.
' Task Scheduler runs this instead of powershell.exe directly, so nothing
' flashes on screen at 14:00. Window style 0 = hidden; True = wait, so the
' task's 10 minute time limit still applies to the real work.
Option Explicit
Dim sh, here, cmd
Set sh = CreateObject("WScript.Shell")
here = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\"))
cmd = "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File """ & here & "run-test.ps1"""
sh.Run cmd, 0, True
