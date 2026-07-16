#Persistent
#MaxThreadsPerHotkey 2
#SingleInstance, Force
SetTitleMatchMode, 2

EnableRCS := true
currentProfile := "dpi 800"
profileList := ["dpi 400", "dpi 800", "dpi 1600"]
profileData := {}

; ===== INI Read Function =====
IniReadOrDefault(file, section, key, default) {
    IniRead, value, %file%, %section%, %key%, %default%
    return value
}

; ===== Load Profile Data =====
for i, name in profileList {
    profileData[name] := Object()
    profileData[name]["AutoY"] := IniReadOrDefault("profiles.ini", name, "AutoY", 10)
    profileData[name]["AutoX"] := IniReadOrDefault("profiles.ini", name, "AutoX", 2)
    profileData[name]["AutoY_Up"] := IniReadOrDefault("profiles.ini", name, "AutoY_Up", 1)
    profileData[name]["TapY"] := IniReadOrDefault("profiles.ini", name, "TapY", 16)
    profileData[name]["ClampX"] := IniReadOrDefault("profiles.ini", name, "ClampX", 2)
    profileData[name]["DelayRateAuto"] := IniReadOrDefault("profiles.ini", name, "DelayRateAuto", 12)
    profileData[name]["InitialY"] := IniReadOrDefault("profiles.ini", name, "InitialY", 8)
    profileData[name]["ShiftBoost"] := IniReadOrDefault("profiles.ini", name, "ShiftBoost", 3)
    profileData[name]["Increment"] := IniReadOrDefault("profiles.ini", name, "Increment", 0.1)
}

loadProfile(profileName) {
    global RcCustomStrengthAutoY, RcCustomStrengthAutoX, RcCustomStrengthAutoY_Up
    global RcCustomStrengthTapY, RcCustomStrengthClampX, DelayRateAuto
    global InitialY, ShiftBoost, Increment
    global profileData, currentProfile

    currentProfile := profileName
    p := profileData[profileName]

    RcCustomStrengthAutoY := p["AutoY"]
    RcCustomStrengthAutoX := p["AutoX"]
    RcCustomStrengthAutoY_Up := p["AutoY_Up"]
    RcCustomStrengthTapY := p["TapY"]
    RcCustomStrengthClampX := p["ClampX"]
    DelayRateAuto := p["DelayRateAuto"]
    InitialY := p["InitialY"]
    ShiftBoost := p["ShiftBoost"]
    Increment := p["Increment"]

    ToolTip, Profile Loaded: %profileName%
    SetTimer, RemoveToolTip, -1000
}

SaveProfileToFile(profileName) {
    global profileData
    p := profileData[profileName]
    IniWrite, % p["AutoY"], profiles.ini, %profileName%, AutoY
    IniWrite, % p["AutoX"], profiles.ini, %profileName%, AutoX
    IniWrite, % p["AutoY_Up"], profiles.ini, %profileName%, AutoY_Up
    IniWrite, % p["TapY"], profiles.ini, %profileName%, TapY
    IniWrite, % p["ClampX"], profiles.ini, %profileName%, ClampX
    IniWrite, % p["DelayRateAuto"], profiles.ini, %profileName%, DelayRateAuto
    IniWrite, % p["InitialY"], profiles.ini, %profileName%, InitialY
    IniWrite, % p["ShiftBoost"], profiles.ini, %profileName%, ShiftBoost
    IniWrite, % p["Increment"], profiles.ini, %profileName%, Increment
}

loadProfile(currentProfile)

ToggleKey := "CapsLock"
TapFireKey := "XButton5"
DelayRateTap := 4

SetTimer, WatchKeys, 10
return

; ===== Watch Keys =====
WatchKeys:
; [TEST MODE] Game check disabled — re-enable for production:
; if (!EnableRCS || !WinActive("ahk_exe TslGame.exe"))
if (!EnableRCS)
    return

if (GetKeyState(TapFireKey, "P")) {
    SetTimer, HandleTapFireAutoRecoil, -10
}

if (GetKeyState("LButton", "P")) {
    if (GetKeyState(ToggleKey, "T") && GetKeyState("RButton", "P")) {
        HandleFullAutoRecoil()
    }
}
return

; ===== Full Auto Recoil with Shift Mode =====
HandleFullAutoRecoil() {
    global RcCustomStrengthAutoX, RcCustomStrengthAutoY_Up, DelayRateAuto
    global InitialY, ShiftBoost, Increment

    currentY := InitialY
    elapsed := 0
    interval := 1000
    startTime := A_TickCount

    while (GetKeyState("LButton", "P") && GetKeyState("RButton", "P")) {
        if (GetKeyState("Shift", "P")) {
            effectiveY := currentY + ShiftBoost
        } else {
            effectiveY := currentY
        }

        offsetX := RcCustomStrengthAutoX
        offsetY := effectiveY - RcCustomStrengthAutoY_Up
        DllCall("mouse_event", "UInt", 1, "Int", offsetX, "Int", offsetY, "UInt", 0, "UInt", 0)

        Sleep, DelayRateAuto
        
        elapsed := A_TickCount - startTime

        if (elapsed >= interval) {
            currentY += Increment
            startTime := A_TickCount
        }
    }

    currentY := InitialY
}

; ===== Tap Fire Recoil =====
HandleTapFireAutoRecoil() {
    global RcCustomStrengthTapY, DelayRateTap

    if (!GetKeyState("XButton5", "P"))
        return

    SendInput {LButton Down}
    Sleep, DelayRateTap

    offsetX := 0
    offsetY := RcCustomStrengthTapY

    DllCall("mouse_event", "UInt", 1, "Int", offsetX, "Int", offsetY, "UInt", 0, "UInt", 0)

    SendInput {LButton Up}
    Sleep, DelayRateTap
}

; ===== XButton2 Step Control =====
~XButton2::
    lastOffsetX := 0
    stepSize := 0.5

    while (GetKeyState("XButton2", "P")) {
        lastOffsetX += stepSize
        if (lastOffsetX > RcCustomStrengthClampX)
            lastOffsetX := RcCustomStrengthClampX

        totalX := lastOffsetX
        totalY := RcCustomStrengthTapY

        SendInput {LButton Down}
        DllCall("mouse_event", "UInt", 1, "Int", totalX, "Int", totalY, "UInt", 0, "UInt", 0)
        Sleep, 50
    }
    SendInput {LButton Up}
return

; ===== Switch Profile =====
~XButton1::
    global profileIndex
    if (!profileIndex)
        profileIndex := 1
    profileIndex++
    if (profileIndex > profileList.MaxIndex())
        profileIndex := 1
    newProfile := profileList[profileIndex]
    loadProfile(newProfile)
return

; ===== Premium Modern GUI =====
F2::
Gui, Destroy
Gui, +LastFound +AlwaysOnTop -Caption +ToolWindow
Gui, Margin, 0, 0
Gui, Color, 0x0a0a0a

; Custom Border and Shadow Effect
Gui, Add, Progress, x0 y0 w650 h600 Background0a0a0a Disabled
Gui, Add, Progress, x5 y5 w640 h590 Background1a1a2e c00d9ff Disabled

; === Logo Area ===
Gui, Font, s24 Bold cFFFFFF, Arial
Gui, Add, Text, x50 y30 w540 h50 BackgroundTrans Center, NSTEX
Gui, Font, s10 Norm c00d9ff
Gui, Add, Text, x50 y80 w540 h25 BackgroundTrans Center, MACROSYNCX - Recoil Control Pro

; Decorative Line
Gui, Add, Progress, x50 y115 w540 h2 Background00d9ff cFFFFFF

; === Profile Section with Glow ===
Gui, Font, s9 Bold cFFFFFF
Gui, Add, Text, x50 y140 w200 h25 BackgroundTrans, SELECT PROFILE
Gui, Font, s8 Norm cFFFFFF
Gui, Add, DropDownList, x260 y137 vSelectedProfile w300 h25 gOnProfileChange, dpi 400|dpi 800|dpi 1600

; === Status Display ===
Gui, Add, Progress, x50 y175 w540 h35 Background16213e c00d9ff
Gui, Font, s8 c00ff88
Gui, Add, Text, x70 y182 vStatusText BackgroundTrans, ACTIVE: %currentProfile%

; === PRIMARY SETTINGS ===
Gui, Font, s10 Bold c00d9ff
Gui, Add, Text, x50 y230 w250 h25 BackgroundTrans, PRIMARY SETTINGS
Gui, Font, s8 Norm cFFFFFF

Gui, Add, Text, x70 y265 w150 BackgroundTrans, InitialY (Start):
Gui, Add, Edit, x220 y262 vInitialY w80 h22 Center, % profileData[currentProfile]["InitialY"]

Gui, Add, Text, x70 y295 w150 BackgroundTrans, AutoY (Full Auto):
Gui, Add, Edit, x220 y292 vAutoY w80 h22 Center, % profileData[currentProfile]["AutoY"]

Gui, Add, Text, x70 y325 w150 BackgroundTrans, TapY (Tap Fire):
Gui, Add, Edit, x220 y322 vTapY w80 h22 Center, % profileData[currentProfile]["TapY"]

; === SECONDARY SETTINGS ===
Gui, Font, s10 Bold c00d9ff
Gui, Add, Text, x340 y230 w250 h25 BackgroundTrans, SECONDARY SETTINGS
Gui, Font, s8 Norm cFFFFFF

Gui, Add, Text, x360 y265 w130 BackgroundTrans, AutoX (Horizontal):
Gui, Add, Edit, x490 y262 vAutoX w80 h22 Center, % profileData[currentProfile]["AutoX"]

Gui, Add, Text, x360 y295 w130 BackgroundTrans, AutoY_Up (Reduce):
Gui, Add, Edit, x490 y292 vAutoY_Up w80 h22 Center, % profileData[currentProfile]["AutoY_Up"]

Gui, Add, Text, x360 y325 w130 BackgroundTrans, ClampX (Limit):
Gui, Add, Edit, x490 y322 vClampX w80 h22 Center, % profileData[currentProfile]["ClampX"]

; Decorative Line
Gui, Add, Progress, x50 y360 w540 h2 Background00d9ff cFFFFFF

; === ADVANCED SETTINGS ===
Gui, Font, s10 Bold c00d9ff
Gui, Add, Text, x50 y380 w540 h25 BackgroundTrans Center, ADVANCED SETTINGS
Gui, Font, s8 Norm cFFFFFF

Gui, Add, Text, x70 y415 w150 BackgroundTrans, ShiftBoost (Shift):
Gui, Add, Edit, x220 y412 vShiftBoost w80 h22 Center, % profileData[currentProfile]["ShiftBoost"]

Gui, Add, Text, x360 y415 w130 BackgroundTrans, Increment (Per Sec):
Gui, Add, Edit, x490 y412 vIncrement w80 h22 Center, % profileData[currentProfile]["Increment"]

Gui, Add, Text, x70 y450 w150 BackgroundTrans, DelayRate (ms):
Gui, Add, Slider, x220 y447 vDelayRateAuto w350 h25 Range5-30 TickInterval5 ToolTip gUpdateDelay, % profileData[currentProfile]["DelayRateAuto"]
Gui, Add, Text, x575 y450 vDelayValue w50 c00ff88 BackgroundTrans, % profileData[currentProfile]["DelayRateAuto"]

; === Action Buttons with Hover Effect ===
Gui, Add, Button, x180 y510 w130 h40 gSaveProfileSettings, SAVE
Gui, Add, Button, x330 y510 w130 h40 gCloseGUI, CLOSE

Gui, Show, w650 h600, NSTEX MacroSyncX Pro
return

UpdateDelay:
Gui, Submit, NoHide
GuiControl,, DelayValue, %DelayRateAuto%
return

OnProfileChange:
Gui, Submit, NoHide
loadProfile(SelectedProfile)
GuiControl,, InitialY, % profileData[SelectedProfile]["InitialY"]
GuiControl,, AutoY, % profileData[SelectedProfile]["AutoY"]
GuiControl,, AutoX, % profileData[SelectedProfile]["AutoX"]
GuiControl,, AutoY_Up, % profileData[SelectedProfile]["AutoY_Up"]
GuiControl,, TapY, % profileData[SelectedProfile]["TapY"]
GuiControl,, ClampX, % profileData[SelectedProfile]["ClampX"]
GuiControl,, DelayRateAuto, % profileData[SelectedProfile]["DelayRateAuto"]
GuiControl,, ShiftBoost, % profileData[SelectedProfile]["ShiftBoost"]
GuiControl,, Increment, % profileData[SelectedProfile]["Increment"]
GuiControl,, StatusText, ACTIVE: %SelectedProfile%
GuiControl,, DelayValue, % profileData[SelectedProfile]["DelayRateAuto"]
return

SaveProfileSettings:
Gui, Submit, NoHide
profileData[SelectedProfile]["InitialY"] := InitialY
profileData[SelectedProfile]["AutoY"] := AutoY
profileData[SelectedProfile]["AutoX"] := AutoX
profileData[SelectedProfile]["AutoY_Up"] := AutoY_Up
profileData[SelectedProfile]["TapY"] := TapY
profileData[SelectedProfile]["ClampX"] := ClampX
profileData[SelectedProfile]["DelayRateAuto"] := DelayRateAuto
profileData[SelectedProfile]["ShiftBoost"] := ShiftBoost
profileData[SelectedProfile]["Increment"] := Increment
SaveProfileToFile(SelectedProfile)
loadProfile(SelectedProfile)
GuiControl,, StatusText, SAVED: %SelectedProfile%
SetTimer, ResetStatusText, -2000
return

ResetStatusText:
GuiControl,, StatusText, ACTIVE: %currentProfile%
return

CloseGUI:
Gui, Destroy
return

GuiClose:
Gui, Destroy
return

RemoveToolTip:
ToolTip
return