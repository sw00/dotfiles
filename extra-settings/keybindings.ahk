#NoEnv  ; Recommended for performance and compatibility with future AutoHotkey releases.
SendMode Input  ; Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir %A_ScriptDir%  ; Ensures a consistent starting directory.

; window groups
GroupAdd, browse, ahk_exe Brave.exe
GroupAdd, browse, ahk_exe firefox.exe
GroupAdd, browse, ahk_exe zeal.exe
GroupAdd, code, ahk_exe WindowsTerminal.exe
GroupAdd, code, ahk_exe alacritty.exe
GroupAdd, code, ahk_exe Code.exe
GroupAdd, communicate, ahk_exe Ferdi.exe
GroupAdd, communicate, ahk_exe Telegram.exe
GroupAdd, task, ahk_exe Boostnote.exe
GroupAdd, task, ahk_exe Boost Note.exe
GroupAdd, task, ahk_exe Bitwarden.exe
GroupAdd, misc, ahk_exe Spotify.exe

; right alt + 1
>!1::GroupActivate, browse, R
; right alt + 2
>!2::GroupActivate, code, R
; right alt + 3
>!3::GroupActivate, communicate, R
; right alt + 4
>!4::GroupActivate, task, R
; right alt + 0
>!0::GroupActivate, misc, R

; map caps to ctrl
CapsLock::Control
