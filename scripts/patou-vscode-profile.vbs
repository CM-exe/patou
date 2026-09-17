' Adds, or removes, the "Patou Bash" entry in `terminal.integrated.profiles.windows`
' inside a VS Code user settings.json - the bundled MSYS2 bash profile that
' shows up as a selectable shell in VS Code's integrated-terminal dropdown.
' Downloaded and run by scripts/install.cmd and scripts/uninstall.cmd, which
' have no PowerShell/JSON-parser dependency of their own - install.ps1 and
' uninstall.ps1 do the equivalent inline via a real
' ConvertFrom-Json/ConvertTo-Json read-modify-write instead.
'
' In add mode (the default), adds the "terminal.integrated.profiles.windows"
' key itself if it isn't already there, then adds the "Patou Bash" entry
' under it if that isn't already there either. In remove mode, removes the
' "Patou Bash" entry if present, then removes the
' "terminal.integrated.profiles.windows" key too if that's now empty. Both
' modes locate the right insertion/removal point with plain string search
' (InStr/Mid/Left, plus a brace-depth scan for remove) rather than a real
' JSON parser (VBScript doesn't have one built in), so everything else
' already in the file is left untouched.
'
' Reads its inputs from environment variables (set by install.cmd/
' uninstall.cmd right before invoking this script) instead of command-line
' arguments, so paths with spaces or other special characters never have to
' survive being quoted for both cmd.exe and this script at once:
'   PATOU_VSCODE_MODE       "add" (default) or "remove"
'   PATOU_VSCODE_SETTINGS   path to the settings.json to update
'   PATOU_VSCODE_BASH_PATH  path to the bundled bash.exe (add mode only)
'   PATOU_VSCODE_HOME_POSIX POSIX-style $HOME path, e.g. /c/Users/bob (add
'                           mode only)
'
' Prints exactly one line to stdout: OK (the file was changed), SKIP
' (nothing to do - already added, or already absent - file untouched), or
' ERROR <reason> (also untouched). The caller reads that line to decide
' what to tell the user.

Function JsonEscape(s)
    s = Replace(s, "\", "\\")
    s = Replace(s, Chr(34), "\" & Chr(34))
    JsonEscape = s
End Function

' Returns the position of the "}" that closes the "{" at openPos, skipping
' over brace characters that appear inside JSON string literals (respecting
' backslash escapes), so a stray "{"/"}" inside e.g. a path string doesn't
' throw off the count. Returns 0 if the content ends before the braces balance.
Function FindMatchingBrace(content, openPos)
    Dim depth, i, ch, inString, escaped
    depth = 0
    inString = False
    escaped = False
    For i = openPos To Len(content)
        ch = Mid(content, i, 1)
        If inString Then
            If escaped Then
                escaped = False
            ElseIf ch = "\" Then
                escaped = True
            ElseIf ch = Chr(34) Then
                inString = False
            End If
        Else
            If ch = Chr(34) Then
                inString = True
            ElseIf ch = "{" Then
                depth = depth + 1
            ElseIf ch = "}" Then
                depth = depth - 1
                If depth = 0 Then
                    FindMatchingBrace = i
                    Exit Function
                End If
            End If
        End If
    Next
    FindMatchingBrace = 0
End Function

' Removes the "key": { ... } entry whose key text starts at keyStart and
' whose value's opening brace is at valueOpenPos, along with exactly one
' adjacent comma (whichever side has one - the entry after it if there is
' one, otherwise the entry before it), so the result stays valid JSON
' either way. Sets ok = False (and returns content unchanged) if the value
' isn't a well-formed brace-delimited object.
Function RemoveEntryAt(content, keyStart, valueOpenPos, ok)
    ok = True
    Dim entryEnd
    entryEnd = FindMatchingBrace(content, valueOpenPos)
    If entryEnd = 0 Then
        ok = False
        RemoveEntryAt = content
        Exit Function
    End If

    Do While keyStart > 1
        Dim prevCh
        prevCh = Mid(content, keyStart - 1, 1)
        If prevCh = " " Or prevCh = vbTab Or prevCh = vbCr Or prevCh = vbLf Then
            keyStart = keyStart - 1
        Else
            Exit Do
        End If
    Loop

    Dim j, chAfter
    j = entryEnd + 1
    Do While j <= Len(content)
        chAfter = Mid(content, j, 1)
        If chAfter = " " Or chAfter = vbTab Or chAfter = vbCr Or chAfter = vbLf Then
            j = j + 1
        Else
            Exit Do
        End If
    Loop

    Dim deleteStart, deleteEnd
    If j <= Len(content) And Mid(content, j, 1) = "," Then
        deleteStart = keyStart
        deleteEnd = j
    Else
        Dim k, chBefore
        k = keyStart - 1
        Do While k >= 1
            chBefore = Mid(content, k, 1)
            If chBefore = " " Or chBefore = vbTab Or chBefore = vbCr Or chBefore = vbLf Then
                k = k - 1
            Else
                Exit Do
            End If
        Loop
        If k >= 1 And Mid(content, k, 1) = "," Then
            deleteStart = k
        Else
            deleteStart = keyStart
        End If
        deleteEnd = entryEnd
    End If

    RemoveEntryAt = Left(content, deleteStart - 1) & Mid(content, deleteEnd + 1)
End Function

Function ReadSettings(settingsPath)
    Dim fso, content
    Set fso = CreateObject("Scripting.FileSystemObject")
    content = ""
    If fso.FileExists(settingsPath) Then
        Dim reader
        Set reader = CreateObject("ADODB.Stream")
        reader.Type = 2 ' text
        reader.Charset = "utf-8"
        reader.Open
        reader.LoadFromFile settingsPath
        content = reader.ReadText
        reader.Close
        ' A UTF-8 BOM decodes to a leading U+FEFF character - drop it if
        ' present, so it doesn't end up duplicated (or misplaced) once rewritten.
        If Len(content) > 0 Then
            If AscW(Left(content, 1)) = 65279 Then
                content = Mid(content, 2)
            End If
        End If
    End If
    ReadSettings = content
End Function

' Written via ADODB.Stream (not FileSystemObject.CreateTextFile, which is
' limited to the system codepage or plain UTF-16) so the file stays UTF-8 -
' matching what VS Code itself writes, and safe for any non-ASCII content
' already in the file (usernames, comments, etc). The Type-2-then-1 dance
' strips the 3-byte UTF-8 BOM ADODB.Stream would otherwise prepend, which
' VS Code's own settings.json files don't carry.
Sub WriteSettings(settingsPath, newContent)
    Dim writer, bytes
    Set writer = CreateObject("ADODB.Stream")
    writer.Type = 2
    writer.Charset = "utf-8"
    writer.Open
    writer.WriteText newContent
    writer.Position = 0
    writer.Type = 1
    writer.Position = 3
    bytes = writer.Read(-1)
    writer.Close

    Dim outStream
    Set outStream = CreateObject("ADODB.Stream")
    outStream.Type = 1
    outStream.Open
    outStream.Write bytes
    outStream.SaveToFile settingsPath, 2 ' adSaveCreateOverWrite
    outStream.Close
End Sub

Dim shellObj, env, mode, settingsPath, q
Set shellObj = CreateObject("WScript.Shell")
Set env = shellObj.Environment("Process")
mode = env("PATOU_VSCODE_MODE")
If mode = "" Then mode = "add"
settingsPath = env("PATOU_VSCODE_SETTINGS")
q = Chr(34)

If settingsPath = "" Then
    WScript.Echo "ERROR missing required environment variables"
    WScript.Quit 1
End If

Dim content
content = ReadSettings(settingsPath)

If mode = "remove" Then
    If Trim(content) = "" Or InStr(content, q & "Patou Bash" & q) = 0 Then
        WScript.Echo "SKIP"
        WScript.Quit 0
    End If

    Dim entryKeyPos, entryBracePos, ok
    entryKeyPos = InStr(content, q & "Patou Bash" & q)
    entryBracePos = InStr(entryKeyPos, content, "{")
    If entryBracePos = 0 Then
        WScript.Echo "ERROR malformed 'Patou Bash' entry"
        WScript.Quit 1
    End If
    content = RemoveEntryAt(content, entryKeyPos, entryBracePos, ok)
    If Not ok Then
        WScript.Echo "ERROR malformed 'Patou Bash' entry"
        WScript.Quit 1
    End If

    ' Also drop `terminal.integrated.profiles.windows` itself if removing
    ' the entry above left it empty, mirroring
    ' uninstall.ps1's equivalent cleanup.
    Dim profilesKeyMarker, profilesKeyPos, profilesBracePos, profilesEnd
    profilesKeyMarker = q & "terminal.integrated.profiles.windows" & q
    profilesKeyPos = InStr(content, profilesKeyMarker)
    If profilesKeyPos > 0 Then
        profilesBracePos = InStr(profilesKeyPos, content, "{")
        If profilesBracePos > 0 Then
            profilesEnd = FindMatchingBrace(content, profilesBracePos)
            If profilesEnd > 0 And Trim(Mid(content, profilesBracePos + 1, profilesEnd - profilesBracePos - 1)) = "" Then
                content = RemoveEntryAt(content, profilesKeyPos, profilesBracePos, ok)
            End If
        End If
    End If

    WriteSettings settingsPath, content
    WScript.Echo "OK"
    WScript.Quit 0
End If

' add mode
Dim bashPath, homePosix
bashPath = JsonEscape(env("PATOU_VSCODE_BASH_PATH"))
homePosix = JsonEscape(env("PATOU_VSCODE_HOME_POSIX"))

If bashPath = "" Then
    WScript.Echo "ERROR missing required environment variables"
    WScript.Quit 1
End If

If Trim(content) = "" Then
    content = "{}"
End If

If InStr(content, q & "Patou Bash" & q) > 0 Then
    WScript.Echo "SKIP"
    WScript.Quit 0
End If

' "icon" is the closest built-in match rather than Patou's own logo: VS
' Code's terminal profile `icon` only accepts a built-in codicon ID for
' profiles defined this way in settings.json, not a path to a custom image
' (see microsoft/vscode issues #127607 and #119343). "color" at least tints
' it blue, in the spirit of the mintty theme's own grey/blue/light-blue
' palette (assets/patou-bash.minttyrc) - which otherwise has no equivalent
' here, since that palette only applies to mintty's own rendering and VS
' Code hosts this profile in its own terminal (xterm.js) instead. The
' ANSI-colored prompt/banner themselves (patou-prompt.sh/patou-banner.sh,
' sourced via --login below) still render the same way regardless of which
' terminal is hosting bash, since those come from bash's own escape codes.
Dim entryText
entryText = "    " & q & "Patou Bash" & q & ": { " & _
    q & "path" & q & ": " & q & bashPath & q & ", " & _
    q & "args" & q & ": [" & q & "--login" & q & ", " & q & "-i" & q & "], " & _
    q & "icon" & q & ": " & q & "terminal-bash" & q & ", " & _
    q & "color" & q & ": " & q & "terminal.ansiBlue" & q & ", " & _
    q & "env" & q & ": { " & q & "CHERE_INVOKING" & q & ": " & q & "1" & q & ", " & _
    q & "HOME" & q & ": " & q & homePosix & q & " } }"

Dim keyMarker
keyMarker = q & "terminal.integrated.profiles.windows" & q

Dim keyPos, bracePos, insertPos, rest, trimmedRest, blockText

keyPos = InStr(content, keyMarker)

If keyPos > 0 Then
    ' The key already exists - insert our entry right after the opening
    ' brace of its value, wherever that value's own "{" actually is (so
    ' this doesn't assume any particular spacing/newlines between the key
    ' and its brace).
    bracePos = InStr(keyPos, content, "{")
    If bracePos = 0 Then
        WScript.Echo "ERROR terminal.integrated.profiles.windows isn't a JSON object"
        WScript.Quit 1
    End If
    insertPos = bracePos + 1
    rest = Mid(content, insertPos)
    trimmedRest = LTrim(rest)
    If Left(trimmedRest, 1) = "}" Then
        blockText = vbCrLf & entryText & vbCrLf & "  "
    Else
        blockText = vbCrLf & entryText & ","
    End If
Else
    ' The key doesn't exist yet - add it (with our entry inside) right
    ' after the file's own top-level opening brace.
    bracePos = InStr(content, "{")
    If bracePos = 0 Then
        WScript.Echo "ERROR settings.json has no top-level JSON object"
        WScript.Quit 1
    End If
    insertPos = bracePos + 1
    rest = Mid(content, insertPos)
    trimmedRest = LTrim(rest)
    Dim keyBlock
    keyBlock = "  " & keyMarker & ": {" & vbCrLf & entryText & vbCrLf & "  }"
    If Left(trimmedRest, 1) = "}" Then
        blockText = vbCrLf & keyBlock & vbCrLf
    Else
        blockText = vbCrLf & keyBlock & ","
    End If
End If

Dim newContent
newContent = Left(content, insertPos - 1) & blockText & Mid(content, insertPos)

WriteSettings settingsPath, newContent

WScript.Echo "OK"
