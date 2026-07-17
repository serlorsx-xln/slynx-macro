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
;  SLYNX RCS - zero-config universal recoil control
;  Only knob the user ever touches: Strength (%).
;  Everything else (curve shape, first-shot boost, sub-pixel
;  smoothing, timing) is baked in and never shown.
; ============================================================
global EnableRCS := 1
global Strength := 100            ; percent. 100 = default feel, higher = stronger pull
global currentProfile := "Default"

; --- baked tuning (never exposed in UI) ---
global DelayRateAuto := 12        ; ms per compensation tick while spraying
global DelayRateTap := 4
global BaseInitialY := 7.0        ; px/tick at spray start (Strength 100)
global BaseMaxY := 9.6            ; px/tick ceiling after ramp settles
global RampPerSec := 1.3          ; px/tick added each second up to the ceiling
global FirstShotMs := 350         ; stronger-pull window at spray start
global FirstShotMult := 1.30
global BaseTapY := 14.0           ; px per tap (tap-fire helper)
global BaseQuickX := 2.0          ; horizontal nudge for quick-burst helper

global MenuHotkey := "F2"
global ToggleKey := "CapsLock"
global TapFireKey := "XButton5"
global GameProcess := "TslGame.exe"

global ProfileList := []
global activeProfileIdx := 1
global overlayVisible := false
global _lastProfileMtime := ""
global overlayW := 200
global overlayRowH := 28

global AccX := 0.0
global AccY := 0.0

LoadProfiles()
CreateProfileOverlay()
ApplyProfile(ProfileList[activeProfileIdx])

if (MenuHotkey != "")
    Hotkey, %MenuHotkey%, ToggleMenu, On

SetTimer, LoadSettingsFromUI, 100
SetTimer, WatchKeys, 10
return

; ============================================================
StrengthFactor() {
    global Strength
    s := Strength + 0.0
    if (s < 1)
        s := 1
    return s / 100.0
}

; Stronger pull for the first few shots, easing back to 1.0
SprayBoost(elapsedMs) {
    global FirstShotMs, FirstShotMult
    if (FirstShotMs <= 0 || elapsedMs >= FirstShotMs)
        return 1.0
    t := elapsedMs / FirstShotMs
    return FirstShotMult + (1.0 - FirstShotMult) * t
}

ResetSubpixel() {
    global AccX, AccY
    AccX := 0.0
    AccY := 0.0
}

; Accumulate fractional pixels so slow pulls stay smooth
SendRelativeMouseMove(dx, dy) {
    global AccX, AccY
    AccX += dx
    AccY += dy
    sx := AccX >= 0 ? Floor(AccX) : Ceil(AccX)
    sy := AccY >= 0 ? Floor(AccY) : Ceil(AccY)
    if (sx = 0 && sy = 0)
        return
    AccX -= sx
    AccY -= sy
    static inputSize := (A_PtrSize = 8) ? 40 : 28
    static mouseBase := (A_PtrSize = 8) ? 8 : 4
    VarSetCapacity(INPUT, inputSize, 0)
    NumPut(0, INPUT, 0, "UInt")
    NumPut(sx, INPUT, mouseBase, "Int")
    NumPut(sy, INPUT, mouseBase+4, "Int")
    NumPut(0, INPUT, mouseBase+8, "UInt")
    NumPut(0x0001, INPUT, mouseBase+12, "UInt")
    NumPut(0, INPUT, mouseBase+16, "UInt")
    DllCall("SendInput", "UInt", 1, "Ptr", &INPUT, "Int", inputSize)
}

LoadProfiles() {
    global ProfileList
    ProfileList := []
    Loop, 20 {
        IniRead, pName, %A_AppData%\SlynxMacro\profiles.ini, Profiles, %A_Index%
        if (pName != "ERROR" && pName != "")
            ProfileList.Push(pName)
    }
    if (ProfileList.MaxIndex() == 0)
        ProfileList := ["Default"]
}

CreateProfileOverlay() {
    global RowText1, RowText2, RowText3, RowText4, RowText5, overlayW, overlayRowH
    alphas := [55, 130, 220, 130, 55]
    Loop, 5 {
        idx := A_Index
        a := alphas[idx]
        Gui, Row%idx%:New, +AlwaysOnTop -Caption +ToolWindow +HwndTmpHwnd
        Gui, Row%idx%:Color, 0A0A14
        Gui, Row%idx%:Add, Text, vRowText%idx% w%overlayW% h%overlayRowH% +Center +0x200 BackgroundTrans,
        Gui, Row%idx%:Show, w%overlayW% h%overlayRowH% x-5000 y-5000 NoActivate
        Sleep, 10
        WinSet, Trans, %a%, ahk_id %TmpHwnd%
        WinSet, ExStyle, +0x20, ahk_id %TmpHwnd%
        Gui, Row%idx%:Hide
    }
}

UpdateOverlay(animate=false) {
    global ProfileList, activeProfileIdx
    Loop, 5 {
        i := A_Index
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
        GuiControl, Row%i%:, RowText%i%, %val%
    }
    if (animate) {
        WinSet, Trans, 255, ahk_class AutoHotkeyGUI ahk_id Row3
        Sleep, 80
        WinSet, Trans, 220, ahk_class AutoHotkeyGUI ahk_id Row3
    }
}

WriteActiveProfile() {
    global ProfileList, activeProfileIdx
    profileName := ProfileList[activeProfileIdx]
    filePath := A_AppData . "\SlynxMacro\active_profile.ini"
    FileOpen(filePath, "w").Write(profileName)
}

ApplyProfile(profileName) {
    global EnableRCS, Strength
    if (profileName = "")
        return
    ini := A_AppData . "\SlynxMacro\profiles.ini"
    IniRead, v, %ini%, %profileName%, MasterSwitch, 1
    EnableRCS := v
    IniRead, v, %ini%, %profileName%, Strength, 100
    Strength := v
    ResetSubpixel()
}

~*Alt::
    if (!overlayVisible) {
        LoadProfiles()
        UpdateOverlay()
        marginR := 20
        totalH := 5 * overlayRowH
        startY := (A_ScreenHeight / 2) - (totalH / 2)
        xPos := A_ScreenWidth - overlayW - marginR
        Loop, 5 {
            i := A_Index
            yPos := startY + (i - 1) * overlayRowH
            Gui, Row%i%:Show, NoActivate x%xPos% y%yPos% w%overlayW% h%overlayRowH%
        }
        overlayVisible := true
    }
return

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
    profilesIni := A_AppData . "\SlynxMacro\profiles.ini"
    IfExist, %profilesIni%
    {
        FileGetTime, curMtime, %profilesIni%
        if (curMtime != _lastProfileMtime) {
            _lastProfileMtime := curMtime
            LoadProfiles()
            currentProfile := ProfileList[activeProfileIdx]
            if (currentProfile != "")
                ApplyProfile(currentProfile)
        }
    }
return

WatchKeys:
    if (!EnableRCS || !WinActive("ahk_exe " . GameProcess))
        return
    if (GetKeyState(TapFireKey, "P"))
        SetTimer, HandleTapFireAutoRecoil, -10
    if (GetKeyState("LButton", "P") && GetKeyState(ToggleKey, "T") && GetKeyState("RButton", "P")) {
        SetTimer, WatchKeys, Off
        HandleFullAutoRecoil()
        SetTimer, WatchKeys, 10
    }
return

ToggleMenu:
    DetectHiddenWindows, On
    IfWinExist, SLYNX Macro Pro
    {
        WinGet, style, Style, SLYNX Macro Pro
        isVisible := (style & 0x10000000)
        ; Only hide when it is already the foreground window. If it is hidden
        ; OR visible-but-behind the game, bring it to front (fixes "F2 does
        ; nothing" because the window was visible behind an in-game window).
        if (isVisible && WinActive("SLYNX Macro Pro"))
            WinHide, SLYNX Macro Pro
        else {
            WinShow, SLYNX Macro Pro
            WinActivate, SLYNX Macro Pro
        }
    }
return

HandleTapFireAutoRecoil:
    if (!GetKeyState("XButton5", "P"))
        return
    sf := StrengthFactor()
    SendInput {LButton Down}
    Sleep, %DelayRateTap%
    SendRelativeMouseMove(0, BaseTapY * sf)
    SendInput {LButton Up}
    Sleep, %DelayRateTap%
return

; Universal vertical compensation: ramps InitialY -> MaxY over the first
; second, with a short first-shot boost, all scaled by Strength.
HandleFullAutoRecoil() {
    global DelayRateAuto, BaseInitialY, BaseMaxY, RampPerSec, ToggleKey
    ResetSubpixel()
    sf := StrengthFactor()
    currentY := BaseInitialY + 0.0
    startTime := A_TickCount
    rampClock := A_TickCount
    while (GetKeyState("LButton", "P") && GetKeyState("RButton", "P") && GetKeyState(ToggleKey, "T")) {
        elapsed := A_TickCount - startTime
        fo := SprayBoost(elapsed)
        dy := currentY * fo * sf
        SendRelativeMouseMove(0, dy)
        if (A_TickCount - rampClock >= 1000) {
            if (currentY < BaseMaxY)
                currentY += RampPerSec
            if (currentY > BaseMaxY)
                currentY := BaseMaxY
            rampClock := A_TickCount
        }
        Sleep, %DelayRateAuto%
    }
    ResetSubpixel()
}

~XButton2::
    sf := StrengthFactor()
    while (GetKeyState("XButton2", "P")) {
        SendInput {LButton Down}
        SendRelativeMouseMove(BaseQuickX * sf, BaseTapY * sf)
        Sleep, 50
    }
    SendInput {LButton Up}
return
