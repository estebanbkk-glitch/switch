' Launch DeepSeek Tray GUI (hidden console window)
Dim shell
Set shell = CreateObject("WScript.Shell")
shell.Run "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & _
    CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName) & _
    "\deepseek-tray.ps1""", 0, False
Set shell = Nothing
