# ============================================================
#  KeyEngraver - fullscreen kiosk front-end for LightBurn
#  Operator types a number, presses ENGRAVE. LightBurn stays hidden.
#  Talks to LightBurn via its UDP command interface (port 19840).
# ============================================================

# ------------------------- CONFIG ---------------------------
$TemplatePath   = Join-Path $PSScriptRoot 'template.lbrn2'   # your LightBurn template containing the text %KEYNUM%
$OutputPath     = Join-Path $PSScriptRoot 'current.lbrn2'    # generated file sent to LightBurn each engrave
$Placeholder    = '%KEYNUM%'   # the literal text in your template that gets replaced
$LightBurnHost  = '127.0.0.1'  # PC running LightBurn (this PC)
$UdpSendPort    = 19840        # LightBurn command port
$UdpReplyPort   = 19841        # LightBurn reply port
$MaxDigits      = 8            # max digits operators can type
$ZeroPadTo      = 0            # e.g. 4 turns "37" into "0037"; 0 = disabled
$EngraveSeconds = 8            # lockout time while the job runs (tune to your actual cycle time)
$LoadDelayMs    = 800          # wait after FORCELOAD before START so LightBurn can render the file
$LogPath        = Join-Path $PSScriptRoot 'engraver.log'
# Exit the kiosk with Ctrl+Shift+X (operators won't find it)
# ------------------------------------------------------------

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# ----------------------- UDP helpers ------------------------
$script:UdpOut = New-Object System.Net.Sockets.UdpClient
$script:UdpIn  = $null
try {
    $script:UdpIn = New-Object System.Net.Sockets.UdpClient $UdpReplyPort
    $script:UdpIn.Client.ReceiveTimeout = 2000
} catch {
    # port already taken (another kiosk instance?) - we can still send blind
}

function Write-Log([string]$msg) {
    try { Add-Content -Path $LogPath -Value ("{0:yyyy-MM-dd HH:mm:ss.fff}  {1}" -f (Get-Date), $msg) } catch {}
}

function Send-LB {
    param([string]$Command, [switch]$WaitReply)
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($Command)
    [void]$script:UdpOut.Send($bytes, $bytes.Length, $LightBurnHost, $UdpSendPort)
    if ($WaitReply -and $script:UdpIn) {
        try {
            $ep = New-Object System.Net.IPEndPoint ([System.Net.IPAddress]::Any, 0)
            $reply = [System.Text.Encoding]::ASCII.GetString($script:UdpIn.Receive([ref]$ep))
            Write-Log "SENT '$Command' -> reply '$reply'"
            return $reply
        } catch {
            Write-Log "SENT '$Command' -> NO REPLY (timeout)"
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
        Title="Key Engraver" WindowStyle="None" WindowState="Maximized"
        Topmost="True" Background="#FF101418" ResizeMode="NoResize">
  <Window.Resources>
    <Style TargetType="Button" x:Key="PadBtn">
      <Setter Property="FontSize" Value="44"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="Foreground" Value="#FFEAEAEA"/>
      <Setter Property="Background" Value="#FF232B33"/>
      <Setter Property="BorderBrush" Value="#FF3A444E"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Margin" Value="8"/>
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

    <!-- keypad -->
    <Grid Grid.Row="2" Margin="220,10,220,10">
      <Grid.RowDefinitions>
        <RowDefinition/><RowDefinition/><RowDefinition/><RowDefinition/>
      </Grid.RowDefinitions>
      <Grid.ColumnDefinitions>
        <ColumnDefinition/><ColumnDefinition/><ColumnDefinition/>
      </Grid.ColumnDefinitions>
      <Button x:Name="B7" Content="7" Style="{StaticResource PadBtn}" Grid.Row="0" Grid.Column="0"/>
      <Button x:Name="B8" Content="8" Style="{StaticResource PadBtn}" Grid.Row="0" Grid.Column="1"/>
      <Button x:Name="B9" Content="9" Style="{StaticResource PadBtn}" Grid.Row="0" Grid.Column="2"/>
      <Button x:Name="B4" Content="4" Style="{StaticResource PadBtn}" Grid.Row="1" Grid.Column="0"/>
      <Button x:Name="B5" Content="5" Style="{StaticResource PadBtn}" Grid.Row="1" Grid.Column="1"/>
      <Button x:Name="B6" Content="6" Style="{StaticResource PadBtn}" Grid.Row="1" Grid.Column="2"/>
      <Button x:Name="B1" Content="1" Style="{StaticResource PadBtn}" Grid.Row="2" Grid.Column="0"/>
      <Button x:Name="B2" Content="2" Style="{StaticResource PadBtn}" Grid.Row="2" Grid.Column="1"/>
      <Button x:Name="B3" Content="3" Style="{StaticResource PadBtn}" Grid.Row="2" Grid.Column="2"/>
      <Button x:Name="BClr" Content="CLR" Style="{StaticResource PadBtn}" Grid.Row="3" Grid.Column="0" Background="#FF5A2B2B"/>
      <Button x:Name="B0" Content="0" Style="{StaticResource PadBtn}" Grid.Row="3" Grid.Column="1"/>
      <Button x:Name="BBack" Content="&#x232B;" Style="{StaticResource PadBtn}" Grid.Row="3" Grid.Column="2" Background="#FF4A4A2B"/>
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

$window = [Windows.Markup.XamlReader]::Parse($xaml)
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
}

function Update-Display { $NumDisplay.Text = $script:Entry }

function Add-Digit([string]$d) {
    if ($script:Busy) { return }
    if ($script:FreshAfterEngrave) { $script:Entry = ''; $script:FreshAfterEngrave = $false }
    if ($script:Entry.Length -lt $MaxDigits) { $script:Entry += $d; Update-Display }
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
        Set-Status 'TYPE A NUMBER FIRST' $ColOrange
        return
    }
    if (-not (Test-Path $TemplatePath)) {
        Set-Status 'TEMPLATE.LBRN2 MISSING' $ColRed
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
    $reply = Send-LB "FORCELOAD:$OutputPath" -WaitReply
    if ($null -eq $reply) { $reply = Send-LB "FORCELOAD:$OutputPath" -WaitReply }  # one retry
    if ($null -eq $reply) {
        $script:Busy = $false
        $script:Connected = $false
        Set-Status 'LIGHTBURN NOT RESPONDING - JOB NOT SENT' $ColRed
        Write-Log 'FORCELOAD got no reply - job aborted, nothing fired'
        return
    }

    Start-Sleep -Milliseconds $LoadDelayMs
    Set-Status "ENGRAVING  $num" $ColOrange
    [void](Send-LB 'START' -WaitReply)

    $LockTimer.Start()
}

# on-screen keypad wiring
foreach ($i in 0..9) {
    $btn = $window.FindName("B$i")
    $d = "$i"
    $btn.Add_Click({ Add-Digit $this.Content }.GetNewClosure())
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
    if ($k -match '^(D|NumPad)([0-9])$') { Add-Digit $Matches[2]; return }
    switch ($k) {
        'Return' { Start-Engrave }
        'Enter'  { Start-Engrave }
        'Back'   {
            if (-not $script:Busy -and $script:Entry.Length -gt 0) {
                $script:Entry = $script:Entry.Substring(0, $script:Entry.Length - 1); Update-Display
            }
        }
        'Escape' { if (-not $script:Busy) { $script:Entry = ''; Update-Display } }
        'X' {
            if ([Windows.Input.Keyboard]::Modifiers -eq ([Windows.Input.ModifierKeys]::Control -bor [Windows.Input.ModifierKeys]::Shift)) {
                $window.Close()
            }
        }
    }
})

# startup: check LightBurn is alive
$window.Add_ContentRendered({
    $reply = Send-LB 'PING' -WaitReply
    if ($null -eq $reply) {
        Set-Status 'WAITING FOR LIGHTBURN...' $ColOrange
        # retry every 3s until it answers
        $pingTimer = New-Object Windows.Threading.DispatcherTimer
        $pingTimer.Interval = [TimeSpan]::FromSeconds(3)
        $pingTimer.Add_Tick({
            if ($null -ne (Send-LB 'PING' -WaitReply)) {
                $this.Stop()
                $script:Connected = $true
                Set-Status 'READY' $ColGreen
            }
        })
        $pingTimer.Start()
    } else {
        $script:Connected = $true
        Set-Status 'READY' $ColGreen
    }
})

[void]$window.ShowDialog()
if ($script:UdpIn) { $script:UdpIn.Close() }
$script:UdpOut.Close()
