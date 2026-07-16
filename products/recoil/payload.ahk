#NoTrayIcon
#Persistent
#MaxThreadsPerHotkey 2
#MaxHotkeysPerInterval 2000
#SingleInstance, Force
#InstallKeybdHook
#InstallMouseHook
SetTitleMatchMode, 2
SendMode, Input
CoordMode, Mouse, Screen
SetDefaultMouseSpeed, 0

; ============================================================
;  GLOBALS
; ============================================================
global EnableRCS          := 1
global currentProfile     := "dpi 800"

global RcCustomStrengthAutoY    := 10
global RcCustomStrengthAutoX    := 2
global RcCustomStrengthAutoY_Up := 1
global RcCustomStrengthTapY     := 16
global RcCustomStrengthClampX   := 2
global DelayRateAuto            := 12
global InitialY                 := 8
global ShiftBoost               := 3
global Increment                := 0.1

global MenuHotkey    := "F2"
global ToggleKey     := "CapsLock"
global TapFireKey    := "XButton5"
global DelayRateTap  := 4

global GameProcess   := "TslGame.exe"
global ProfileList   := []
global activeProfileIdx  := 1
global overlayVisible    := false
global _lastProfileMtime := ""
global overlayW          := 200
global overlayRowH       := 28
global overlayHwnd       := 0

; ============================================================
;  AUTO-EXECUTE — everything below runs once at startup
; ============================================================
LoadProfiles()
CreateProfileOverlay()

if (MenuHotkey != "")
    Hotkey, %MenuHotkey%, ToggleMenu, On

SetTimer, LoadSettingsFromUI, 100
SetTimer, WatchKeys, 10

return  ; <-- end of auto-execute section

; ============================================================
;  FUNCTIONS
; ============================================================
LoadProfiles() {
    global ProfileList
    ProfileList := []
    Loop, 20 {
        IniRead, pName, %A_AppData%\SlynxMacro\profiles.ini, Profiles, %A_Index%
        if (pName != "ERROR" && pName != "")
            ProfileList.Push(pName)
    }
    if (ProfileList.MaxIndex() == 0)
        ProfileList := ["Profile 1", "Profile 2", "Profile 3", "Profile 4", "Profile 5"]
}

CreateProfileOverlay() {
    global RowText1, RowText2, RowText3, RowText4, RowText5, overlayW, overlayRowH
    ; All rows same width; alpha: outer=55 mid=130 center=220
    alphas := [55, 130, 220, 130, 55]
    Loop, 5 {
        idx := A_Index
        a   := alphas[idx]
        Gui, Row%idx%:New, +AlwaysOnTop -Caption +ToolWindow +HwndTmpHwnd
        Gui, Row%idx%:Color, 0A0A14
        Gui, Row%idx%:Add, Text, vRowText%idx% w%overlayW% h%overlayRowH% +Center +0x200 BackgroundTrans,
        Gui, Row%idx%:Show, w%overlayW% h%overlayRowH% x-5000 y-5000 NoActivate
        Sleep, 10
        WinSet, Trans,   %a%,   ahk_id %TmpHwnd%
        WinSet, ExStyle, +0x20, ahk_id %TmpHwnd%
        Gui, Row%idx%:Hide
    }
}

UpdateOverlay(animate=false) {
    global ProfileList, activeProfileIdx, RowText1, RowText2, RowText3, RowText4, RowText5
    Loop, 5 {
        i   := A_Index
        idx := activeProfileIdx - 3 + i
        val := (idx >= 1 && idx <= ProfileList.MaxIndex()) ? ProfileList[idx] : ""
        dist := Abs(i - 3)
        if (dist = 0)
            Gui, Row%i%:Font, s14 cFFFFFF bold, Segoe UI
        else if (dist = 1)
            Gui, Row%i%:Font, s11 cCCCCCC norm, Segoe UI
        else
            Gui, Row%i%:Font, s10 c888888 norm, Segoe UI
        GuiControl, Row%i%:Font, RowText%i%
        GuiControl, Row%i%:,     RowText%i%, %val%
    }
    ; Quick flash on center row when scrolling
    if (animate) {
        WinSet, Trans, 255, ahk_class AutoHotkeyGUI ahk_id Row3
        Sleep, 80
        WinSet, Trans, 220, ahk_class AutoHotkeyGUI ahk_id Row3
    }
}

WriteActiveProfile() {
    global ProfileList, activeProfileIdx
    profileName := ProfileList[activeProfileIdx]
    filePath    := A_AppData . "\SlynxMacro\active_profile.ini"
    FileOpen(filePath, "w").Write(profileName)
}

ApplyProfile(profileName) {
    global EnableRCS, RcCustomStrengthAutoY, RcCustomStrengthAutoX
    global RcCustomStrengthAutoY_Up, RcCustomStrengthTapY, RcCustomStrengthClampX
    global DelayRateAuto, InitialY, ShiftBoost, Increment
    ini := A_AppData . "\SlynxMacro\profiles.ini"

    IniRead, v, %ini%, %profileName%, MasterSwitch,  1
    EnableRCS := v
    IniRead, v, %ini%, %profileName%, AutoY, 10
    RcCustomStrengthAutoY := v
    IniRead, v, %ini%, %profileName%, AutoX, 2
    RcCustomStrengthAutoX := v
    IniRead, v, %ini%, %profileName%, AutoY_Up, 1
    RcCustomStrengthAutoY_Up := v
    IniRead, v, %ini%, %profileName%, TapY, 16
    RcCustomStrengthTapY := v
    IniRead, v, %ini%, %profileName%, ClampX, 2
    RcCustomStrengthClampX := v
    IniRead, v, %ini%, %profileName%, DelayRateAuto, 12
    DelayRateAuto := v
    IniRead, v, %ini%, %profileName%, InitialY, 8
    InitialY := v
    IniRead, v, %ini%, %profileName%, ShiftBoost, 3
    ShiftBoost := v
    IniRead, v, %ini%, %profileName%, Increment, 0.1
    Increment := v
}

SendRelativeMouseMove(dx, dy) {
    static inputSize := (A_PtrSize = 8) ? 40 : 28
    static mouseBase := (A_PtrSize = 8) ? 8  : 4
    VarSetCapacity(INPUT, inputSize, 0)
    NumPut(0,      INPUT, 0,            "UInt")
    NumPut(dx,     INPUT, mouseBase,    "Int")
    NumPut(dy,     INPUT, mouseBase+4,  "Int")
    NumPut(0,      INPUT, mouseBase+8,  "UInt")
    NumPut(0x0001, INPUT, mouseBase+12, "UInt")
    NumPut(0,      INPUT, mouseBase+16, "UInt")
    DllCall("SendInput", "UInt", 1, "Ptr", &INPUT, "Int", inputSize)
}

; ============================================================
;  HOTKEYS
; ============================================================

; Alt held = show profile overlay
~*Alt::
    if (!overlayVisible) {
        LoadProfiles()
        UpdateOverlay()
        marginR := 20
        totalH  := 5 * overlayRowH
        startY  := (A_ScreenHeight / 2) - (totalH / 2)
        xPos    := A_ScreenWidth - overlayW - marginR
        Loop, 5 {
            i    := A_Index
            yPos := startY + (i - 1) * overlayRowH
            Gui, Row%i%:Show, NoActivate x%xPos% y%yPos% w%overlayW% h%overlayRowH%
        }
        overlayVisible := true
    }
return

; Alt released = hide overlay & apply selected profile
~*Alt up::
    if (overlayVisible) {
        Loop, 5
            Gui, Row%A_Index%:Hide
        overlayVisible := false
        currentProfile := ProfileList[activeProfileIdx]
        if (currentProfile != "")
            ApplyProfile(currentProfile)
    }
return

; Scroll wheel while Alt held = cycle profiles
~*!WheelUp::
    if (activeProfileIdx > 1) {
        activeProfileIdx--
        UpdateOverlay(true)
        WriteActiveProfile()
    }
return

~*!WheelDown::
    if (activeProfileIdx < ProfileList.MaxIndex()) {
        activeProfileIdx++
        UpdateOverlay(true)
        WriteActiveProfile()
    }
return

; [TEST] F8 = confirm AHK receives key + try all movement methods
F8::
    ToolTip, F8 received - testing mouse move
    MouseGetPos, curX, curY
    MouseMove, %curX%, % curY+30
    SetTimer, HideTooltip, -1500
return

HideTooltip:
    ToolTip
return

; ============================================================
;  TIMER SUBROUTINES
; ============================================================

; Reload settings written by Go UI (runs every 100 ms)
LoadSettingsFromUI:
    IfExist, %A_AppData%\SlynxMacro\system_config.ini
    {
        IniRead, pMenuHotkey, %A_AppData%\SlynxMacro\system_config.ini, Settings, MenuHotkey, F2
        if (pMenuHotkey != MenuHotkey) {
            if (MenuHotkey != "")
                Hotkey, %MenuHotkey%, ToggleMenu, Off
            MenuHotkey := pMenuHotkey
            if (MenuHotkey != "")
                Hotkey, %MenuHotkey%, ToggleMenu, On
        }

        IniRead, px, %A_AppData%\SlynxMacro\system_config.ini, Settings, PosX, 50
        IniRead, py, %A_AppData%\SlynxMacro\system_config.ini, Settings, PosY, 50

        IfWinExist, SLYNX Macro Pro
        {
            WinGetPos, winX, winY, winW, winH, SLYNX Macro Pro
            newX := (A_ScreenWidth * px / 100) - (winW / 2)
            newY := (A_ScreenHeight * py / 100) - (winH / 2)
            if (newX < 0)
                newX := 0
            if (newY < 0)
                newY := 0
            if (newX + winW > A_ScreenWidth)
                newX := A_ScreenWidth - winW
            if (newY + winH > A_ScreenHeight)
                newY := A_ScreenHeight - winH
            if (Abs(winX - newX) > 5 || Abs(winY - newY) > 5)
                WinMove, SLYNX Macro Pro,, %newX%, %newY%
        }
    }

    ; Reload profile settings only when profiles.ini changes
    profilesIni := A_AppData . "\SlynxMacro\profiles.ini"
    IfExist, %profilesIni%
    {
        FileGetTime, curMtime, %profilesIni%
        if (curMtime != _lastProfileMtime) {
            _lastProfileMtime := curMtime
            currentProfile    := ProfileList[activeProfileIdx]
            if (currentProfile != "")
                ApplyProfile(currentProfile)
        }
    }
return

; Poll input state every 10 ms to drive recoil compensation
WatchKeys:
; [TEST MODE] Game window check disabled — re-enable line below for production
; if (!EnableRCS || !WinActive("ahk_exe " . GameProcess))
    if (!EnableRCS)
        return

    if (GetKeyState(TapFireKey, "P"))
        SetTimer, HandleTapFireAutoRecoil, -10

    if (GetKeyState("LButton", "P") && GetKeyState(ToggleKey, "T") && GetKeyState("RButton", "P")) {
        SetTimer, WatchKeys, Off     ; prevent new threads while recoil loop runs
        HandleFullAutoRecoil()
        SetTimer, WatchKeys, 10      ; re-enable after buttons released
    }
return

; ============================================================
;  SUBROUTINES
; ============================================================

ToggleMenu:
    DetectHiddenWindows, On
    IfWinExist, SLYNX Macro Pro
    {
        WinGet, style, Style, SLYNX Macro Pro
        if (style & 0x10000000)
            WinHide, SLYNX Macro Pro
        else {
            WinShow,     SLYNX Macro Pro
            WinActivate, SLYNX Macro Pro
        }
    }
return

HandleTapFireAutoRecoil:
    if (!GetKeyState("XButton5", "P"))
        return
    SendInput {LButton Down}
    Sleep, %DelayRateTap%
    SendRelativeMouseMove(0, RcCustomStrengthTapY)
    SendInput {LButton Up}
    Sleep, %DelayRateTap%
return

; ============================================================
;  FULL-AUTO RECOIL (called directly, not via SetTimer)
; ============================================================
HandleFullAutoRecoil() {
    global RcCustomStrengthAutoX, RcCustomStrengthAutoY_Up, DelayRateAuto
    global InitialY, ShiftBoost, Increment, ToggleKey

    currentY  := InitialY
    startTime := A_TickCount

    while (GetKeyState("LButton", "P") && GetKeyState("RButton", "P") && GetKeyState(ToggleKey, "T")) {
        effectiveY := currentY + (GetKeyState("Shift", "P") ? ShiftBoost : 0)
        SendRelativeMouseMove(RcCustomStrengthAutoX, effectiveY - RcCustomStrengthAutoY_Up)
        Sleep, %DelayRateAuto%
        if (A_TickCount - startTime >= 1000) {
            currentY  += Increment
            startTime := A_TickCount
        }
    }
}

; ===== XButton2 Step Control =====
~XButton2::
    while (GetKeyState("XButton2", "P")) {
        SendInput {LButton Down}
        SendRelativeMouseMove(RcCustomStrengthClampX, RcCustomStrengthTapY)
        Sleep, 50
    }
    SendInput {LButton Up}
return
