# ============================================================
#  KeyEngraver - fullscreen kiosk front-end for LightBurn
#  Operator types a key number (digits and letters), presses ENGRAVE. LightBurn stays hidden.
#  Talks to LightBurn via its UDP command interface (port 19840).
# ============================================================

# ------------------------- CONFIG ---------------------------
# PowerShell 2.0 (stock Windows 7) has no $PSScriptRoot in scripts - derive it
if (-not $PSScriptRoot) { $PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }
$TemplatePath   = Join-Path $PSScriptRoot 'template.lbrn2'   # your LightBurn template containing the text %KEYNUM%
$OutputPath     = Join-Path $PSScriptRoot 'current.lbrn2'    # generated file sent to LightBurn each engrave
$Placeholder    = '%KEYNUM%'   # the literal text in your template that gets replaced
$LightBurnHost  = '127.0.0.1'  # PC running LightBurn (this PC)
$UdpSendPort    = 19840        # LightBurn command port
$UdpReplyPort   = 19841        # LightBurn reply port
$MaxChars       = 8            # max characters (digits + letters) operators can type
$ZeroPadTo      = 0            # e.g. 4 turns "37" into "0037"; 0 = disabled
$EngraveSeconds = 8            # lockout time while the job runs (tune to your actual cycle time)
$LoadDelayMs    = 800          # wait after FORCELOAD before START so LightBurn can render the file
$ReplyTimeoutMs = 2000         # how long to wait for LightBurn to answer PING / START
$LoadTimeoutMs  = 15000        # how long to wait for LightBurn to answer FORCELOAD (slow PCs take a while)
$Fullscreen     = $false       # $true = borderless fullscreen kiosk, $false = normal window (for troubleshooting)
$LogPath        = Join-Path $PSScriptRoot 'engraver.log'
# Exit the kiosk with Ctrl+Shift+X (operators won't find it)
# ------------------------------------------------------------

function Write-Log([string]$msg) {
    try { Add-Content -Path $LogPath -Value ("{0:yyyy-MM-dd HH:mm:ss.fff}  {1}" -f (Get-Date), $msg) } catch {}
}

Write-Log ("=== Kiosk starting.  PowerShell {0}  OS {1}  Folder {2}" -f $PSVersionTable.PSVersion, [Environment]::OSVersion.VersionString, $PSScriptRoot)

# every PowerShell error also goes to engraver.log so it can be read after the console is gone
trap {
    Write-Log ("ERROR: {0}  (line {1})" -f $_.Exception.Message, $_.InvocationInfo.ScriptLineNumber)
    continue
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# ----------------------- UDP helpers ------------------------
$script:UdpOut = New-Object System.Net.Sockets.UdpClient
$script:UdpIn  = $null
try {
    $script:UdpIn = New-Object System.Net.Sockets.UdpClient $UdpReplyPort
} catch {
    # port already taken (another kiosk instance?) - we can still send blind
    Write-Log "WARNING: could not listen on UDP $UdpReplyPort - $($_.Exception.Message). Replies will not be received."
}

function Clear-StaleReplies {
    # throw away any reply that arrived late from an earlier command, so it can't be
    # mistaken for the answer to the command we're about to send
    if (-not $script:UdpIn) { return }
    while ($script:UdpIn.Available -gt 0) {
        try {
            $ep = New-Object System.Net.IPEndPoint ([System.Net.IPAddress]::Any, 0)
            $old = [System.Text.Encoding]::ASCII.GetString($script:UdpIn.Receive([ref]$ep))
            Write-Log "Discarded stale reply '$old'"
        } catch { break }
    }
}

function Send-LB {
    param([string]$Command, [switch]$WaitReply, [int]$TimeoutMs = $ReplyTimeoutMs)
    Clear-StaleReplies
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($Command)
    [void]$script:UdpOut.Send($bytes, $bytes.Length, $LightBurnHost, $UdpSendPort)
    if ($WaitReply -and $script:UdpIn) {
        try {
            $script:UdpIn.Client.ReceiveTimeout = $TimeoutMs
            $ep = New-Object System.Net.IPEndPoint ([System.Net.IPAddress]::Any, 0)
            $reply = [System.Text.Encoding]::ASCII.GetString($script:UdpIn.Receive([ref]$ep))
            Write-Log "SENT '$Command' -> reply '$reply'"
            return $reply
        } catch {
            Write-Log "SENT '$Command' -> NO REPLY after ${TimeoutMs}ms ($($_.Exception.Message))"
            return $null
        }
    }
    Write-Log "SENT '$Command' (no wait)"
    return $null
}

# -------------------------- UI ------------------------------
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Key Engraver" Background="#FF101418" Width="1000" Height="800"
        WindowStartupLocation="CenterScreen">
  <Window.Resources>
    <Style TargetType="Button" x:Key="PadBtn">
      <Setter Property="FontSize" Value="34"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="Foreground" Value="#FFEAEAEA"/>
      <Setter Property="Background" Value="#FF232B33"/>
      <Setter Property="BorderBrush" Value="#FF3A444E"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Margin" Value="4"/>
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="Cursor" Value="Hand"/>
    </Style>
  </Window.Resources>
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="90"/>
      <RowDefinition Height="200"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="150"/>
      <RowDefinition Height="50"/>
    </Grid.RowDefinitions>

    <!-- status bar -->
    <Border x:Name="StatusBar" Grid.Row="0" Background="#FF1E7A3C">
      <TextBlock x:Name="StatusText" Text="READY" Foreground="White" FontSize="46"
                 FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>

    <!-- number display -->
    <Border Grid.Row="1" Background="#FF0A0D10" Margin="30,20,30,10" CornerRadius="10"
            BorderBrush="#FF3A444E" BorderThickness="2">
      <TextBlock x:Name="NumDisplay" Text="" Foreground="#FF7FE07F" FontSize="120"
                 FontFamily="Consolas" FontWeight="Bold"
                 HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>

    <!-- keyboard: digit row + QWERTY letters (rows generated below) -->
    <!-- 20 half-width columns so the letter rows can stagger like a real keyboard -->
    <Grid Grid.Row="2" Margin="30,10,30,10">
      <Grid.RowDefinitions>
        <RowDefinition/><RowDefinition/><RowDefinition/><RowDefinition/>
      </Grid.RowDefinitions>
      <Grid.ColumnDefinitions>
        <ColumnDefinition/><ColumnDefinition/><ColumnDefinition/><ColumnDefinition/><ColumnDefinition/>
        <ColumnDefinition/><ColumnDefinition/><ColumnDefinition/><ColumnDefinition/><ColumnDefinition/>
        <ColumnDefinition/><ColumnDefinition/><ColumnDefinition/><ColumnDefinition/><ColumnDefinition/>
        <ColumnDefinition/><ColumnDefinition/><ColumnDefinition/><ColumnDefinition/><ColumnDefinition/>
      </Grid.ColumnDefinitions>
%KEYS%
      <Button x:Name="BClr" Content="CLR" Style="{StaticResource PadBtn}" Grid.Row="3" Grid.Column="0" Grid.ColumnSpan="3" Background="#FF5A2B2B"/>
      <Button x:Name="BBack" Content="&#x232B;" Style="{StaticResource PadBtn}" Grid.Row="3" Grid.Column="17" Grid.ColumnSpan="3" Background="#FF4A4A2B"/>
    </Grid>

    <!-- engrave button -->
    <Button x:Name="BGo" Grid.Row="3" Margin="120,10,120,15" Focusable="False" Cursor="Hand"
            Background="#FF1E7A3C" BorderBrush="#FF2FA85A" BorderThickness="2">
      <TextBlock Text="ENGRAVE" Foreground="White" FontSize="60" FontWeight="Bold"/>
    </Button>

    <!-- footer -->
    <TextBlock x:Name="Footer" Grid.Row="4" Text="Keys engraved: 0" Foreground="#FF667380"
               FontSize="20" HorizontalAlignment="Center" VerticalAlignment="Center"/>
  </Grid>
</Window>
'@

# build the key rows: each key is 2 of the 20 grid columns wide, rows are centred so
# the letter rows stagger like a real keyboard. Buttons are named B0..B9 and BA..BZ.
$KeyRows = @('1234567890', 'QWERTYUIOP', 'ASDFGHJKL', 'ZXCVBNM')
$keysXaml = ''
for ($r = 0; $r -lt $KeyRows.Count; $r++) {
    $row = $KeyRows[$r]
    $offset = (20 - 2 * $row.Length) / 2
    for ($c = 0; $c -lt $row.Length; $c++) {
        $ch = $row[$c]
        $keysXaml += ('      <Button x:Name="B{0}" Content="{0}" Style="{{StaticResource PadBtn}}" Grid.Row="{1}" Grid.Column="{2}" Grid.ColumnSpan="2"/>' -f $ch, $r, ($offset + 2 * $c)) + "`r`n"
    }
}
$xaml = $xaml.Replace('%KEYS%', $keysXaml)

$window = [Windows.Markup.XamlReader]::Parse($xaml)
if ($Fullscreen) {
    $window.WindowStyle = [Windows.WindowStyle]::None
    $window.ResizeMode  = [Windows.ResizeMode]::NoResize
    $window.Topmost     = $true
    $window.WindowState = [Windows.WindowState]::Maximized
}
$StatusBar  = $window.FindName('StatusBar')
$StatusText = $window.FindName('StatusText')
$NumDisplay = $window.FindName('NumDisplay')
$Footer     = $window.FindName('Footer')
$BGo        = $window.FindName('BGo')

$script:Entry = ''
$script:Busy = $false
$script:Count = 0
$script:FreshAfterEngrave = $false
$script:Connected = $false

$ColGreen  = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0x1E,0x7A,0x3C))
$ColOrange = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0xB5,0x6A,0x1E))
$ColRed    = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0x8E,0x24,0x24))

function Set-Status([string]$text, $brush) {
    $StatusText.Text = $text
    $StatusBar.Background = $brush
    # force the UI to repaint now - the engrave path blocks the UI thread while it waits on LightBurn
    try { $window.Dispatcher.Invoke([Windows.Threading.DispatcherPriority]::Render, [Action]{}) } catch {}
}

function Update-Display { $NumDisplay.Text = $script:Entry }

function Add-Digit([string]$d) {
    if ($script:Busy) { return }
    if ($script:FreshAfterEngrave) { $script:Entry = ''; $script:FreshAfterEngrave = $false }
    if ($script:Entry.Length -lt $MaxChars) { $script:Entry += $d; Update-Display }
}

# lockout timer - re-enables input after the engrave cycle
$LockTimer = New-Object Windows.Threading.DispatcherTimer
$LockTimer.Interval = [TimeSpan]::FromSeconds($EngraveSeconds)
$LockTimer.Add_Tick({
    $LockTimer.Stop()
    $script:Busy = $false
    $script:Count++
    $Footer.Text = "Keys engraved: $($script:Count)"
    Set-Status 'READY' $ColGreen
})

function Start-Engrave {
    if ($script:Busy) { return }
    if (-not $script:Connected) {
        # LightBurn never answered, or dropped off - re-check right now
        if ($null -ne (Send-LB 'PING' -WaitReply)) {
            $script:Connected = $true
        } else {
            Set-Status 'WAITING FOR LIGHTBURN - NOT SENT' $ColRed
            Write-Log 'Engrave blocked: LightBurn not responding to PING'
            return
        }
    }
    if ([string]::IsNullOrEmpty($script:Entry)) {
        Set-Status 'TYPE A KEY NUMBER FIRST' $ColOrange
        return
    }
    if (-not (Test-Path $TemplatePath)) {
        Set-Status 'TEMPLATE.LBRN2 MISSING' $ColRed
        Write-Log "Template not found at $TemplatePath"
        return
    }

    $num = $script:Entry
    if ($ZeroPadTo -gt 0) { $num = $num.PadLeft($ZeroPadTo, '0') }

    # build the job file from the template
    $content = [System.IO.File]::ReadAllText($TemplatePath)
    if ($content.IndexOf($Placeholder) -lt 0) {
        Set-Status "TEMPLATE HAS NO $Placeholder" $ColRed
        return
    }
    $content = $content.Replace($Placeholder, $num)
    [System.IO.File]::WriteAllText($OutputPath, $content)

    $script:Busy = $true
    $script:FreshAfterEngrave = $true
    Set-Status "SENDING  $num" $ColOrange
    $NumDisplay.Text = $num
    Write-Log "=== Engrave requested: $num ==="

    # hand the file to LightBurn - require a confirmed load before firing
    $reply = Send-LB "FORCELOAD:$OutputPath" -WaitReply -TimeoutMs $LoadTimeoutMs
    if ($null -eq $reply) {
        $script:Busy = $false
        $script:Connected = $false
        Set-Status 'LIGHTBURN NOT RESPONDING - JOB NOT SENT' $ColRed
        Write-Log "FORCELOAD got no reply within ${LoadTimeoutMs}ms - job aborted, nothing fired. Check LightBurn for a popup dialog."
        return
    }

    Start-Sleep -Milliseconds $LoadDelayMs
    Set-Status "ENGRAVING  $num" $ColOrange
    [void](Send-LB 'START' -WaitReply)

    $LockTimer.Start()
}

# on-screen keyboard wiring (digits and letters)
foreach ($row in $KeyRows) {
    foreach ($ch in $row.ToCharArray()) {
        $btn = $window.FindName("B$ch")
        $d = "$ch"
        $btn.Add_Click({ Add-Digit $d }.GetNewClosure())
    }
}
$window.FindName('BClr').Add_Click({ if (-not $script:Busy) { $script:Entry = ''; Update-Display } })
$window.FindName('BBack').Add_Click({
    if (-not $script:Busy -and $script:Entry.Length -gt 0) {
        $script:Entry = $script:Entry.Substring(0, $script:Entry.Length - 1); Update-Display
    }
})
$BGo.Add_Click({ Start-Engrave })

# physical keyboard / numpad
$window.Add_KeyDown({
    param($s, $e)
    $k = $e.Key.ToString()
    $mods = [Windows.Input.Keyboard]::Modifiers
    # hidden exit: Ctrl+Shift+X
    if ($k -eq 'X' -and $mods -eq ([Windows.Input.ModifierKeys]::Control -bor [Windows.Input.ModifierKeys]::Shift)) {
        $window.Close(); return
    }
    if ($k -match '^(D|NumPad)([0-9])$') { Add-Digit $Matches[2]; return }
    # letters always enter as capitals regardless of Caps Lock / Shift; ignore Ctrl/Alt chords
    if ($k -match '^[A-Z]$' -and -not ($mods -band ([Windows.Input.ModifierKeys]::Control -bor [Windows.Input.ModifierKeys]::Alt))) {
        Add-Digit $k; return
    }
    switch ($k) {
        'Return' { Start-Engrave }
        'Enter'  { Start-Engrave }
        'Back'   {
            if (-not $script:Busy -and $script:Entry.Length -gt 0) {
                $script:Entry = $script:Entry.Substring(0, $script:Entry.Length - 1); Update-Display
            }
        }
        'Escape' { if (-not $script:Busy) { $script:Entry = ''; Update-Display } }
    }
})

# startup: check LightBurn is alive
$pingTimer = New-Object Windows.Threading.DispatcherTimer
$pingTimer.Interval = [TimeSpan]::FromSeconds(3)
$pingTimer.Add_Tick({
    if ($null -ne (Send-LB 'PING' -WaitReply)) {
        $pingTimer.Stop()
        $script:Connected = $true
        Set-Status 'READY' $ColGreen
    }
})
$window.Add_ContentRendered({
    $reply = Send-LB 'PING' -WaitReply
    if ($null -eq $reply) {
        Set-Status 'WAITING FOR LIGHTBURN...' $ColOrange
        $pingTimer.Start()   # retry every 3s until it answers
    } else {
        $script:Connected = $true
        Set-Status 'READY' $ColGreen
    }
})

[void]$window.ShowDialog()
if ($script:UdpIn) { $script:UdpIn.Close() }
$script:UdpOut.Close()
Write-Log '=== Kiosk closed ==='
