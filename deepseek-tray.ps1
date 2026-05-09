# DeepSeek Switcher - System Tray GUI
# Saves API key to .claude\deepseek-key.txt
# Orange recycling icon = Claude (off), Blue recycling icon = DeepSeek (on)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$scriptDir = $PSScriptRoot
$proxyJs   = "$scriptDir\deepseek-proxy.js"
$keyFile   = "$scriptDir\deepseek-key.txt"
$configFile = "$scriptDir\deepseek-config.json"
$statsUrl  = "http://localhost:4000/v1/stats"
$port      = 4000
$script:proxyPidVal = $null

# -- persist / load config --
function Save-Config {
    $config = @{
        "proxy_on" = $false
    } | ConvertTo-Json -Compress
    [System.IO.File]::WriteAllText($configFile, $config)
}
function Load-Config {
    if (Test-Path $configFile) {
        try { return Get-Content $configFile -Raw | ConvertFrom-Json } catch { }
    }
    return $null
}

# -- helpers --
function Get-TrayIcon($blue) {
    # Recycling symbol (♻) on a colored circle
    $size = 16
    $img = New-Object System.Drawing.Bitmap($size, $size)
    $g = [System.Drawing.Graphics]::FromImage($img)
    $g.SmoothingMode = "HighQuality"
    $g.TextRenderingHint = "AntiAliasGridFit"

    # background circle
    $bgColor = if ($blue) { [System.Drawing.Color]::FromArgb(0, 120, 215) } else { [System.Drawing.Color]::FromArgb(243, 121, 52) }
    $bBrush = New-Object System.Drawing.SolidBrush($bgColor)
    $g.FillEllipse($bBrush, 0, 0, 15, 15)
    $bBrush.Dispose()

    # ♻ symbol in white
    $fBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $font = New-Object System.Drawing.Font("Segoe UI Symbol", 10, [System.Drawing.FontStyle]::Bold)
    $g.DrawString([char]0x267B, $font, $fBrush, 0.5, 0)
    $font.Dispose(); $fBrush.Dispose(); $g.Dispose()

    [System.Drawing.Icon]::FromHandle($img.GetHicon())
}

function Get-ProxyPid {
    $connections = netstat -ano 2>$null | Select-String ":${port}\s"
    foreach ($conn in $connections) {
        $parts = $conn -split '\s+'
        if ($parts.Count -ge 5 -and $parts[-1] -match '^\d+$') {
            $found = [int]$parts[-1]
            if ($found -gt 0) {
                try { $proc = Get-Process -Id $found -ErrorAction Stop; if ($proc.ProcessName -eq 'node') { return $found } } catch {}
                return $found
            }
        }
    }
    return $null
}

function Test-ProxyRunning { return (Get-ProxyPid) -ne $null }

function Update-ProxyStatus {
    $running = Test-ProxyRunning
    if ($running) {
        $trayIcon.Icon = Get-TrayIcon $true
        $trayIcon.Text = "DeepSeek Switcher`nStatus: DeepSeek ACTIVE (blue)"
    } else {
        $trayIcon.Icon = Get-TrayIcon $false
        $trayIcon.Text = "DeepSeek Switcher`nStatus: Claude ACTIVE (orange)"
    }
}

function Write-Log($msg) {
    $logPath = "$scriptDir\deepseek-tray.log"
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg"
    Add-Content -Path $logPath -Value $line
    Write-Host $line
}

# -- actions --
function Start-Proxy {
    $key = $keyBox.Text.Trim()
    if (-not $key) {
        $statusLabel.Text = "Enter a DeepSeek API key first!"
        $statusLabel.ForeColor = "Red"
        return
    }
    if (Test-ProxyRunning) {
        $statusLabel.Text = "Proxy already running"
        $statusLabel.ForeColor = "Blue"
        return
    }
    # save key
    [System.IO.File]::WriteAllText($keyFile, $key)

    # kill anything on port 4000
    $existing = Get-ProxyPid
    if ($existing) { taskkill /f /pid $existing >$null 2>&1; Start-Sleep -Milliseconds 300 }

    # start proxy via hidden cmd window
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "cmd.exe"
    $psi.Arguments = "/c set DEEPSEEK_API_KEY=$key && node `"$proxyJs`""
    $psi.WindowStyle = "Hidden"
    $psi.CreateNoWindow = $true
    $psi.UseShellExecute = $false
    $p = [System.Diagnostics.Process]::Start($psi)
    Start-Sleep -Seconds 2

    if (Test-ProxyRunning) {
        # set env var
        [Environment]::SetEnvironmentVariable("ANTHROPIC_BASE_URL", "http://localhost:4000", "User")
        Write-Log "Proxy started, ANTHROPIC_BASE_URL set"

        $statusLabel.Text = "DeepSeek ACTIVE (proxy on port $port)"
        $statusLabel.ForeColor = "Blue"
        $onBtn.Enabled = $false
        $offBtn.Enabled = $true
        $form.BackColor = [System.Drawing.Color]::FromArgb(230, 245, 255)
        $panel.BackColor = [System.Drawing.Color]::FromArgb(230, 245, 255)
        Update-ProxyStatus
        Update-Stats
    } else {
        $statusLabel.Text = "Failed to start proxy!"
        $statusLabel.ForeColor = "Red"
    }
}

function Stop-Proxy {
    $foundPid = Get-ProxyPid
    if ($foundPid) {
        taskkill /f /pid $foundPid >$null 2>&1
        Start-Sleep -Milliseconds 300
    }
    # remove env var
    [Environment]::SetEnvironmentVariable("ANTHROPIC_BASE_URL", $null, "User")
    try { Remove-ItemProperty -Path "HKCU:\Environment" -Name "ANTHROPIC_BASE_URL" -ErrorAction SilentlyContinue } catch {}

    Write-Log "Proxy stopped, ANTHROPIC_BASE_URL cleared"
    $statusLabel.Text = "Claude ACTIVE (Anthropic direct)"
    $statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(200, 80, 0)
    $onBtn.Enabled = $true
    $offBtn.Enabled = $false
    $form.BackColor = [System.Drawing.Color]::FromArgb(255, 242, 230)
    $panel.BackColor = [System.Drawing.Color]::FromArgb(255, 242, 230)
    Update-ProxyStatus
    Update-Stats
}

# -- build form --
$form = New-Object System.Windows.Forms.Form
$form.Text = "DeepSeek Switcher"
$form.Size = New-Object System.Drawing.Size(380, 380)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(255, 242, 230)  # warm orange tint
$form.Icon = Get-TrayIcon $false
$form.TopMost = $true

# header
$header = New-Object System.Windows.Forms.Label
$header.Text = "DeepSeek Switcher for Claude Code"
$header.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$header.Size = New-Object System.Drawing.Size(350, 24)
$header.Location = New-Object System.Drawing.Point(15, 12)
$header.TextAlign = "MiddleCenter"
$form.Controls.Add($header)

# subtitle
$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = "Switch between Claude (Anthropic) and DeepSeek"
$subtitle.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$subtitle.Size = New-Object System.Drawing.Size(350, 18)
$subtitle.Location = New-Object System.Drawing.Point(15, 36)
$subtitle.TextAlign = "MiddleCenter"
$subtitle.ForeColor = "Gray"
$form.Controls.Add($subtitle)

# panel to hold the rest
$panel = New-Object System.Windows.Forms.Panel
$panel.Size = New-Object System.Drawing.Size(350, 240)
$panel.Location = New-Object System.Drawing.Point(15, 60)
$panel.BackColor = [System.Drawing.Color]::FromArgb(255, 242, 230)
$form.Controls.Add($panel)

# API key label
$keyLabel = New-Object System.Windows.Forms.Label
$keyLabel.Text = "DeepSeek API Key:"
$keyLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$keyLabel.Size = New-Object System.Drawing.Size(340, 18)
$keyLabel.Location = New-Object System.Drawing.Point(0, 5)
$panel.Controls.Add($keyLabel)

# API key box
$keyBox = New-Object System.Windows.Forms.TextBox
$keyBox.Size = New-Object System.Drawing.Size(340, 22)
$keyBox.Location = New-Object System.Drawing.Point(0, 24)
$keyBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$keyBox.PasswordChar = '*'
# load saved key
if (Test-Path $keyFile) { $keyBox.Text = [System.IO.File]::ReadAllText($keyFile).Trim() }
$panel.Controls.Add($keyBox)

# show/hide key toggle
$showKey = New-Object System.Windows.Forms.CheckBox
$showKey.Text = "Show key"
$showKey.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$showKey.Size = New-Object System.Drawing.Size(80, 18)
$showKey.Location = New-Object System.Drawing.Point(0, 50)
$showKey.Add_CheckedChanged({ $keyBox.PasswordChar = if ($showKey.Checked) { 0 } else { '*' } })
$panel.Controls.Add($showKey)

# buttons
$onBtn = New-Object System.Windows.Forms.Button
$onBtn.Text = "  Use DeepSeek"
$onBtn.Size = New-Object System.Drawing.Size(155, 50)
$onBtn.Location = New-Object System.Drawing.Point(0, 78)
$onBtn.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$onBtn.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$onBtn.ForeColor = "White"
$onBtn.FlatStyle = "Flat"
$onBtn.FlatAppearance.BorderSize = 0
$onBtn.Add_Click({ Start-Proxy })
$panel.Controls.Add($onBtn)

$offBtn = New-Object System.Windows.Forms.Button
$offBtn.Text = "  Use Claude"
$offBtn.Size = New-Object System.Drawing.Size(155, 50)
$offBtn.Location = New-Object System.Drawing.Point(185, 78)
$offBtn.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$offBtn.BackColor = [System.Drawing.Color]::FromArgb(243, 121, 52)
$offBtn.ForeColor = "White"
$offBtn.FlatStyle = "Flat"
$offBtn.FlatAppearance.BorderSize = 0
$offBtn.Add_Click({ Stop-Proxy })
$panel.Controls.Add($offBtn)

# usage stats label
$usageLabel = New-Object System.Windows.Forms.Label
$usageLabel.Text = ""
$usageLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$usageLabel.ForeColor = "Gray"
$usageLabel.Size = New-Object System.Drawing.Size(340, 30)
$usageLabel.Location = New-Object System.Drawing.Point(0, 133)
$usageLabel.TextAlign = "MiddleCenter"
$panel.Controls.Add($usageLabel)

function Update-Stats {
    try {
        $resp = Invoke-RestMethod -Uri $statsUrl -Method GET -TimeoutSec 2 -ErrorAction Stop
        $inTok  = [math]::Round($resp.deepseek.input / 1000, 1)
        $outTok = [math]::Round($resp.deepseek.output / 1000, 1)
        $reqs   = $resp.deepseek.requests
        $usageLabel.Text = "DeepSeek: $inTok`K in / $outTok`K out  ($reqs requests)"
    } catch {
        $usageLabel.Text = ""
    }
}

# status
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = "Checking status..."
$statusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$statusLabel.Size = New-Object System.Drawing.Size(340, 22)
$statusLabel.Location = New-Object System.Drawing.Point(0, 163)
$statusLabel.TextAlign = "MiddleCenter"
$panel.Controls.Add($statusLabel)

# info line 1
$info1 = New-Object System.Windows.Forms.Label
$info1.Text = "Proxy runs on localhost:$port"
$info1.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$info1.ForeColor = "Gray"
$info1.Size = New-Object System.Drawing.Size(340, 16)
$info1.Location = New-Object System.Drawing.Point(0, 190)
$info1.TextAlign = "MiddleCenter"
$panel.Controls.Add($info1)

# info line 2
$info2 = New-Object System.Windows.Forms.Label
$info2.Text = "New terminals get ANTHROPIC_BASE_URL"
$info2.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$info2.ForeColor = "Gray"
$info2.Size = New-Object System.Drawing.Size(340, 16)
$info2.Location = New-Object System.Drawing.Point(0, 206)
$info2.TextAlign = "MiddleCenter"
$panel.Controls.Add($info2)

# -- system tray icon --
$trayIcon = New-Object System.Windows.Forms.NotifyIcon
$trayIcon.Icon = Get-TrayIcon $false
$trayIcon.Text = "DeepSeek Switcher`nStatus: Claude ACTIVE (orange)"
$trayIcon.Visible = $true

# tray context menu
$trayMenu = New-Object System.Windows.Forms.ContextMenuStrip

$showItem = New-Object System.Windows.Forms.ToolStripMenuItem
$showItem.Text = "&Show Window"
$showItem.Add_Click({ $form.Show(); $form.WindowState = "Normal"; $form.Activate() })
$trayMenu.Items.Add($showItem)

$trayMenu.Items.Add("-")  # separator

$trayOnItem = New-Object System.Windows.Forms.ToolStripMenuItem
$trayOnItem.Text = "Use &DeepSeek"
$trayOnItem.Add_Click({ Start-Proxy })
$trayMenu.Items.Add($trayOnItem)

$trayOffItem = New-Object System.Windows.Forms.ToolStripMenuItem
$trayOffItem.Text = "Use &Claude"
$trayOffItem.Add_Click({ Stop-Proxy })
$trayMenu.Items.Add($trayOffItem)

$trayMenu.Items.Add("-")

$resetItem = New-Object System.Windows.Forms.ToolStripMenuItem
$resetItem.Text = "&Reset Stats"
$resetItem.Add_Click({
    try { Invoke-RestMethod -Uri "http://localhost:4000/v1/stats/reset" -Method GET -TimeoutSec 2 -ErrorAction Stop | Out-Null } catch {}
    Update-Stats
})
$trayMenu.Items.Add($resetItem)

$trayMenu.Items.Add("-")

$exitItem = New-Object System.Windows.Forms.ToolStripMenuItem
$exitItem.Text = "E&xit"
$exitItem.Add_Click({
    $trayIcon.Visible = $false
    [System.Windows.Forms.Application]::Exit()
    [System.Environment]::Exit(0)
})
$trayMenu.Items.Add($exitItem)

$trayIcon.ContextMenuStrip = $trayMenu

# double-click tray to show window
$trayIcon.Add_MouseDoubleClick({
    $form.Show()
    $form.WindowState = "Normal"
    $form.Activate()
})

# minimize to tray
$form.Add_Resize({
    if ($form.WindowState -eq "Minimized") {
        $form.Hide()
    }
})

# -- init --
$running = Test-ProxyRunning
if ($running) {
    $statusLabel.Text = "DeepSeek ACTIVE (proxy running)"
    $statusLabel.ForeColor = "Blue"
    $onBtn.Enabled = $false
    $offBtn.Enabled = $true
    $form.BackColor = [System.Drawing.Color]::FromArgb(230, 245, 255)
    $panel.BackColor = [System.Drawing.Color]::FromArgb(230, 245, 255)
} else {
    $statusLabel.Text = "Claude ACTIVE (Anthropic direct)"
    $statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(200, 80, 0)
    $onBtn.Enabled = $true
    $offBtn.Enabled = $false
}
Update-ProxyStatus
Update-Stats

# -- run --
$form.Add_Shown({ $form.Activate() })
$form.TopMost = $false
[System.Windows.Forms.Application]::Run($form)
