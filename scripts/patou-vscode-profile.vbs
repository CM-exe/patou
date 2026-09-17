' Adds (or updates) a "Patou Bash" entry in `terminal.integrated.profiles.windows`
' inside a VS Code user settings.json, so the bundled MSYS2 bash shows up as a
' selectable shell in VS Code's integrated-terminal dropdown. Downloaded and
' run by scripts/install.cmd, which has no PowerShell/JSON-parser dependency
' of its own - scripts/install.ps1 does the equivalent inline via a real
' ConvertFrom-Json/ConvertTo-Json read-modify-write instead.
'
' Adds the "terminal.integrated.profiles.windows" key itself if it isn't
' already there, then adds the "Patou Bash" entry under it if that isn't
' already there either - in both cases by locating the right insertion point
' with plain string search (InStr/Mid/Left) rather than a real JSON parser
' (VBScript doesn't have one built in), so everything else already in the
' file is left untouched.
'
' Reads its inputs from environment variables (set by install.cmd right
' before invoking this script) instead of command-line arguments, so paths
' with spaces or other special characters never have to survive being
' quoted for both cmd.exe and this script at once:
'   PATOU_VSCODE_SETTINGS   path to the settings.json to update
'   PATOU_VSCODE_BASH_PATH  path to the bundled bash.exe
'   PATOU_VSCODE_HOME_POSIX POSIX-style $HOME path, e.g. /c/Users/bob
'
' Prints exactly one line to stdout: OK (wrote the file), SKIP (a
' "Patou Bash" entry was already present, file untouched), or ERROR <reason>
' (also untouched). install.cmd reads that line to decide what to tell the
' user.

Function JsonEscape(s)
    s = Replace(s, "\", "\\")
    s = Replace(s, Chr(34), "\" & Chr(34))
    JsonEscape = s
End Function

Dim shellObj, env, settingsPath, bashPath, homePosix
Set shellObj = CreateObject("WScript.Shell")
Set env = shellObj.Environment("Process")
settingsPath = env("PATOU_VSCODE_SETTINGS")
bashPath = JsonEscape(env("PATOU_VSCODE_BASH_PATH"))
homePosix = JsonEscape(env("PATOU_VSCODE_HOME_POSIX"))

If settingsPath = "" Or bashPath = "" Then
    WScript.Echo "ERROR missing required environment variables"
    WScript.Quit 1
End If

Dim fso
Set fso = CreateObject("Scripting.FileSystemObject")

Dim content
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

If Trim(content) = "" Then
    content = "{}"
End If

Dim q
q = Chr(34)

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

' Written via ADODB.Stream (not FileSystemObject.CreateTextFile, which is
' limited to the system codepage or plain UTF-16) so the file stays UTF-8 -
' matching what VS Code itself writes, and safe for any non-ASCII content
' already in the file (usernames, comments, etc). The Type-2-then-1 dance
' strips the 3-byte UTF-8 BOM ADODB.Stream would otherwise prepend, which
' VS Code's own settings.json files don't carry.
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

WScript.Echo "OK"
