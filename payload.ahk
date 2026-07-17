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
;  SLYNX RCS - ramp / pattern editor / weapon-slot auto
; ============================================================
global EnableRCS := 1
global currentProfile := "dpi 800"

global RcCustomStrengthAutoY := 10
global RcCustomStrengthAutoX := 2
global RcCustomStrengthAutoY_Up := 1
global RcCustomStrengthTapY := 16
global RcCustomStrengthClampX := 2
global DelayRateAuto := 12
global InitialY := 8
global ShiftBoost := 3
global Increment := 0.1

global UserDPI := 800
global BaseDPI := 800
global UserSens := 1.0
global BaseSens := 1.0
global FalloffMs := 400
global FalloffMult := 1.35
global RecoilMode := 1
global PatternScale := 1.0
global PatternName := "m416"
global PatternSteps := ""
global WeaponAuto := 1
global Slot1 := "m416"
global Slot2 := "akm"
global Slot3 := "beryl"
global Slot4 := "ump"
global Slot5 := "vector"
global ActiveWeapon := "m416"
global ActiveSlot := 1

global MenuHotkey := "F2"
global ToggleKey := "CapsLock"
global TapFireKey := "XButton5"
global DelayRateTap := 4
global GameProcess := "TslGame.exe"

global ProfileList := []
global activeProfileIdx := 1
global overlayVisible := false
global _lastProfileMtime := ""
global overlayW := 200
global overlayRowH := 28

global AccX := 0.0
global AccY := 0.0
global PatDx := []
global PatDy := []
global PatLen := 0

EnsurePatternDir()
LoadProfiles()
CreateProfileOverlay()
ApplyProfile(ProfileList[activeProfileIdx])
WriteWeaponStatus()

if (MenuHotkey != "")
    Hotkey, %MenuHotkey%, ToggleMenu, On

; Weapon slots - passthrough to game (~) + auto pattern
Hotkey, ~1, WeaponSlot1, On
Hotkey, ~2, WeaponSlot2, On
Hotkey, ~3, WeaponSlot3, On
Hotkey, ~4, WeaponSlot4, On
Hotkey, ~5, WeaponSlot5, On

SetTimer, LoadSettingsFromUI, 100
SetTimer, WatchKeys, 10
return

; ============================================================
EnsurePatternDir() {
    dir := A_AppData . "\SlynxMacro\patterns"
    if (!FileExist(dir))
        FileCreateDir, %dir%
}

DpiScale() {
    global UserDPI, BaseDPI, UserSens, BaseSens
    ud := UserDPI + 0.0
    bd := BaseDPI + 0.0
    us := UserSens + 0.0
    bs := BaseSens + 0.0
    if (ud < 1)
        ud := 800
    if (bd < 1)
        bd := 800
    if (us < 0.01)
        us := 1.0
    if (bs < 0.01)
        bs := 1.0
    return (bd / ud) * (bs / us)
}

FalloffFactor(elapsedMs) {
    global FalloffMs, FalloffMult
    fm := FalloffMs + 0
    if (fm <= 0)
        return 1.0
    mult := FalloffMult + 0.0
    if (mult < 0.1)
        mult := 1.0
    if (elapsedMs >= fm)
        return 1.0
    t := elapsedMs / fm
    return mult + (1.0 - mult) * t
}

_pushPat(dx, dy) {
    global PatDx, PatDy, PatLen
    PatDx.Push(dx + 0.0)
    PatDy.Push(dy + 0.0)
    PatLen++
}

ClearPattern() {
    global PatDx, PatDy, PatLen
    PatDx := []
    PatDy := []
    PatLen := 0
}

; Load from PatternSteps string: "dx,dy;dx,dy;..."
LoadPatternFromSteps(steps) {
    global PatLen
    ClearPattern()
    steps := Trim(steps)
    if (steps = "" || steps = "ERROR")
        return false
    Loop, Parse, steps, `;
    {
        line := Trim(A_LoopField)
        if (line = "")
            continue
        StringReplace, line, line, %A_Tab%, `,, All
        StringSplit, p, line, `,
        if (p0 < 2)
            continue
        _pushPat(p1, p2)
    }
    return PatLen > 0
}

LoadPatternFromFile(name) {
    global PatLen
    ClearPattern()
    custom := A_AppData . "\SlynxMacro\patterns\" . name . ".txt"
    if (!FileExist(custom))
        return false
    Loop, Read, %custom%
    {
        line := Trim(A_LoopReadLine)
        if (line = "" || SubStr(line, 1, 1) = ";" || SubStr(line, 1, 1) = "#")
            continue
        StringReplace, line, line, %A_Tab%, `,, All
        StringSplit, p, line, `,
        if (p0 < 2)
            continue
        _pushPat(p1, p2)
    }
    return PatLen > 0
}

; Built-in PUBG-ish compensation tables (relative per DelayRate tick)
LoadBuiltinWeapon(name) {
    global PatLen, PatternName
    ClearPattern()
    PatternName := name
    if (name = "akm") {
        Loop, 5
            _pushPat(0.05 * (A_Index - 3), 3.4)
        Loop, 8
            _pushPat(0.35 * ((Mod(A_Index, 2) * 2) - 1), 2.6)
        Loop, 12
            _pushPat(0.55 * ((Mod(A_Index, 2) * 2) - 1), 2.0)
        Loop, 15
            _pushPat(0.45 * ((Mod(A_Index, 2) * 2) - 1), 1.5)
    } else if (name = "beryl") {
        Loop, 4
            _pushPat(0, 3.6)
        Loop, 10
            _pushPat(0.5 * ((Mod(A_Index, 2) * 2) - 1), 2.8)
        Loop, 14
            _pushPat(0.7 * ((Mod(A_Index, 2) * 2) - 1), 2.1)
        Loop, 12
            _pushPat(0.4 * ((Mod(A_Index, 2) * 2) - 1), 1.6)
    } else if (name = "scar" || name = "scar-l") {
        Loop, 6
            _pushPat(0, 2.6)
        Loop, 10
            _pushPat(0.2 * ((Mod(A_Index, 2) * 2) - 1), 2.0)
        Loop, 16
            _pushPat(0.25 * ((Mod(A_Index, 2) * 2) - 1), 1.4)
    } else if (name = "aug") {
        Loop, 6
            _pushPat(0, 2.4)
        Loop, 12
            _pushPat(0.15 * ((Mod(A_Index, 2) * 2) - 1), 1.8)
        Loop, 16
            _pushPat(0.2 * ((Mod(A_Index, 2) * 2) - 1), 1.3)
    } else if (name = "g36c") {
        Loop, 5
            _pushPat(0, 2.5)
        Loop, 12
            _pushPat(0.22 * ((Mod(A_Index, 2) * 2) - 1), 1.9)
        Loop, 15
            _pushPat(0.28 * ((Mod(A_Index, 2) * 2) - 1), 1.35)
    } else if (name = "ump" || name = "ump45") {
        Loop, 5
            _pushPat(0, 2.0)
        Loop, 10
            _pushPat(0.15 * ((Mod(A_Index, 2) * 2) - 1), 1.5)
        Loop, 20
            _pushPat(0.2 * ((Mod(A_Index, 2) * 2) - 1), 1.1)
    } else if (name = "vector" || name = "vector") {
        Loop, 8
            _pushPat(0, 1.6)
        Loop, 16
            _pushPat(0.12 * ((Mod(A_Index, 2) * 2) - 1), 1.2)
        Loop, 24
            _pushPat(0.18 * ((Mod(A_Index, 2) * 2) - 1), 0.95)
    } else if (name = "uzi") {
        Loop, 10
            _pushPat(0, 1.3)
        Loop, 20
            _pushPat(0.1 * ((Mod(A_Index, 2) * 2) - 1), 1.0)
        Loop, 20
            _pushPat(0.15 * ((Mod(A_Index, 2) * 2) - 1), 0.85)
    } else if (name = "bizon") {
        Loop, 8
            _pushPat(0, 1.7)
        Loop, 20
            _pushPat(0.2 * ((Mod(A_Index, 2) * 2) - 1), 1.25)
        Loop, 30
            _pushPat(0.25 * ((Mod(A_Index, 2) * 2) - 1), 1.0)
    } else if (name = "vertical" || name = "generic_ar") {
        Loop, 6
            _pushPat(0, 2.8)
        Loop, 10
            _pushPat(0, 2.0)
        Loop, 14
            _pushPat(0, 1.4)
        Loop, 20
            _pushPat(0, 1.0)
    } else if (name = "sway") {
        swayX := "0,0,0.2,0.4,0.6,0.8,0.5,0.1,-0.4,-0.8,-1.0,-0.7,-0.2,0.3,0.7,1.0,0.8,0.3,-0.3,-0.7,-0.9,-0.5,0,0.4"
        swayY := "2.2,2.4,2.6,2.5,2.3,2.1,1.9,1.8,1.7,1.6,1.5,1.5,1.4,1.4,1.3,1.3,1.2,1.2,1.1,1.1,1.0,1.0,1.0,1.0"
        StringSplit, sx, swayX, `,
        StringSplit, sy, swayY, `,
        Loop, %sx0%
            _pushPat(sx%A_Index%, sy%A_Index%)
        Loop, 16 {
            side := (Mod(A_Index, 4) < 2) ? 0.5 : -0.5
            _pushPat(side, 0.95)
        }
    } else if (name = "heavy") {
        Loop, 8
            _pushPat(0, 3.2)
        Loop, 12
            _pushPat(0.15 * ((Mod(A_Index, 2) * 2) - 1), 2.4)
        Loop, 20
            _pushPat(0.25 * ((Mod(A_Index, 2) * 2) - 1), 1.6)
    } else {
        ; default m416 - controllable AR
        Loop, 5
            _pushPat(0, 2.7)
        Loop, 8
            _pushPat(0.18 * ((Mod(A_Index, 2) * 2) - 1), 2.15)
        Loop, 12
            _pushPat(0.3 * ((Mod(A_Index, 2) * 2) - 1), 1.7)
        Loop, 16
            _pushPat(0.25 * ((Mod(A_Index, 2) * 2) - 1), 1.25)
    }
    return PatLen > 0
}

; Priority: custom steps from UI → file → builtin weapon name
ResolvePattern() {
    global PatternSteps, PatternName, ActiveWeapon, WeaponAuto, RecoilMode
    EnsurePatternDir()
    if (LoadPatternFromSteps(PatternSteps))
        return
    name := PatternName
    if (WeaponAuto + 0 = 1 && ActiveWeapon != "")
        name := ActiveWeapon
    if (LoadPatternFromFile(name))
        return
    LoadBuiltinWeapon(name)
    if (WeaponAuto + 0 = 1)
        RecoilMode := 1
}

WriteWeaponStatus() {
    global ActiveWeapon, ActiveSlot, PatLen, WeaponAuto
    EnsurePatternDir()
    f := A_AppData . "\SlynxMacro\weapon_status.ini"
    FileDelete, %f%
    IniWrite, %ActiveWeapon%, %f%, Status, Weapon
    IniWrite, %ActiveSlot%, %f%, Status, Slot
    IniWrite, %PatLen%, %f%, Status, Steps
    IniWrite, %WeaponAuto%, %f%, Status, WeaponAuto
}

ApplyWeaponSlot(slot, weapon) {
    global WeaponAuto, ActiveWeapon, ActiveSlot, PatternName, RecoilMode, PatternSteps
    if (WeaponAuto + 0 != 1)
        return
    ActiveSlot := slot
    ActiveWeapon := weapon
    PatternName := weapon
    PatternSteps := ""  ; use builtin/file for this weapon
    RecoilMode := 1
    ResolvePattern()
    WriteWeaponStatus()
}

WeaponSlot1:
    ApplyWeaponSlot(1, Slot1)
return
WeaponSlot2:
    ApplyWeaponSlot(2, Slot2)
return
WeaponSlot3:
    ApplyWeaponSlot(3, Slot3)
return
WeaponSlot4:
    ApplyWeaponSlot(4, Slot4)
return
WeaponSlot5:
    ApplyWeaponSlot(5, Slot5)
return

LoadProfiles() {
    global ProfileList
    ProfileList := []
    Loop, 20 {
        IniRead, pName, %A_AppData%\SlynxMacro\profiles.ini, Profiles, %A_Index%
        if (pName != "ERROR" && pName != "")
            ProfileList.Push(pName)
    }
    if (ProfileList.MaxIndex() == 0)
        ProfileList := ["dpi 400", "dpi 800", "dpi 1600"]
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
    global EnableRCS, RcCustomStrengthAutoY, RcCustomStrengthAutoX
    global RcCustomStrengthAutoY_Up, RcCustomStrengthTapY, RcCustomStrengthClampX
    global DelayRateAuto, InitialY, ShiftBoost, Increment
    global UserDPI, BaseDPI, UserSens, BaseSens, FalloffMs, FalloffMult
    global RecoilMode, PatternScale, PatternName, PatternSteps, WeaponAuto
    global Slot1, Slot2, Slot3, Slot4, Slot5, ActiveWeapon
    if (profileName = "")
        return
    ini := A_AppData . "\SlynxMacro\profiles.ini"

    IniRead, v, %ini%, %profileName%, MasterSwitch, 1
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
    IniRead, v, %ini%, %profileName%, UserDPI, 800
    UserDPI := v
    IniRead, v, %ini%, %profileName%, BaseDPI, 800
    BaseDPI := v
    IniRead, v, %ini%, %profileName%, UserSens, 1.0
    UserSens := v
    IniRead, v, %ini%, %profileName%, BaseSens, 1.0
    BaseSens := v
    IniRead, v, %ini%, %profileName%, FalloffMs, 400
    FalloffMs := v
    IniRead, v, %ini%, %profileName%, FalloffMult, 1.35
    FalloffMult := v
    IniRead, v, %ini%, %profileName%, RecoilMode, 1
    RecoilMode := v
    IniRead, v, %ini%, %profileName%, PatternScale, 1.0
    PatternScale := v
    IniRead, v, %ini%, %profileName%, PatternName, m416
    PatternName := v
    IniRead, v, %ini%, %profileName%, PatternSteps,
    PatternSteps := v
    IniRead, v, %ini%, %profileName%, WeaponAuto, 1
    WeaponAuto := v
    IniRead, v, %ini%, %profileName%, Slot1, m416
    Slot1 := v
    IniRead, v, %ini%, %profileName%, Slot2, akm
    Slot2 := v
    IniRead, v, %ini%, %profileName%, Slot3, beryl
    Slot3 := v
    IniRead, v, %ini%, %profileName%, Slot4, ump
    Slot4 := v
    IniRead, v, %ini%, %profileName%, Slot5, vector
    Slot5 := v

    if (WeaponAuto + 0 = 1) {
        ActiveWeapon := Slot1
        PatternName := Slot1
        RecoilMode := 1
    }
    ResolvePattern()
    ResetSubpixel()
    WriteWeaponStatus()
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
        if (style & 0x10000000)
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
    sc := DpiScale()
    SendInput {LButton Down}
    Sleep, %DelayRateTap%
    SendRelativeMouseMove(0, RcCustomStrengthTapY * sc)
    SendInput {LButton Up}
    Sleep, %DelayRateTap%
return

HandleFullAutoRecoil() {
    global RcCustomStrengthAutoX, RcCustomStrengthAutoY, RcCustomStrengthAutoY_Up
    global DelayRateAuto, InitialY, ShiftBoost, Increment, ToggleKey
    global RecoilMode, PatternScale, PatDx, PatDy, PatLen

    if (PatLen < 1)
        ResolvePattern()

    ResetSubpixel()
    sc := DpiScale()
    currentY := InitialY + 0.0
    targetY := RcCustomStrengthAutoY + 0.0
    if (targetY < currentY)
        targetY := currentY
    startTime := A_TickCount
    rampClock := A_TickCount
    stepIdx := 1
    usePat := (RecoilMode + 0 = 1 && PatLen > 0)

    while (GetKeyState("LButton", "P") && GetKeyState("RButton", "P") && GetKeyState(ToggleKey, "T")) {
        elapsed := A_TickCount - startTime
        fo := FalloffFactor(elapsed)
        boost := GetKeyState("Shift", "P") ? ShiftBoost : 0

        if (usePat) {
            idx := stepIdx
            if (idx > PatLen)
                idx := PatLen
            dx := PatDx[idx] * PatternScale * sc * fo
            dy := PatDy[idx] * PatternScale * sc * fo
            dy += boost * sc
            dy -= RcCustomStrengthAutoY_Up * sc
            SendRelativeMouseMove(dx, dy)
            stepIdx++
        } else {
            effectiveY := currentY + boost
            dx := RcCustomStrengthAutoX * sc * fo
            dy := (effectiveY - RcCustomStrengthAutoY_Up) * sc * fo
            SendRelativeMouseMove(dx, dy)
            if (A_TickCount - rampClock >= 1000) {
                if (currentY < targetY)
                    currentY += Increment
                if (currentY > targetY)
                    currentY := targetY
                rampClock := A_TickCount
            }
        }
        Sleep, %DelayRateAuto%
    }
    ResetSubpixel()
}

~XButton2::
    sc := DpiScale()
    while (GetKeyState("XButton2", "P")) {
        SendInput {LButton Down}
        SendRelativeMouseMove(RcCustomStrengthClampX * sc, RcCustomStrengthTapY * sc)
        Sleep, 50
    }
    SendInput {LButton Up}
return
