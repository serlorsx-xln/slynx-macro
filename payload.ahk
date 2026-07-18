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
;  SLYNX RCS - Profile = gun curve
;  Machine globals (DPI/Sens/Enable) live in [MasterSwitch]
;  Per-gun Strength + curve knobs live in each [Profile] section
;  Alt+scroll cycles profiles (guns)
; ============================================================
global EnableRCS := 1
global Strength := 100
global currentProfile := "Universal"

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

global UserDPI := 800
global BaseDPI := 800
global UserSens := 50
global BaseSens := 50

global MenuHotkey := "F2"
global ToggleKey := "CapsLock"
global TapFireKey := "XButton5"
global GameProcess := "TslGame.exe"

global ProfileList := []
global activeProfileIdx := 1
global overlayVisible := false
global _lastProfileMtime := ""
global overlayW := 248
global overlayRowH := 34
global overlayGap := 4
global RowHwnd1 := 0
global RowHwnd2 := 0
global RowHwnd3 := 0
global RowHwnd4 := 0
global RowHwnd5 := 0

global AccX := 0.0
global AccY := 0.0

LoadProfiles()
RestoreActiveProfileIdx()
CreateProfileOverlay()
ApplyProfile(ProfileList[activeProfileIdx])

if (MenuHotkey != "")
    Hotkey, %MenuHotkey%, ToggleMenu, On

SetTimer, LoadSettingsFromUI, 100
SetTimer, WatchKeys, 10
return

; ============================================================
; Strength * DPI/sens (scope sens is handled in-game)
PullScale() {
    global Strength, UserDPI, BaseDPI, UserSens, BaseSens
    sf := Strength + 0.0
    if (sf < 1)
        sf := 1
    sf := sf / 100.0
    ud := UserDPI + 0.0
    bd := BaseDPI + 0.0
    us := UserSens + 0.0
    bs := BaseSens + 0.0
    if (ud < 1)
        ud := 1
    if (bd < 1)
        bd := 800
    if (us < 0.1)
        us := 0.1
    if (bs < 0.1)
        bs := 50
    return sf * (bd / ud) * (bs / us)
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
        ProfileList := ["Universal", "M416", "AKM", "Beryl", "SCAR", "AUG", "UMP", "Vector", "Uzi", "Bizon"]
}

RestoreActiveProfileIdx() {
    global ProfileList, activeProfileIdx
    filePath := A_AppData . "\SlynxMacro\active_profile.ini"
    if (!FileExist(filePath))
        return
    FileRead, savedName, %filePath%
    savedName := Trim(savedName)
    if (savedName = "")
        return
    Loop, % ProfileList.MaxIndex() {
        if (ProfileList[A_Index] = savedName) {
            activeProfileIdx := A_Index
            return
        }
    }
}

LoadGlobals(ini, profileName) {
    global EnableRCS, UserDPI, BaseDPI, UserSens, BaseSens
    ; Machine-wide from [MasterSwitch]; Strength is per-gun (loaded in ApplyProfile).
    IniRead, v, %ini%, MasterSwitch, EnableRCS, ERROR
    if (v = "ERROR" || v = "")
        IniRead, v, %ini%, %profileName%, MasterSwitch, 1
    EnableRCS := v

    IniRead, v, %ini%, MasterSwitch, UserDPI, ERROR
    if (v = "ERROR" || v = "")
        IniRead, v, %ini%, %profileName%, UserDPI, 800
    UserDPI := (v = "ERROR" || v = "") ? 800 : v + 0

    IniRead, v, %ini%, MasterSwitch, BaseDPI, ERROR
    if (v = "ERROR" || v = "")
        IniRead, v, %ini%, %profileName%, BaseDPI, 800
    BaseDPI := (v = "ERROR" || v = "") ? 800 : v + 0

    IniRead, v, %ini%, MasterSwitch, UserSens, ERROR
    if (v = "ERROR" || v = "")
        IniRead, v, %ini%, %profileName%, UserSens, 50
    UserSens := (v = "ERROR" || v = "") ? 50 : v + 0.0

    IniRead, v, %ini%, MasterSwitch, BaseSens, ERROR
    if (v = "ERROR" || v = "")
        IniRead, v, %ini%, %profileName%, BaseSens, 50
    BaseSens := (v = "ERROR" || v = "") ? 50 : v + 0.0
}

CreateProfileOverlay() {
    global RowText1, RowText2, RowText3, RowText4, RowText5
    global RowHwnd1, RowHwnd2, RowHwnd3, RowHwnd4, RowHwnd5
    global overlayW, overlayRowH
    Loop, 5 {
        idx := A_Index
        Gui, Row%idx%:New, +AlwaysOnTop -Caption +ToolWindow +HwndTmpHwnd
        Gui, Row%idx%:Margin, 0, 0
        Gui, Row%idx%:Color, 0C0C12
        Gui, Row%idx%:Font, s12 cAAAAAA norm, Segoe UI
        Gui, Row%idx%:Add, Text, vRowText%idx% x14 y0 w%overlayW% h%overlayRowH% +0x200 BackgroundTrans,
        Gui, Row%idx%:Show, w%overlayW% h%overlayRowH% x-5000 y-5000 NoActivate
        Sleep, 10
        RowHwnd%idx% := TmpHwnd
        WinSet, Trans, 160, ahk_id %TmpHwnd%
        WinSet, ExStyle, +0x20, ahk_id %TmpHwnd%
        Gui, Row%idx%:Hide
    }
}

OverlayStrengthFor(profileName) {
    if (profileName = "")
        return ""
    ini := A_AppData . "\SlynxMacro\profiles.ini"
    IniRead, v, %ini%, %profileName%, Strength, 100
    if (v = "ERROR" || v = "")
        v := 100
    return v
}

UpdateOverlay(animate=false) {
    global ProfileList, activeProfileIdx
    global RowHwnd1, RowHwnd2, RowHwnd3, RowHwnd4, RowHwnd5
    ; dist 0 = selected (center). Soft wheel-picker look.
    alphas := [70, 140, 245, 140, 70]
    bgs := ["0A0A10", "101018", "152238", "101018", "0A0A10"]
    Loop, 5 {
        i := A_Index
        idx := activeProfileIdx - 3 + i
        name := (idx >= 1 && idx <= ProfileList.MaxIndex()) ? ProfileList[idx] : ""
        dist := Abs(i - 3)
        bg := bgs[i]
        Gui, Row%i%:Color, %bg%
        if (name = "") {
            label := ""
            Gui, Row%i%:Font, s11 c555555 norm, Segoe UI
        } else if (dist = 0) {
            st := OverlayStrengthFor(name)
            label := "▸  " . name . "   ·   " . st . "%"
            Gui, Row%i%:Font, s13 cFFFFFF bold, Segoe UI
        } else if (dist = 1) {
            label := name
            Gui, Row%i%:Font, s12 cC8C8D0 norm, Segoe UI
        } else {
            label := name
            Gui, Row%i%:Font, s11 c6B6B78 norm, Segoe UI
        }
        GuiControl, Row%i%:Font, RowText%i%
        GuiControl, Row%i%:, RowText%i%, %label%
        hwnd := RowHwnd%i%
        a := alphas[i]
        if (hwnd)
            WinSet, Trans, %a%, ahk_id %hwnd%
    }
    if (animate && RowHwnd3) {
        hwnd := RowHwnd3
        WinSet, Trans, 255, ahk_id %hwnd%
        Sleep, 70
        WinSet, Trans, 245, ahk_id %hwnd%
    }
}

WriteActiveProfile() {
    global ProfileList, activeProfileIdx
    profileName := ProfileList[activeProfileIdx]
    filePath := A_AppData . "\SlynxMacro\active_profile.ini"
    FileOpen(filePath, "w").Write(profileName)
}

ApplyProfile(profileName) {
    global currentProfile, Strength
    global InitialY, AutoY, AutoX, AutoY_Up, TapY, ClampX, ShiftBoost, Increment, DelayRateAuto
    if (profileName = "")
        return
    currentProfile := profileName
    ini := A_AppData . "\SlynxMacro\profiles.ini"

    LoadGlobals(ini, profileName)

    IniRead, v, %ini%, %profileName%, Strength, 100
    Strength := (v = "ERROR" || v = "") ? 100 : v + 0

    IniRead, v, %ini%, %profileName%, InitialY, 8
    InitialY := (v = "ERROR" || v = "") ? 8.0 : v + 0.0
    IniRead, v, %ini%, %profileName%, AutoY, 10
    AutoY := (v = "ERROR" || v = "") ? 10.0 : v + 0.0
    IniRead, v, %ini%, %profileName%, AutoX, 2
    AutoX := (v = "ERROR" || v = "") ? 2.0 : v + 0.0
    IniRead, v, %ini%, %profileName%, AutoY_Up, 1
    AutoY_Up := (v = "ERROR" || v = "") ? 1.0 : v + 0.0
    IniRead, v, %ini%, %profileName%, TapY, 16
    TapY := (v = "ERROR" || v = "") ? 16.0 : v + 0.0
    IniRead, v, %ini%, %profileName%, ClampX, 2
    ClampX := (v = "ERROR" || v = "") ? 2.0 : v + 0.0
    IniRead, v, %ini%, %profileName%, ShiftBoost, 3
    ShiftBoost := (v = "ERROR" || v = "") ? 3.0 : v + 0.0
    IniRead, v, %ini%, %profileName%, Increment, 0.1
    Increment := (v = "ERROR" || v = "") ? 0.1 : v + 0.0
    IniRead, v, %ini%, %profileName%, DelayRateAuto, 12
    DelayRateAuto := (v = "ERROR" || v = "") ? 12 : v + 0

    ResetSubpixel()
}

~*Alt::
    if (!overlayVisible) {
        LoadProfiles()
        UpdateOverlay()
        marginR := 28
        totalH := (5 * overlayRowH) + (4 * overlayGap)
        startY := (A_ScreenHeight / 2) - (totalH / 2)
        xPos := A_ScreenWidth - overlayW - marginR
        Loop, 5 {
            i := A_Index
            yPos := startY + (i - 1) * (overlayRowH + overlayGap)
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
    sc := PullScale()
    SendInput {LButton Down}
    Sleep, %DelayRateTap%
    SendRelativeMouseMove(0, TapY * sc)
    SendInput {LButton Up}
    Sleep, %DelayRateTap%
return

; Original-style loop (friend backup): step Y once per second, plain Sleep.
; Strength/DPI/Sens only scale once via PullScale - Advanced numbers stay WYSIWYG.
HandleFullAutoRecoil() {
    global DelayRateAuto, InitialY, AutoY, AutoX, AutoY_Up, ShiftBoost, Increment, ToggleKey
    ResetSubpixel()
    sc := PullScale()
    currentY := InitialY + 0.0
    maxY := AutoY + 0.0
    if (maxY < currentY)
        maxY := currentY
    startTime := A_TickCount
    while (GetKeyState("LButton", "P") && GetKeyState("RButton", "P") && GetKeyState(ToggleKey, "T")) {
        boost := GetKeyState("Shift", "P") ? ShiftBoost : 0
        dy := (currentY + boost - AutoY_Up) * sc
        dx := AutoX * sc
        SendRelativeMouseMove(dx, dy)
        Sleep, %DelayRateAuto%
        if (A_TickCount - startTime >= 1000) {
            currentY += Increment
            if (currentY > maxY)
                currentY := maxY
            startTime := A_TickCount
        }
    }
    ResetSubpixel()
}

~XButton2::
    sc := PullScale()
    while (GetKeyState("XButton2", "P")) {
        SendInput {LButton Down}
        SendRelativeMouseMove(ClampX * sc, TapY * sc)
        Sleep, 50
    }
    SendInput {LButton Up}
return
