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
;  SLYNX RCS - merged pre_formula ramp + Strength/first-shot/subpixel
;  Phase 2: baked weapon presets + Scope multiplier + Alt+scroll
; ============================================================
global EnableRCS := 1
global Strength := 100
global currentProfile := "Default"
global currentWeapon := "Universal"
global currentScope := "1x"

global InitialY := 8.0
global AutoY := 10.0
global AutoX := 2.0
global AutoY_Up := 1.0
global TapY := 16.0
global ClampX := 2.0
global ShiftBoost := 3.0
global Increment := 0.1
global DelayRateAuto := 12
global DelayRateTap := 4

global FirstShotMs := 350
global FirstShotMult := 1.30
global ScopeMult := 1.0

global MenuHotkey := "F2"
global ToggleKey := "CapsLock"
global TapFireKey := "XButton5"
global GameProcess := "TslGame.exe"

global ProfileList := []
global activeProfileIdx := 1
global WeaponList := []
global activeWeaponIdx := 1
global overlayVisible := false
global _lastProfileMtime := ""
global overlayW := 200
global overlayRowH := 28

global AccX := 0.0
global AccY := 0.0

InitWeaponList()
LoadProfiles()
CreateProfileOverlay()
ApplyWeaponByName(currentWeapon)
ApplyProfile(ProfileList[activeProfileIdx])

if (MenuHotkey != "")
    Hotkey, %MenuHotkey%, ToggleMenu, On

SetTimer, LoadSettingsFromUI, 100
SetTimer, WatchKeys, 10
return

; ============================================================
InitWeaponList() {
    global WeaponList, activeWeaponIdx, currentWeapon
    ; Order shown in Alt+scroll overlay
    WeaponList := ["Universal", "M416", "AKM", "Beryl", "SCAR", "AUG", "UMP", "Vector", "Uzi", "Bizon"]
    activeWeaponIdx := 1
    currentWeapon := WeaponList[1]
}

; Baked vertical feel per weapon (Strength 100 / Scope 1x baseline)
LoadWeaponPreset(name) {
    global InitialY, AutoY, AutoX, Increment, DelayRateAuto
    if (name = "M416") {
        InitialY := 7.5
        AutoY := 9.5
        AutoX := 1.5
        Increment := 0.09
        DelayRateAuto := 12
    } else if (name = "AKM") {
        InitialY := 9.0
        AutoY := 12.0
        AutoX := 2.5
        Increment := 0.14
        DelayRateAuto := 11
    } else if (name = "Beryl") {
        InitialY := 9.5
        AutoY := 13.0
        AutoX := 2.8
        Increment := 0.15
        DelayRateAuto := 11
    } else if (name = "SCAR") {
        InitialY := 7.2
        AutoY := 9.2
        AutoX := 1.4
        Increment := 0.08
        DelayRateAuto := 12
    } else if (name = "AUG") {
        InitialY := 7.0
        AutoY := 9.0
        AutoX := 1.3
        Increment := 0.08
        DelayRateAuto := 12
    } else if (name = "UMP") {
        InitialY := 6.5
        AutoY := 8.5
        AutoX := 1.2
        Increment := 0.07
        DelayRateAuto := 13
    } else if (name = "Vector") {
        InitialY := 5.5
        AutoY := 7.5
        AutoX := 1.0
        Increment := 0.06
        DelayRateAuto := 10
    } else if (name = "Uzi") {
        InitialY := 5.0
        AutoY := 7.0
        AutoX := 1.0
        Increment := 0.05
        DelayRateAuto := 10
    } else if (name = "Bizon") {
        InitialY := 6.0
        AutoY := 8.0
        AutoX := 1.2
        Increment := 0.07
        DelayRateAuto := 12
    } else {
        InitialY := 8.0
        AutoY := 10.0
        AutoX := 2.0
        Increment := 0.1
        DelayRateAuto := 12
    }
}

ScopeMultiplier(scopeName) {
    if (scopeName = "2x")
        return 1.30
    if (scopeName = "3x")
        return 1.60
    if (scopeName = "4x")
        return 2.00
    if (scopeName = "6x")
        return 2.60
    return 1.00
}

ApplyWeaponByName(name) {
    global WeaponList, activeWeaponIdx, currentWeapon
    if (name = "")
        name := "Universal"
    found := 0
    Loop % WeaponList.MaxIndex() {
        if (WeaponList[A_Index] = name) {
            activeWeaponIdx := A_Index
            found := 1
            break
        }
    }
    if (!found) {
        activeWeaponIdx := 1
        name := WeaponList[1]
    }
    currentWeapon := name
    LoadWeaponPreset(name)
    WriteActiveWeapon()
    ResetSubpixel()
}

StrengthFactor() {
    global Strength
    s := Strength + 0.0
    if (s < 1)
        s := 1
    return s / 100.0
}

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

; Overlay lists weapons (phase 2), not profiles
UpdateOverlay(animate=false) {
    global WeaponList, activeWeaponIdx
    Loop, 5 {
        i := A_Index
        idx := activeWeaponIdx - 3 + i
        val := (idx >= 1 && idx <= WeaponList.MaxIndex()) ? WeaponList[idx] : ""
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

WriteActiveWeapon() {
    global currentWeapon
    filePath := A_AppData . "\SlynxMacro\active_weapon.ini"
    FileOpen(filePath, "w").Write(currentWeapon)
}

WriteActiveProfile() {
    global ProfileList, activeProfileIdx
    profileName := ProfileList[activeProfileIdx]
    filePath := A_AppData . "\SlynxMacro\active_profile.ini"
    FileOpen(filePath, "w").Write(profileName)
}

ApplyProfile(profileName) {
    global EnableRCS, Strength, currentScope, ScopeMult
    global InitialY, AutoY, AutoX, AutoY_Up, TapY, ClampX, ShiftBoost, Increment, DelayRateAuto
    global currentWeapon
    if (profileName = "")
        return
    ini := A_AppData . "\SlynxMacro\profiles.ini"

    IniRead, v, %ini%, %profileName%, MasterSwitch, 1
    EnableRCS := v
    IniRead, v, %ini%, %profileName%, Strength, 100
    Strength := v
    IniRead, v, %ini%, %profileName%, Scope, 1x
    if (v = "ERROR" || v = "")
        v := "1x"
    currentScope := v
    ScopeMult := ScopeMultiplier(currentScope)

    IniRead, wpn, %ini%, %profileName%, Weapon, Universal
    if (wpn != "ERROR" && wpn != "")
        ApplyWeaponByName(wpn)

    ; Advanced overrides from profile (after weapon base)
    IniRead, v, %ini%, %profileName%, InitialY, %InitialY%
    if (v != "ERROR" && v != "")
        InitialY := v + 0.0
    IniRead, v, %ini%, %profileName%, AutoY, %AutoY%
    if (v != "ERROR" && v != "")
        AutoY := v + 0.0
    IniRead, v, %ini%, %profileName%, AutoX, %AutoX%
    if (v != "ERROR" && v != "")
        AutoX := v + 0.0
    IniRead, v, %ini%, %profileName%, AutoY_Up, 1
    AutoY_Up := (v = "ERROR" || v = "") ? 1.0 : v + 0.0
    IniRead, v, %ini%, %profileName%, TapY, 16
    TapY := (v = "ERROR" || v = "") ? 16.0 : v + 0.0
    IniRead, v, %ini%, %profileName%, ClampX, 2
    ClampX := (v = "ERROR" || v = "") ? 2.0 : v + 0.0
    IniRead, v, %ini%, %profileName%, ShiftBoost, 3
    ShiftBoost := (v = "ERROR" || v = "") ? 3.0 : v + 0.0
    IniRead, v, %ini%, %profileName%, Increment, %Increment%
    if (v != "ERROR" && v != "")
        Increment := v + 0.0
    IniRead, v, %ini%, %profileName%, DelayRateAuto, %DelayRateAuto%
    if (v != "ERROR" && v != "")
        DelayRateAuto := v + 0

    ResetSubpixel()
}

~*Alt::
    if (!overlayVisible) {
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
    global WeaponList, activeWeaponIdx, ProfileList, activeProfileIdx
    global Strength, currentScope, ScopeMult, AutoY_Up, TapY, ClampX, ShiftBoost, currentWeapon, currentProfile
    if (overlayVisible) {
        Loop, 5
            Gui, Row%A_Index%:Hide
        overlayVisible := false
        ApplyWeaponByName(WeaponList[activeWeaponIdx])
        ; Keep Strength/Scope helpers from current profile; weapon baked values stay
        currentProfile := ProfileList[activeProfileIdx]
        if (currentProfile != "") {
            ini := A_AppData . "\SlynxMacro\profiles.ini"
            IniRead, v, %ini%, %currentProfile%, Strength, 100
            Strength := v
            IniRead, v, %ini%, %currentProfile%, Scope, 1x
            if (v = "ERROR" || v = "")
                v := "1x"
            currentScope := v
            ScopeMult := ScopeMultiplier(currentScope)
            IniRead, v, %ini%, %currentProfile%, AutoY_Up, 1
            AutoY_Up := (v = "ERROR" || v = "") ? 1.0 : v + 0.0
            IniRead, v, %ini%, %currentProfile%, TapY, 16
            TapY := (v = "ERROR" || v = "") ? 16.0 : v + 0.0
            IniRead, v, %ini%, %currentProfile%, ClampX, 2
            ClampX := (v = "ERROR" || v = "") ? 2.0 : v + 0.0
            IniRead, v, %ini%, %currentProfile%, ShiftBoost, 3
            ShiftBoost := (v = "ERROR" || v = "") ? 3.0 : v + 0.0
            IniWrite, %currentWeapon%, %ini%, %currentProfile%, Weapon
        }
    }
return

~*!WheelUp::
    if (activeWeaponIdx > 1) {
        activeWeaponIdx--
        UpdateOverlay(true)
        WriteActiveWeapon()
    }
return

~*!WheelDown::
    if (activeWeaponIdx < WeaponList.MaxIndex()) {
        activeWeaponIdx++
        UpdateOverlay(true)
        WriteActiveWeapon()
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
    SendRelativeMouseMove(0, TapY * sf * ScopeMult)
    SendInput {LButton Up}
    Sleep, %DelayRateTap%
return

; Ramp InitialY -> AutoY, first-shot boost, Strength + Scope scale, sub-pixel
HandleFullAutoRecoil() {
    global DelayRateAuto, InitialY, AutoY, AutoX, AutoY_Up, ShiftBoost, Increment, ToggleKey, ScopeMult
    ResetSubpixel()
    sf := StrengthFactor()
    currentY := InitialY + 0.0
    maxY := AutoY + 0.0
    if (maxY < currentY)
        maxY := currentY
    startTime := A_TickCount
    rampClock := A_TickCount
    while (GetKeyState("LButton", "P") && GetKeyState("RButton", "P") && GetKeyState(ToggleKey, "T")) {
        elapsed := A_TickCount - startTime
        fo := SprayBoost(elapsed)
        boost := GetKeyState("Shift", "P") ? ShiftBoost : 0
        dy := (currentY + boost) * fo * sf * ScopeMult - AutoY_Up * sf
        dx := AutoX * sf * ScopeMult
        SendRelativeMouseMove(dx, dy)
        if (A_TickCount - rampClock >= 1000) {
            currentY += Increment
            if (currentY > maxY)
                currentY := maxY
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
        SendRelativeMouseMove(ClampX * sf, TapY * sf * ScopeMult)
        Sleep, 50
    }
    SendInput {LButton Up}
return
