; This script lets you press a key (default middle mouse) within an Explorer Save/Open dialog window, and it will show a list of paths from any currently open Directory Opus and/or Windows Explorer windows.
; Source Repo: https://github.com/ThioJoe/AHK-Scripts
; Parts of the logic from this script: https://gist.github.com/akaleeroy/f23bd4dd2ddae63ece2582ede842b028#file-currently-opened-folders-md

; HOW TO USE:
; Either run this script by itself, or include it in your main script using #Include
; Ensure the required RemoteTreeView class file is in the location in the #Include line
; Set the dialogMenuHotkey variable to the hotkey you want to use to show the menu
; Edit any configuration variables as needed

#Requires AutoHotkey v2.0
#SingleInstance force
SetWorkingDir(A_ScriptDir)
; Set the path to the RemoteTreeView class file as necessary. Here it is up one directory then in the Lib folder. Necessary to navigate legacy folder dialogs.
; Can be acquired from: https://github.com/ThioJoe/AHK-RemoteTreeView-V2/blob/main/RemoteTreeView.ahk
#Include "..\Lib\RemoteTreeView.ahk"

; ---------------------------------------- DEFAULT USER SETTINGS ----------------------------------------
; These will be overridden by settings in the settings ini file if it exists. Otherwise these defaults will be used.
class DefaultSettings {
    ; Hotkey to show the menu. Default is Middle Mouse Button. If including this script in another script, you could choose to set this hotkey in the main script and comment this line out
    static dialogMenuHotkey := "~MButton"
    ; Enable debug mode to show tooltips with debug info
    static enableExplorerDialogMenuDebug := false
    ; Whether to show the disabled clipboard path menu item when no valid path is found on the clipboard, or only when a valid path is found on the clipboard
    static alwaysShowClipboardmenuItem := true
    ; Whether to enable UI access by default to allow the script to run in elevated windows without running as admin
    static enableUIAccess := true
    static activeTabSuffix := ""            ;  Appears to the right of the active path for each window group
    static activeTabPrefix := "► "          ;  Appears to the left of the active path for each window group
    static standardEntryPrefix := "    "    ; Indentation for inactive tabs, so they line up
    static dopusRTPath := ""  ; Path to dopusrt.exe - can be empty to disable Directory Opus integration
}

; ------------------------------------------ INITIALIZATION ----------------------------------------------------

; Global variable to hold current settings
global g_settings := {}
global settingsFileName := "ExplorerDialogPathSelector-Settings.ini"
settingsFileDirectory := A_ScriptDir
global settingsFilePath := settingsFileDirectory "\" settingsFileName

InitializeSettings()
; If the script is running standalone and UI access is installed...
; Reload self with UI Access for the script - Allows usage within elevated windows protected by UAC without running the script as admin
; See Docs: https://www.autohotkey.com/docs/v1/FAQ.htm#uac
if (g_settings.enableUIAccess = true) and !A_IsCompiled and ThisScriptRunningStandalone() and !InStr(A_AhkPath, "_UIA") {
    Run "*uiAccess " A_ScriptFullPath
    ExitApp
}

UpdateHotkeyFromSettings()

; ---------------------------------------- INITIALIZATION FUNCTIONS  ----------------------------------------------

DisplayDialogPathMenuCallback(ThisHotkey) {
    DisplayDialogPathMenu()
}

UpdateHotkeyFromSettings(previousHotkeyString := "") {
    if (previousHotkeyString != "") {
        try {
            HotKey(previousHotkeyString, "Off")
        }
        catch Error as hotkeyUnsetErr {
            MsgBox("Error disabling previous hotkey: " hotkeyUnsetErr.Message "`n`nHotkey Attempted to Disable:`n" previousHotkeyString "`n`nWill still try to set new hotkey.")
        }
    }

    try {
        HotKey(g_settings.dialogMenuHotkey, DisplayDialogPathMenuCallback)
    }
    catch Error as hotkeySetErr {
        MsgBox("Error setting hotkey: " hotkeySetErr.Message "`n`nHotkey Set To:`n" g_settings.dialogMenuHotkey)
    }
}

InitializeSettings() {
    try {
        if FileExist(settingsFilePath) {
            ; Load each setting from the INI file
            g_settings.dialogMenuHotkey := IniRead(settingsFilePath, "Settings", "dialogMenuHotkey", DefaultSettings.dialogMenuHotkey)
            g_settings.dopusRTPath := IniRead(settingsFilePath, "Settings", "dopusRTPath", DefaultSettings.dopusRTPath)
            g_settings.activeTabPrefix := IniRead(settingsFilePath, "Settings", "activeTabPrefix", DefaultSettings.activeTabPrefix)
            g_settings.activeTabSuffix := IniRead(settingsFilePath, "Settings", "activeTabSuffix", DefaultSettings.activeTabSuffix)
            g_settings.standardEntryPrefix := IniRead(settingsFilePath, "Settings", "standardEntryPrefix", DefaultSettings.standardEntryPrefix)
            g_settings.enableExplorerDialogMenuDebug := IniRead(settingsFilePath, "Settings", "enableExplorerDialogMenuDebug", DefaultSettings.enableExplorerDialogMenuDebug)
            g_settings.alwaysShowClipboardmenuItem := IniRead(settingsFilePath, "Settings", "alwaysShowClipboardmenuItem", DefaultSettings.alwaysShowClipboardmenuItem)
            g_settings.enableUIAccess := IniRead(settingsFilePath, "Settings", "enableUIAccess", DefaultSettings.enableUIAccess)
            
            ; Convert string boolean values to actual booleans
            g_settings.enableExplorerDialogMenuDebug := g_settings.enableExplorerDialogMenuDebug = "1"
            g_settings.alwaysShowClipboardmenuItem := g_settings.alwaysShowClipboardmenuItem = "1"
            g_settings.enableUIAccess := g_settings.enableUIAccess = "1"
        } else {
            ; If no settings file exists, use defaults
            for k, v in DefaultSettings.OwnProps() {
                g_settings.%k% := DefaultSettings.%k%
            }
        }
    }
    catch Error as err {
        MsgBox("Error reading settings file: " err.Message "`n`nUsing default settings.")
        for k, v in DefaultSettings.OwnProps() {
            g_settings.%k% := DefaultSettings.%k%
        }
    }

    ; ----- Special handling for certain settings -----

    ; For UI Access, always disable if not running standalone
    if !ThisScriptRunningStandalone() {
        g_settings.enableUIAccess := false
    }

    return
}

; ---------------------------------------- UTILITY FUNCTIONS  ----------------------------------------------
; Function to check if the script is running standalone or included in another script
ThisScriptRunningStandalone() {
    ;MsgBox("A_ScriptName: " A_ScriptFullPath "`n`nA_LineFile: " A_LineFile "`n`nRunning Standalone: " (A_ScriptFullPath = A_LineFile ? "True" : "False"))
    return A_ScriptFullPath = A_LineFile
}

; ------------------------------------ MAIN LOGIC FUNCTIONS ---------------------------------------------------


; Navigate to the chosen path
f_Navigate(A_ThisMenuItem := "", A_ThisMenuItemPos := "", MyMenu := "", *) {
    global
    ; Strip any prefix markers from the path
    f_path := RegExReplace(A_ThisMenuItem, "^[►▶→•\s]+\s*", "")
    ; Strip any custom suffix if present
    if (g_settings.activeTabSuffix)
        f_path := RegExReplace(f_path, "\Q" g_settings.activeTabSuffix "\E$", "")
    
    if (f_path = "")
        return

    if (f_class = "#32770") ; It's a dialog
    {
        WinActivate("ahk_id " f_window_id)
        
        ; Check if it's a legacy dialog
        if (dialogInfo := DetectDialogType(f_window_id)) {
            ; Use the legacy navigation approach
            NavigateDialog(f_path, f_window_id, dialogInfo)
        } else {
            ; Use the existing modern dialog approach
            Send("!{d}")
            Sleep(50)
            addressbar := ControlGetFocus("a")
            ControlSetText(f_path, addressbar, "a")
            ControlSend("{Enter}", addressbar, "a")
            ControlFocus("Edit1", "a")
        }
        return
    } else if (f_class = "ConsoleWindowClass") {   
        WinActivate("ahk_id " f_window_id)
        SetKeyDelay(0)
        Send("{Esc}pushd " f_path "{Enter}")
        return
    }
}

RemoveToolTip() {
    SetTimer(RemoveToolTip, 0)
    ToolTip()
}

; Get Explorer paths
getAllExplorerPaths() {
    paths := []
    
    ; Get all CabinetWClass windows
    explorerHwnds := WinGetList("ahk_class CabinetWClass")
    
    ; Get Shell.Application once
    shell := ComObject("Shell.Application")
    
    ; IShellBrowser interface ID
    static IID_IShellBrowser := "{000214E2-0000-0000-C000-000000000046}"
    
    ; For each Explorer window
    for explorerHwnd in explorerHwnds {
        try {
            ; First get the main window path
            for window in shell.Windows {
                try {
                    if window && window.hwnd && window.hwnd = explorerHwnd {
                        path := window.Document.Folder.Self.Path
                        if path && !HasValue(paths, path)
                            paths.Push(path)
                        
                        ; Now try to get tabs
                        tabCtrl := ControlGetHwnd("ShellTabWindowClass1", explorerHwnd)
                        if tabCtrl {
                            ; Get the shell browser interface
                            shellBrowser := ComObjQuery(window, IID_IShellBrowser, IID_IShellBrowser)
                            if shellBrowser {
                                try {
                                    ; Get the tab window object
                                    tabWindow := window.Document.Application.Windows
                                    if tabWindow {
                                        ; Loop through shell windows again to find ones matching this window's tabs
                                        for tabShell in shell.Windows {
                                            try {
                                                if tabShell && tabShell.hwnd = explorerHwnd {
                                                    tabPath := tabShell.Document.Folder.Self.Path
                                                    if tabPath && !HasValue(paths, tabPath)
                                                        paths.Push(tabPath)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        break  ; Found the main window, move to next explorer
                    }
                }
            }
        }
    }
    return paths
}

; Helper function to check if value exists in array
HasValue(haystack, needle) {
    if !(IsObject(haystack))
        return false
    for index, value in haystack {
        if (value = needle)
            return true
    }
    return false
}

; Parse the XML and return an array of path objects
GetDOpusPaths() {
    if (g_settings.dopusRTPath = "") {
        return []
    }

    if !FileExist(g_settings.dopusRTPath) {
        MsgBox("Directory Opus Runtime (dopusrt.exe) not found at:`n" g_settings.dopusRTPath "`n`nDirectory Opus integration won't work. To enable it, set the correct path in the script configuration. Or set it to an empty string to avoid this error.", "DOpus Integration Error", "Icon!")
        return []
    }
    
    tempFile := A_Temp "\dopus_paths.xml"
    try FileDelete(tempFile)
    
    try {
        cmd := '"' g_settings.dopusRTPath '" /info "' tempFile '",paths'
        RunWait(cmd,, "Hide")
        
        if !FileExist(tempFile)
            return []
        
        xmlContent := FileRead(tempFile)
        FileDelete(tempFile)
        
        ; Parse paths from XML
        paths := []
        
        ; Start after the XML declaration
        xmlContent := RegExReplace(xmlContent, "^.*?<results.*?>", "")
        
        ; Extract each path element with its attributes
        while RegExMatch(xmlContent, "s)<path([^>]*)>(.*?)</path>", &match) {
            ; Get attributes
            attrs := Map()
            RegExMatch(match[1], "lister=`"(0x[^`"]*)`"", &listerMatch)
            RegExMatch(match[1], "active_tab=`"([^`"]*)`"", &activeTabMatch)
            RegExMatch(match[1], "active_lister=`"([^`"]*)`"", &activeListerMatch)
            
            ; Create path object
            pathObj := {
                path: match[2],
                lister: listerMatch ? listerMatch[1] : "unknown",
                isActiveTab: activeTabMatch ? (activeTabMatch[1] = "1") : false,
                isActiveLister: activeListerMatch ? (activeListerMatch[1] = "1") : false
            }
            paths.Push(pathObj)
            
            ; Remove the processed path element and continue searching
            xmlContent := SubStr(xmlContent, match.Pos + match.Len)
        }
        
        return paths
    }
    catch as err {
        MsgBox("Error reading Directory Opus paths: " err.Message "`n`nDirectory Opus integration will be disabled.", "DOpus Integration Error", "Icon!")
        return []
    }
}

; Display the menu
DisplayDialogPathMenu() {
    global
    if (g_settings.enableExplorerDialogMenuDebug)
    {
        ToolTip("Hotkey Pressed: " A_ThisHotkey)
        Sleep(1000)
        ToolTip()
    }

    ; Detect windows with error handling
    try {
        f_window_id := WinGetID("a")
        f_class := WinGetClass("a")
    } catch as err {
        ; If we can't get window info, wait briefly and try once more
        Sleep(25)
        try {
            f_window_id := WinGetID("a")
            f_class := WinGetClass("a")
        } catch as err {
            if (g_settings.enableExplorerDialogMenuDebug)
            {
                ToolTip("Unable to detect active window")
                Sleep(1000)
                ToolTip()
            }
            return
        }
    }

    ; Verify we got valid window info
    if (!f_window_id || !f_class) {
        if (g_settings.enableExplorerDialogMenuDebug)
        {
            ToolTip("No valid window detected")
            Sleep(1000)
            ToolTip()
        }
        return
    }

    if (g_settings.enableExplorerDialogMenuDebug)
    {
        ToolTip("Window ID: " f_window_id "`nClass: " f_class)
        Sleep(1000)
        ToolTip()
    }

    ; Don't display menu unless it's a dialog or console window
    if !(f_class ~= "^(?i:#32770|ConsoleWindowClass)$")
    {
        if (g_settings.enableExplorerDialogMenuDebug)
        {
            ToolTip("Window class does not match expected: " f_class)
            Sleep(1000)
            ToolTip()
        }
        return
    }

    ; Proceed to display the menu
    CurrentLocations := Menu()
    hasItems := false
    
    ; Only get Directory Opus paths if dopusRTPath is set
    if (g_settings.dopusRTPath != "") {
        ; Get paths from Directory Opus using DOpusRT
        paths := GetDOpusPaths()
        
        ; Group paths by lister
        listers := Map()
        
        ; First, group all paths by their lister
        for pathObj in paths {
            if !listers.Has(pathObj.lister)
                listers[pathObj.lister] := []
            listers[pathObj.lister].Push(pathObj)
        }
        
        ; First add paths from active lister
        for pathObj in paths {
            if (pathObj.isActiveLister) {
                CurrentLocations.Add("Opus Window " A_Index " (Active)", f_Navigate)
                CurrentLocations.Disable("Opus Window " A_Index " (Active)")
                
                ; Add all paths for this lister
                listerPaths := listers[pathObj.lister]
                for tabObj in listerPaths {
                    menuText := tabObj.path
                    ; Add prefix and suffix for active tab based on global settings
                    if (tabObj.isActiveTab)
                        menuText := g_settings.activeTabPrefix menuText g_settings.activeTabSuffix
                    else
                        menuText := g_settings.standardEntryPrefix menuText
                    
                    CurrentLocations.Add(menuText, f_Navigate)
                    CurrentLocations.SetIcon(menuText, A_WinDir . "\system32\imageres.dll", "4")
                    hasItems := true
                }
                
                ; Remove this lister from the map so we don't show it again
                listers.Delete(pathObj.lister)
                break
            }
        }
        
        ; Then add remaining Directory Opus listers
        windowNum := 2
        for lister, listerPaths in listers {
            CurrentLocations.Add("Opus Window " windowNum, f_Navigate)
            CurrentLocations.Disable("Opus Window " windowNum)
            
            ; Add all paths for this lister
            for pathObj in listerPaths {
                menuText := pathObj.path
                ; Add prefix and suffix for active tab based on global settings
                if (pathObj.isActiveTab)
                    menuText := g_settings.activeTabPrefix menuText g_settings.activeTabSuffix
                else
                    menuText := g_settings.standardEntryPrefix menuText
                    
                CurrentLocations.Add(menuText, f_Navigate)
                CurrentLocations.SetIcon(menuText, A_WinDir . "\system32\imageres.dll", "4")
                hasItems := true
            }
            
            windowNum++
        }
    }

    ; Get Explorer paths
    explorerPaths := getAllExplorerPaths()
    
    ; Add Explorer paths if any exist
    if explorerPaths.Length > 0 {
        ; Add separator if we had Directory Opus paths
        if (hasItems)
            CurrentLocations.Add()
        
        ; Add Explorer header
        CurrentLocations.Add("Windows Explorer", f_Navigate)
        CurrentLocations.Disable("Windows Explorer")
        
        ; Add Explorer paths
        for path in explorerPaths {
            menuText := g_settings.standardEntryPrefix path
            CurrentLocations.Add(menuText, f_Navigate)
            CurrentLocations.SetIcon(menuText, A_WinDir . "\system32\imageres.dll", "4")
            hasItems := true
        }
    }

    ; If there is a path in the clipboard, add it to the menu
    if DllCall("Shlwapi\PathIsDirectoryW", "Str", A_Clipboard) != 0 {
        ; Add separator if we had Directory Opus or Explorer paths
        if (hasItems)
            CurrentLocations.Add()
        
        menuText := g_settings.standardEntryPrefix A_Clipboard
        CurrentLocations.Add(menuText, f_Navigate)
        CurrentLocations.SetIcon(menuText, A_WinDir . "\system32\imageres.dll", "-5301")
        hasItems := true
    } else if g_settings.alwaysShowClipboardmenuItem = true {
        ; If there is no path in the clipboard, add an option to enter a path
        if (hasItems)
            CurrentLocations.Add()

        menuText := g_settings.standardEntryPrefix "Paste path from clipboard"
        CurrentLocations.Add(menuText, f_Navigate) ; Still need the function even if it's disabled
        CurrentLocations.SetIcon(menuText, A_WinDir . "\system32\imageres.dll", "-5301")
        CurrentLocations.Disable(menuText)
    }

    ; Show menu if we have items, otherwise show tooltip
    if (hasItems) {
        CurrentLocations.Show()
    } else {
        ToolTip("No folders open")
        SetTimer(RemoveToolTip, 1000)
    }

    ; Clean up
    CurrentLocations := ""
}

ShowPathEntryBox(*) {
    path := InputBox("Enter a path to navigate to", "Path", "w300 h100")
    
    ; Check if user cancelled the InputBox
    if (path.Result = "Cancel")
        return ""

    ; Trim whitespace
    trimmedPath := Trim(path.Value)
        
    ; Check if the input is empty
    if (trimmedPath = "")
        return ""

    ; Use Windows API to check if the directory exists. Also works for UNC paths
    if DllCall("Shlwapi\PathIsDirectoryW", "Str", path) = 0 {
        MsgBox("Invalid path format. Please enter a valid path.")
        return ""
    }

    ; Navigate to the chosen path
    f_Navigate(trimmedPath)
}

DetectDialogType(hwnd) {
    ; Wait for the dialog window with class #32770 to be active
    if !WinWaitActive("ahk_class #32770",, 10) {
        return 0
    }

    ; try {
    ;     modernDialogControlHwnd := CheckIfModernDialog(hwnd)
    ;     if modernDialogControlHwnd != 0 {
    ;         return {Type: "ModernDialog", ControlHwnd: modernDialogControlHwnd}
    ;     }
    ; } catch {
    ;     ; Error occurred while checking for modern dialog
    ;     return 0
    ; }
    
    ; Look for an "Edit1" control, which is typically the file name edit box in file dialogs
    try {
        hFileNameEdit := ControlGetHwnd("Edit1", "ahk_class #32770")
        return {Type: "HasEditControl", ControlHwnd: hFileNameEdit}
    } catch {
        ; Try to get the handle of the TreeView control
        try {
            hTreeView := ControlGetHwnd("SysTreeView321", "ahk_class #32770")
            return {Type: "FolderBrowserDialog", ControlHwnd: hTreeView}
        } catch {
            ; Neither control found
            return 0
        }
    }
}

; CheckIfModernDialog(windowHwnd) {
;     testList := Object()
;     controls := WinGetControls(windowHwnd)
;     ; Go through controls that match "ToolbarWindow32*" in the class name and check if their text starts with "Address: "
;     for controlClassNN in controls {
;         if (controlClassNN ~= "ToolbarWindow32") {
;             controlText := ControlGetText(controlClassNN, windowHwnd)
;             if (controlText ~= "Address: ") {
;                 ; Get the hwnd of the address bar control
;                 controlHwnd := ControlGetHwnd(controlClassNN, windowHwnd)
;                 if (controlHwnd) {
;                     return controlHwnd
;                 }
;             }
;         }
;     }
;     return 0
; }

; GetAllControlObjects(windowHwnd) {
;     controls := WinGetControls(windowHwnd)
;     controlObjects := Map()  ; Changed from Object() to Map()
;     for controlClassNN in controls {
;         try {
;             controlHwnd := ControlGetHwnd(controlClassNN, windowHwnd)
;             controlText := ControlGetText(controlClassNN, windowHwnd)
;             ControlID := DllCall("GetDlgCtrlID", "Ptr", controlHwnd, "Int")
;             controlObjects[controlClassNN] := {Hwnd: controlHwnd, Text: controlText, ControlID: ControlID}
;         }
;         catch{
;             ; Skip this control
;         }
;     }
;     return controlObjects
; }

; Function to navigate to the specified path
NavigateDialog(path, windowHwnd, dialogInfo) {

    if (dialogInfo.Type = "HasEditControl") {
        ; Send the path to the edit control text box using SendMessage
        DllCall("SendMessage", "Ptr", dialogInfo.ControlHwnd, "UInt", 0x000C, "Ptr", 0, "Str", path) ; 0xC is WM_SETTEXT - Sets the text of the text box
        ; Tell the dialog to accept the text box contents, which will cause it to navigate to the path
        DllCall("SendMessage", "Ptr", windowHwnd, "UInt", 0x0111, "Ptr", 0x1, "Ptr", 0) ; command ID (0x1) typically corresponds to the IDOK control which represents the primary action button, whether it's labeled "Save" or "Open".
               
    } else if (dialogInfo.Type = "FolderBrowserDialog") {
        NavigateLegacyFolderDialog(path, dialogInfo.ControlHwnd)
    }
}

NavigateLegacyFolderDialog(path, hTV) {
    ; Initialize variables
    networkPath := ""
    driveLetter := ""
    hItem := ""

    ; Create RemoteTreeView object
    myTreeView := RemoteTreeView(hTV)

    ; Wait for the TreeView to load
    myTreeView.Wait()

    ; Split the path into components
    pathComponents := StrSplit(path, "\")
    ; Remove empty components caused by leading backslashes
    while (pathComponents.Length > 0 && pathComponents[1] = "") {
        pathComponents.RemoveAt(1)
    }

    ; Handle network paths starting with "\\"
    if (SubStr(path, 1, 2) = "\\") {
        networkPath := "\\" . pathComponents.RemoveAt(1)
        if pathComponents.Length > 0 {
            networkPath .= "\" . pathComponents.RemoveAt(1)
        }
    }

    ; Start from the "This PC" node (adjust for different Windows versions)
    startingNodes := ["This PC", "Computer", "My Computer", "Desktop"]
    for name in startingNodes {
        if (hItem := myTreeView.GetHandleByText(name)) {
            break
        }
    }
    if !hItem {
        MsgBox("Could not find a starting node like 'This PC' in the TreeView.")
        return
    }

    ; Expand the starting node
    myTreeView.Expand(hItem, true)

    ; If it's a network path
    if (networkPath != "") {
        ; Navigate to the network location
        hItem := NavigateToNode(myTreeView, hItem, networkPath)
        if !hItem {
            MsgBox("Could not find network path '" . networkPath . "' in the TreeView.")
            return
        }
    } else if (pathComponents.Length > 0 && pathComponents[1] ~= "^[A-Za-z]:$") {
        ; Handle drive letters
        driveLetter := pathComponents.RemoveAt(1)
        hItem := NavigateToNode(myTreeView, hItem, driveLetter, true) ; Pass true to indicate drive letter
        if !hItem {
            MsgBox("Could not find drive '" . driveLetter . "' in the TreeView.")
            return
        }
    } else {
        ; If path starts from a folder under starting node
        ; No action needed
    }

    ; Now navigate through the remaining components
    for component in pathComponents {
        hItem := NavigateToNode(myTreeView, hItem, component)
        if !hItem {
            MsgBox("Could not find folder '" . component . "' in the TreeView.")
            return
        }
    }

    ; Select the final item
    myTreeView.SetSelection(hItem, false)
    ; Optionally, send Enter to confirm selection
    ; Send("{Enter}")
}

; Helper function to navigate to a node with the given text under the given parent item
NavigateToNode(treeView, parentItem, nodeText, isDriveLetter := false) {
    treeView.Expand(parentItem, true)
    hItem := treeView.GetChild(parentItem)
    while (hItem) {
        itemText := treeView.GetText(hItem)
        if (isDriveLetter) {
            ; Special handling for drive letters. Look for them in parentheses, because they might show with name like "Primary (C:)"
            if (itemText ~= "i)\(" . RegExEscape(nodeText) . "\)") {
                ; Found the drive
                return hItem
            }
        } else {
            ; Regular matching for other nodes
            if (itemText ~= "i)^" . RegExEscape(nodeText) . "(\s|$)") {
                ; Found the item
                return hItem
            }
        }
        hItem := treeView.GetNext(hItem)
    }
    return 0
}

; Helper function to escape special regex characters in node text
RegExEscape(str) {
    static chars := "[\^\$\.\|\?\*\+\(\)\{\}\[\]\\]"
    return RegExReplace(str, chars, "\$0")
}

; ----------------------------------------------------------------------------------------------
; ---------------------------------------- GUI-RELATED  ----------------------------------------
; ----------------------------------------------------------------------------------------------

; Function to show the settings GUI
ShowSettingsGUI(*) {
    ; Create the settings window
    settingsGui := Gui("+Resize", "Explorer Dialog Path Menu Settings")
    settingsGui.OnEvent("Size", GuiResize)

    hTT := CreateTooltipControl(settingsGui.Hwnd)
    
    ; Add controls - using current values from global variables
    labelHotkey := settingsGui.AddText("xm y10 w120 h23 +0x200", "Dialog Menu Hotkey:")
    hotkeyEdit := settingsGui.AddEdit("x+10 yp w200", g_settings.dialogMenuHotkey)
    labelhotkeyTooltipText := "Enter the key or key combination that will trigger the dialog menu`nMust use AutoHotkey syntax (AHK V2)`n`nTip: Add a tilde (~) before the key to ensure the hotkey doesn't block the key's normal functionality.`nExample:  ~MButton"
    AddTooltipToControl(hTT, labelHotkey.Hwnd, labelhotkeyTooltipText)
    AddTooltipToControl(hTT, hotkeyEdit.Hwnd, labelhotkeyTooltipText)
    
    labelOpusRTPath := settingsGui.AddText("xm y+10 w120 h23 +0x200", "DOpus RT Path:")
    dopusPathEdit := settingsGui.AddEdit("x+10 yp w200", g_settings.dopusRTPath)
    labelOpusRTPathTooltipText := "*** For Directory Opus users *** `nPath to dopusrt.exe`n`nOr leave empty to disable Directory Opus integration."
    AddTooltipToControl(hTT, labelOpusRTPath.Hwnd, labelOpusRTPathTooltipText)
    AddTooltipToControl(hTT, dopusPathEdit.Hwnd, labelOpusRTPathTooltipText)
    ; Button to browse for DOpusRT
    browseBtn := settingsGui.AddButton("x+5 yp w60", "Browse...")
    browseBtn.OnEvent("Click", (*) => BrowseForDopusRT(dopusPathEdit))
    
    labelActiveTabPrefix := settingsGui.AddText("xm y+10 w120 h23 +0x200", "Active Tab Prefix:")
    prefixEdit := settingsGui.AddEdit("x+10 yp w200", g_settings.activeTabPrefix)
    labelActiveTabPrefixTooltipText := "Text/Characters that appears to the left of the active path for each window group"
    AddTooltipToControl(hTT, labelActiveTabPrefix.Hwnd, labelActiveTabPrefixTooltipText)
    AddTooltipToControl(hTT, prefixEdit.Hwnd, labelActiveTabPrefixTooltipText)
    
    labelActiveTabSuffix := settingsGui.AddText("xm y+10 w120 h23 +0x200", "Active Tab Suffix:")
    suffixEdit := settingsGui.AddEdit("x+10 yp w200", g_settings.activeTabSuffix)
    labelActiveTabSuffixTooltipText := "Text/Characters will appear to the right of the active path for each window group, if you want as a label."
    AddTooltipToControl(hTT, labelActiveTabSuffix.Hwnd, labelActiveTabSuffixTooltipText)
    AddTooltipToControl(hTT, suffixEdit.Hwnd, labelActiveTabSuffixTooltipText)
    
    labelStandardEntryPrefix := settingsGui.AddText("xm y+10 w120 h23 +0x200", "Standard Entry Prefix:")
    standardPrefixEdit := settingsGui.AddEdit("x+10 yp w200", g_settings.standardEntryPrefix)
    labelStandardEntryPrefixTooltipText := "Indentation spaces for inactive tabs, so they line up"
    AddTooltipToControl(hTT, labelStandardEntryPrefix.Hwnd, labelStandardEntryPrefixTooltipText)
    AddTooltipToControl(hTT, standardPrefixEdit.Hwnd, labelStandardEntryPrefixTooltipText)
    
    debugCheck := settingsGui.AddCheckbox("xm y+15", "Enable Debug Mode")
    debugCheck.Value := g_settings.enableExplorerDialogMenuDebug
    labelDebugCheckTooltipText := "Show tooltips with debug information when the hotkey is pressed.`nUseful for troubleshooting."
    AddTooltipToControl(hTT, debugCheck.Hwnd, labelDebugCheckTooltipText)
    
    clipboardCheck := settingsGui.AddCheckbox("xm y+10", "Always Show Clipboard Menu Item")
    clipboardCheck.Value := g_settings.alwaysShowClipboardmenuItem
    labelClipboardCheckTooltipText := "If Disabled: The option to paste the clipboard path will only appear when a valid path is found on the clipboard.`nIf Enabled: The menu entry will always appear, but is disabled when no valid path is found."
    AddTooltipToControl(hTT, clipboardCheck.Hwnd, labelClipboardCheckTooltipText)

    UIAccessCheck := settingsGui.AddCheckbox("xm y+10", "Enable UI Access")
    UIAccessCheck.Value := g_settings.enableUIAccess
    labelUIAccessCheckTooltipText := ""
    if !ThisScriptRunningStandalone() {
        UIAccessCheck.Value := 0
        UIAccessCheck.Enabled := 0

        ; Get position of the checkbox before disabling it so we can add an invisible box to apply the tooltip to
        ; Because the tooltip won't show on a disabled control
        x := 0, y := 0, w := 0, h := 0
        UIAccessCheck.GetPos(&x, &y, &w, &h)
        tooltipOverlay := settingsGui.AddText("x" x " y" y " w" w " h" h " +BackgroundTrans", "")

        labelUIAccessCheckTooltipText := "This script appears to be running as being included by another script. You should enable UI Access via the parent script instead."
        AddTooltipToControl(hTT, tooltipOverlay.Hwnd, labelUIAccessCheckTooltipText)
    } else {
        labelUIAccessCheckTooltipText := "Enable `"UI Access`" to allow the script to run in elevated windows protected by UAC without running as admin."
        AddTooltipToControl(hTT, UIAccessCheck.Hwnd, labelUIAccessCheckTooltipText)
    }
    
    ; Add buttons at the bottom
    buttonsY := "y+20"
    ; Reset button
    resetBtn := settingsGui.AddButton("xm " buttonsY " w80", "Defaults")
    resetBtn.OnEvent("Click", ResetSettings)
    settingsGui.AddButton("x+10 yp w80", "Cancel").OnEvent("Click", (*) => settingsGui.Destroy())
    labelButtonResetTooltipText := "Sets all settings above to their default values.`nYou'll still need to click Save to apply the changes."
    AddTooltipToControl(hTT, resetBtn.Hwnd, labelButtonResetTooltipText)
    ; Save button
    saveBtn := settingsGui.AddButton("x+10 yp w80 Default", "Save")
    saveBtn.OnEvent("Click", SaveSettings)
    labelButtonSaveTooltipText := "Save the current settings to a file to automatically load in the future."
    AddTooltipToControl(hTT, saveBtn.Hwnd, labelButtonSaveTooltipText)

    ; Set variables to track when certain settings are changed for special handling
    UIAccessInitialValue := g_settings.enableUIAccess
    HotkeyInitialValue := g_settings.dialogMenuHotkey
    
    ; Show the GUI
    settingsGui.Show()
    
    ResetSettings(*) {
        hotkeyEdit.Value := DefaultSettings.dialogMenuHotkey
        dopusPathEdit.Value := DefaultSettings.dopusRTPath
        prefixEdit.Value := DefaultSettings.activeTabPrefix
        suffixEdit.Value := DefaultSettings.activeTabSuffix
        standardPrefixEdit.Value := DefaultSettings.standardEntryPrefix
        debugCheck.Value := DefaultSettings.enableExplorerDialogMenuDebug
        clipboardCheck.Value := DefaultSettings.alwaysShowClipboardmenuItem
        UIAccessCheck.Value := DefaultSettings.enableUIAccess
    }
    
    SaveSettings(*) {
        ; Update settings object
        g_settings.dialogMenuHotkey := hotkeyEdit.Value
        g_settings.dopusRTPath := dopusPathEdit.Value
        ; Put quotes around the prefix and suffix values, otherwise spaces will be trimmed by the OS. The quotes will be removed when the values are read
        g_settings.activeTabPrefix := '"' prefixEdit.Value '"'
        g_settings.activeTabSuffix := '"' suffixEdit.Value '"'
        g_settings.standardEntryPrefix := '"' standardPrefixEdit.Value '"'
        g_settings.enableExplorerDialogMenuDebug := debugCheck.Value
        g_settings.alwaysShowClipboardmenuItem := clipboardCheck.Value
        g_settings.enableUIAccess := UIAccessCheck.Value
        
        ; Save to settings file
        SaveSettingsToFile()
        
        ; When UI Access goes from enabled to disabled, the user must manually close and re-run the script
        if (UIAccessInitialValue = true && UIAccessCheck.Value = false) {
            MsgBox("NOTE: When changing UI Access from Enabled to Disabled, you must manually close and re-run the script/app for changes to take effect.", "Settings Saved - Process Restart Required", "Icon!")
        } else {
            ; The rest of the settings don't require a restart, they are pulled directly from the settings object which has been updated
        }

        ; Disable the original hotkey by passing in the previous hotkey string
        UpdateHotkeyFromSettings(HotkeyInitialValue)
        settingsGui.Destroy()
    }
    
    GuiResize(thisGui, minMax, width, height) {
        if minMax = -1  ; The window has been minimized
            return
        
        ; Update control positions based on new window size
        for ctrl in thisGui {
            if ctrl.HasProp("Type") {
                if ctrl.Type = "Edit" {
                    ; Leave space for the Browse button if this is the DOpus path edit box
                    if (ctrl.HasProp("ClassNN") && ctrl.ClassNN = "Edit2") {
                        ctrl.Move(,, width - 220)  ; Leave extra space for Browse button
                    } else {
                        ctrl.Move(,, width - 150)  ; Standard width for other edit controls
                    }
                } else if ctrl.Type = "Button" && ctrl.Text = "Browse..." {
                    ctrl.Move(width - 75)  ; Anchor Browse button to window edge
                }
            }
        }
    }
}

; Create a tooltip control window and return its handle
CreateTooltipControl(guiHwnd) {
    ; Create tooltip window
    static ICC_TAB_CLASSES := 0x8
    static CW_USEDEFAULT := 0x80000000
    static TTS_ALWAYSTIP := 0x01
    static TTS_NOPREFIX := 0x02
    static WS_POPUP := 0x80000000
    
    ; Initialize common controls
    INITCOMMONCONTROLSEX := Buffer(8, 0)
    NumPut("UInt", 8, "UInt", ICC_TAB_CLASSES, INITCOMMONCONTROLSEX)
    DllCall("comctl32\InitCommonControlsEx", "Ptr", INITCOMMONCONTROLSEX)
    
    ; Create tooltip window
    hTT := DllCall("CreateWindowEx", "UInt", 0
        , "Str", "tooltips_class32"
        , "Ptr", 0
        , "UInt", TTS_ALWAYSTIP | TTS_NOPREFIX | WS_POPUP
        , "Int", CW_USEDEFAULT
        , "Int", CW_USEDEFAULT
        , "Int", CW_USEDEFAULT
        , "Int", CW_USEDEFAULT
        , "Ptr", guiHwnd
        , "Ptr", 0
        , "Ptr", 0
        , "Ptr", 0
        , "Ptr")

    ; Set maximum width to enable word wrapping and newlines in tooltips
    static TTM_SETMAXTIPWIDTH := 0x418
    DllCall("SendMessage", "Ptr", hTT, "UInt", TTM_SETMAXTIPWIDTH, "Ptr", 0, "Ptr", 600)

    return hTT
}

; Add a tooltip to a control
AddTooltipToControl(hTT, controlHwnd, text) {
    ; TTM_ADDTOOLW - Unicode version only
    static TTM_ADDTOOL := 0x432
    ; Enum values used in TOOLINFO structure - See: https://learn.microsoft.com/en-us/windows/win32/api/commctrl/ns-commctrl-tttoolinfow
    static TTF_IDISHWND := 0x1
    static TTF_SUBCLASS := 0x10
    ; Static control style - See: https://learn.microsoft.com/en-us/windows/win32/controls/static-control-styles
    static SS_NOTIFY := 0x100
    static GWL_STYLE := -16 ; Used in SetWindowLongPtr: https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowlongptrw
    
    ; Check if this is a static text control and add SS_NOTIFY style if needed
    className := Buffer(256)
    if DllCall("GetClassName", "Ptr", controlHwnd, "Ptr", className, "Int", 256) {
        if (StrGet(className) = "Static") {
            ; Get current style
            currentStyle := DllCall("GetWindowLongPtr", "Ptr", controlHwnd, "Int", GWL_STYLE, "Ptr")
            ; Add SS_NOTIFY if it's not already there
            if !(currentStyle & SS_NOTIFY)
                DllCall("SetWindowLongPtr", "Ptr", controlHwnd, "Int", GWL_STYLE, "Ptr", currentStyle | SS_NOTIFY)
        }
    }
    
    ; Create and populate TOOLINFO structure
    TOOLINFO := Buffer(A_PtrSize = 8 ? 72 : 44, 0)  ; Size differs between 32 and 64 bit
    
    ; Calculate size of TOOLINFO structure
    cbSize := A_PtrSize = 8 ? 72 : 44
    
    ; Populate TOOLINFO structure
    NumPut("UInt", cbSize, TOOLINFO, 0)   ; cbSize
    NumPut("UInt", TTF_IDISHWND | TTF_SUBCLASS, TOOLINFO, 4)   ; uFlags
    NumPut("Ptr",  controlHwnd,  TOOLINFO, A_PtrSize = 8 ? 16 : 12)  ; hwnd
    NumPut("Ptr",  controlHwnd,  TOOLINFO, A_PtrSize = 8 ? 24 : 16)  ; uId
    NumPut("Ptr",  StrPtr(text), TOOLINFO, A_PtrSize = 8 ? 48 : 36)  ; lpszText
    
    ; Add the tool
    result := DllCall("SendMessage", "Ptr", hTT, "UInt", TTM_ADDTOOL, "Ptr", 0, "Ptr", TOOLINFO)
    return result
}

BrowseForDopusRT(editControl) {
    selectedFile := FileSelect(3,, "Select dopusrt.exe", "Executable (*.exe)")
    if selectedFile
        editControl.Value := selectedFile
}

SaveSettingsToFile() {
    fileAlreadyExisted := (FileExist(settingsFilePath) != "") ; If an empty string is returned from FileExist, the file was not found

    ; Save all settings to INI file
    IniWrite(g_settings.dialogMenuHotkey, settingsFilePath, "Settings", "dialogMenuHotkey")
    IniWrite(g_settings.dopusRTPath, settingsFilePath, "Settings", "dopusRTPath")
    IniWrite(g_settings.activeTabPrefix, settingsFilePath, "Settings", "activeTabPrefix")
    IniWrite(g_settings.activeTabSuffix, settingsFilePath, "Settings", "activeTabSuffix")
    IniWrite(g_settings.standardEntryPrefix, settingsFilePath, "Settings", "standardEntryPrefix")
    IniWrite(g_settings.enableExplorerDialogMenuDebug ? "1" : "0", settingsFilePath, "Settings", "enableExplorerDialogMenuDebug")
    IniWrite(g_settings.alwaysShowClipboardmenuItem ? "1" : "0", settingsFilePath, "Settings", "alwaysShowClipboardmenuItem")
    IniWrite(g_settings.enableUIAccess ? "1" : "0", settingsFilePath, "Settings", "enableUIAccess")

    if (!fileAlreadyExisted) {
        MsgBox("Settings saved to file:`n" settingsFileName "`n`n Settings will be automatically loaded from file from now on.", "Settings File Created", "Iconi")
    }
}

; Add a tray menu item to show the settings GUI
A_TrayMenu.Insert("2&", "")  ; Separator
A_TrayMenu.Insert("3&", "Dialog Path Settings", ShowSettingsGUI)
