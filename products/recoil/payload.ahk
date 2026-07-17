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
;
;  Steadiness pipeline (baked, invisible):
;   1. High-res 1ms system timer (timeBeginPeriod) so waits are exact.
;   2. High-frequency sub-step glide (~3ms) driven by a QPC hybrid
;      wait, so the vertical pull is delivered as many tiny drift-free
;      moves instead of a few chunky 12ms jumps.
;   3. Sub-pixel accumulation so fractional px are never lost.
;   4. Mouse-acceleration guard: warns + one-click disables Windows
;      "Enhance pointer precision" which otherwise warps compensation.
; ============================================================
global EnableRCS := 1
global Strength := 100            ; percent. 100 = default feel, higher = stronger pull
global currentProfile := "Default"

; --- baked tuning (never exposed in UI) ---
; Vertical pull is defined as a RATE (px/second) so it is decoupled from
; the loop frequency. These values reproduce the previous feel exactly:
;   old 7.0px / 12ms tick = 583 px/s start, 9.6px / 12ms = 800 px/s max,
;   +1.3px/tick per second = +108 px/s per second ramp.
global VInitRate := 583.0         ; px/s at spray start (Strength 100)
global VMaxRate := 800.0          ; px/s ceiling after ramp settles
global VRampRate := 108.0         ; px/s added each second up to the ceiling
global MoveIntervalMs := 3        ; sub-step period while spraying (~333 Hz)
global DelayRateTap := 4
global FirstShotMs := 350         ; stronger-pull window at spray start
global FirstShotMult := 1.30
global BaseTapY := 14.0           ; px per tap (tap-fire helper)
global BaseQuickX := 2.0          ; horizontal nudge for quick-burst helper

; --- high-resolution timing (QPC) ---
global QPCFreq := 0
DllCall("QueryPerformanceFrequency", "Int64*", QPCFreq)
; Force the system timer to 1ms so Sleep/waits are precise (default ~15.6ms).
DllCall("winmm\timeBeginPeriod", "UInt", 1)
; Best effort push to 0.5ms via the undocumented NT call (harmless if it fails).
_ntActualRes := 0
DllCall("ntdll\NtSetTimerResolution", "UInt", 5000, "Int", 1, "UInt*", _ntActualRes)
OnExit, CleanupTimer

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
CheckMouseAccel()

if (MenuHotkey != "")
    Hotkey, %MenuHotkey%, ToggleMenu, On

SetTimer, LoadSettingsFromUI, 100
SetTimer, WatchKeys, 10
return

CleanupTimer:
    DllCall("winmm\timeEndPeriod", "UInt", 1)
    ExitApp

; ============================================================
;  High-resolution timing helpers
; ============================================================
QPCNow() {
    local t := 0
    DllCall("QueryPerformanceCounter", "Int64*", t)
    return t
}

; Hybrid wait until an absolute QPC target: coarse Sleep(1) for the bulk
; (accurate at 1ms timer res), then a tight spin for the final <1.5ms so
; the sub-step cadence is drift-free without pegging the CPU.
PreciseWaitUntil(targetCount) {
    global QPCFreq
    if (QPCFreq <= 0) {
        Sleep, 3
        return
    }
    Loop {
        local now := 0
        DllCall("QueryPerformanceCounter", "Int64*", now)
        remaining := (targetCount - now) / QPCFreq * 1000.0
        if (remaining <= 0)
            break
        if (remaining > 1.5)
            DllCall("Sleep", "UInt", 1)
    }
}

; ============================================================
;  Mouse-acceleration guard (Windows "Enhance pointer precision")
;  Warps relative mouse deltas, which desyncs recoil compensation.
; ============================================================
CheckMouseAccel() {
    VarSetCapacity(mp, 12, 0)
    DllCall("SystemParametersInfo", "UInt", 0x0003, "UInt", 0, "Ptr", &mp, "UInt", 0)
    accel := NumGet(mp, 8, "Int")
    if (accel != 0)
        ShowAccelWarning()
}

DisableMouseAccel() {
    VarSetCapacity(mp, 12, 0)
    NumPut(0, mp, 0, "Int")
    NumPut(0, mp, 4, "Int")
    NumPut(0, mp, 8, "Int")
    ; SPI_SETMOUSE, SPIF_UPDATEINIFILE | SPIF_SENDCHANGE
    DllCall("SystemParametersInfo", "UInt", 0x0004, "UInt", 0, "Ptr", &mp, "UInt", 3)
}

ShowAccelWarning() {
    Gui, Accel:New, +AlwaysOnTop +ToolWindow +HwndAccelHwnd, SLYNX
    Gui, Accel:Color, 0F0F1A
    Gui, Accel:Margin, 16, 16
    Gui, Accel:Font, s10 cFFFFFF, Segoe UI
    Gui, Accel:Add, Text, w340, Windows "Enhance pointer precision" (mouse accel) กำลังเปิดอยู่`nมันทำให้การชดเชย recoil เพี้ยนและไม่นิ่ง แนะนำให้ปิด
    Gui, Accel:Font, s9 c9AA0B5
    Gui, Accel:Add, Text, w340 y+4, ปิดครั้งเดียวพอ ไม่ต้องทำซ้ำ
    Gui, Accel:Add, Button, gAccelFix w160 x16 y+14 Default, ปิดให้เลย (แนะนำ)
    Gui, Accel:Add, Button, gAccelSkip w160 x+8, ข้าม
    Gui, Accel:Show, AutoSize Center
}

AccelFix:
    DisableMouseAccel()
    Gui, Accel:Destroy
return

AccelSkip:
    Gui, Accel:Destroy
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

; Universal vertical compensation delivered as a high-frequency sub-step
; glide: the pull is a RATE (px/s) that ramps VInitRate -> VMaxRate over the
; first second with a short first-shot boost, sliced into ~3ms sub-steps and
; paced by a QPC hybrid wait. Many tiny drift-free moves + sub-pixel accum =
; the steadiest vertical line the hardware can produce. Horizontal stays 0 on
; purpose (PUBG's horizontal recoil is semi-random; fighting it only scatters).
HandleFullAutoRecoil() {
    global VInitRate, VMaxRate, VRampRate, MoveIntervalMs, ToggleKey, QPCFreq
    ResetSubpixel()
    sf := StrengthFactor()
    rate := VInitRate + 0.0
    dt := MoveIntervalMs / 1000.0
    intervalCount := (QPCFreq > 0) ? Round(QPCFreq * dt) : 0
    startTime := A_TickCount
    nextTick := QPCNow() + intervalCount
    while (GetKeyState("LButton", "P") && GetKeyState("RButton", "P") && GetKeyState(ToggleKey, "T")) {
        elapsed := A_TickCount - startTime
        fo := SprayBoost(elapsed)
        SendRelativeMouseMove(0, rate * fo * sf * dt)
        if (rate < VMaxRate) {
            rate += VRampRate * dt
            if (rate > VMaxRate)
                rate := VMaxRate
        }
        if (intervalCount > 0) {
            PreciseWaitUntil(nextTick)
            nextTick += intervalCount
        } else {
            Sleep, %MoveIntervalMs%
        }
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
