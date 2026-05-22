; Start komorebi (via komorebic)
komorebiConfigHome := "C:\Users\settw\.config\komorebi"
ErrorLevel := ProcessExist("komorebi.exe")
if (ErrorLevel = 0)
    RunWait("komorebic.exe start --config " . komorebiConfigHome . "\komorebi.json", , "Hide")

MaxRetries:=3
RetryCount := 0
Loop
{
    RunWait("komorebic.exe state", , "Hide UseErrorLevel")
    if (ErrorLevel = 0)
    {
        Break
    }
    Else
    {
    	RetryCount++
        if (RetryCount >= MaxRetries){
        	Break
        }
        else {
            Sleep(1000)
        }
    }
}

#SingleInstance Force

; Load library
#Include C:\Users\settw\.config\komorebi\komorebic.lib.ahk

; Set monitor index preferences
MonitorIndexPreference(0, 0, 0, 2560, 1440)
MonitorIndexPreference(1, 2560, -185, 1080, 1920)


; Focus windows
!h::Focus("left")
!j::Focus("down")
!k::Focus("up")
!l::Focus("right")
!+[::CycleFocus("previous")
!+]::CycleFocus("next")

; Move windows
!+h::Move("left")
!+j::Move("down")
!+k::Move("up")
!+l::Move("right")
!+Enter::Promote()

; Stack windows
!Left::Stack("left")
!Right::Stack("right")
!Up::Stack("up")
!Down::Stack("down")
!;::Unstack()
![::CycleStack("previous")
!]::CycleStack("next")

; Resize
!=::ResizeAxis("horizontal", "increase")
!-::ResizeAxis("horizontal", "decrease")
!+=::ResizeAxis("vertical", "increase")
!+-::ResizeAxis("vertical", "decrease")

; Manipulate windows
!t::ToggleFloat()
!+f::ToggleMonocle()

; Window manager options
!+r::Retile()
!p::TogglePause()

; Layouts
!x::FlipLayout("horizontal")
!y::FlipLayout("vertical")

; Workspaces
!1::FocusWorkspace(0)
!2::FocusWorkspace(1)
!3::FocusWorkspace(2)
!4::FocusWorkspace(3)
!5::FocusWorkspace(4)

; Move windows across workspaces
!+1::MoveToWorkspace(0)
!+2::MoveToWorkspace(1)
!+3::MoveToWorkspace(2)
!+4::MoveToWorkspace(3)
!+5::MoveToWorkspace(4)
