Dim key, script
key    = WScript.Arguments(0)
script = WScript.Arguments(1)
CreateObject("WScript.Shell").Run "cmd /c set DEEPSEEK_API_KEY=" & key & " && node """ & script & """", 0, False
