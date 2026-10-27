param(
    [string]$ServerUrl = 'http://127.0.0.1:4096',
    [switch]$Demo,
    [switch]$SmokeTest,
    [string]$PreviewPath
)
$ErrorActionPreference = 'Stop'
try {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    . "$PSScriptRoot/src/State.ps1"
    $uri = [uri]$ServerUrl
    if (-not $uri.IsLoopback -or $uri.Scheme -notin 'http','https' -or $uri.UserInfo) {
        throw 'Use a loopback HTTP(S) URL without credentials, such as http://127.0.0.1:4096.'
    }
    if (-not $Demo) { Add-Type -Path "$PSScriptRoot/src/EventStream.cs" }
    $script:state = New-SpiderState
    $script:frame = 0
    $script:paused = $false
    $script:stream = $null
    $script:started = [datetime]::UtcNow
    $script:moods = @('idle','working','waiting','done','error','offline')
    $script:labels = @{ idle='READY'; working='WEAVING CODE'; waiting='NEEDS YOU'; done='ALL DONE'; error='SNAG IN THE WEB'; offline='OFFLINE' }
    $script:colors = @{ idle='#70F0C4'; working='#63D7FF'; waiting='#FFCD70'; done='#AEF789'; error='#FF8095'; offline='#8D9AAE' }
    [xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Webby - OpenCode Spider" Width="268" Height="252"
        WindowStyle="None" ResizeMode="NoResize" AllowsTransparency="True"
        Background="Transparent" Topmost="True" ShowInTaskbar="True">
  <Border CornerRadius="20" Background="#F2131A26" BorderBrush="#344454" BorderThickness="1" Padding="17,12">
    <Grid>
      <Grid.RowDefinitions><RowDefinition Height="26"/><RowDefinition Height="*"/><RowDefinition Height="28"/><RowDefinition Height="23"/></Grid.RowDefinitions>
      <TextBlock Text="WEBBY / OPENCODE" FontFamily="Consolas" FontSize="11" Foreground="#9CABC0" VerticalAlignment="Center"/>
      <Button x:Name="CloseButton" Content="&#x00D7;" HorizontalAlignment="Right" Width="24" Background="Transparent" Foreground="#9CABC0" BorderThickness="0" ToolTip="Close"/>
      <TextBlock x:Name="SpiderArt" Grid.Row="1" FontFamily="Consolas" FontSize="20" LineHeight="22" TextAlignment="Center" VerticalAlignment="Center" Foreground="#70F0C4"/>
      <TextBlock x:Name="MoodLabel" Grid.Row="2" FontFamily="Consolas" FontSize="13" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center"/>
      <TextBlock x:Name="HintLabel" Grid.Row="3" Text="drag to move / right-click" FontFamily="Consolas" FontSize="10" Foreground="#7F90A6" HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Grid>
  </Border>
</Window>
'@
    $reader = [Xml.XmlNodeReader]::new($xaml)
    $script:window = [Windows.Markup.XamlReader]::Load($reader)
    $script:art = $window.FindName('SpiderArt')
    $script:label = $window.FindName('MoodLabel')
    $script:hint = $window.FindName('HintLabel')
    $area = [Windows.SystemParameters]::WorkArea
    $window.Left = $area.Right - $window.Width - 24
    $window.Top = $area.Bottom - $window.Height - 24
    $window.FindName('CloseButton').Add_Click({ $window.Close() })
    $window.Add_MouseLeftButtonDown({ if ($_.ButtonState -eq 'Pressed') { $window.DragMove() } })
    $menu = [Windows.Controls.ContextMenu]::new()
    $pause = [Windows.Controls.MenuItem]::new()
    $pause.Header = 'Pause animation'; $pause.IsCheckable = $true
    $pause.Add_Click({ $script:paused = $this.IsChecked })
    [void]$menu.Items.Add($pause)
    $pin = [Windows.Controls.MenuItem]::new()
    $pin.Header = 'Always on top'; $pin.IsCheckable = $true; $pin.IsChecked = $true
    $pin.Add_Click({ $window.Topmost = $this.IsChecked })
    [void]$menu.Items.Add($pin)
    $exit = [Windows.Controls.MenuItem]::new(); $exit.Header = 'Close Webby'
    $exit.Add_Click({ $window.Close() }); [void]$menu.Items.Add($exit)
    $window.ContextMenu = $menu
    $window.Add_KeyDown({ if ($_.Key -eq 'Escape') { $window.Close() } })
    if (-not $Demo) {
        $user = $env:OPENCODE_SERVER_USERNAME
        if (-not $user) { $user = 'opencode' }
        $script:stream = [SpiderEventStream]::new($ServerUrl, $user, $env:OPENCODE_PASSWORD)
    }
    function Update-View {
        if ($stream) {
            $raw = ''
            $count = 0
            while ($count -lt 100 -and $stream.Events.TryDequeue([ref]$raw)) {
                try { Update-SpiderState $state (ConvertFrom-Json $raw) } catch { }
                $count++
            }
            $window.ToolTip = $stream.Status + "`n" + $ServerUrl + "`nObserves events after connection; never approves permissions."
        }
        $mood = Get-SpiderMood $state
        if ($Demo) { $mood = $moods[[int][math]::Floor((([datetime]::UtcNow - $started).TotalSeconds / 4)) % $moods.Count] }
        if (-not $paused) { $script:frame++ }
        $eyes = switch ($mood) { 'waiting' { '??' }; 'done' { '^^' }; 'error' { '!!' }; 'offline' { '--' }; default { if ($frame % 16 -eq 0) { '--' } else { 'oo' } } }
        $legs = if ($frame % 2 -eq 0 -and $mood -eq 'working') { @('  / /|  |\ \',' /_/ |__| \_\',' \ \ /  \ / /','  \_\|  |/_/') } else { @(' \ \ |  | / /','  \_\|__|/_/','  / /    \ \',' /_/      \_\') }
        $art.Text = "      |      `n      |      `n" + $legs[0] + "`n" + $legs[1] + "`n" + "    (" + $eyes + ")    `n" + $legs[2] + "`n" + $legs[3]
        $brush = [Windows.Media.BrushConverter]::new().ConvertFromString($colors[$mood])
        $art.Foreground = $brush; $label.Foreground = $brush
        $label.Text = $labels[$mood]
        if ($Demo) { $hint.Text = 'DEMO / right-click for options' }
        elseif ($mood -eq 'offline') { $hint.Text = 'start OpenCode / see README' }
        else { $hint.Text = 'drag to move / right-click' }
        if ($SmokeTest -and ([datetime]::UtcNow - $started).TotalSeconds -gt 2) { $window.Close() }
    }
    Update-View
    $timer = [Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [timespan]::FromMilliseconds(250)
    $timer.Add_Tick({ Update-View })
    $window.Add_Closed({ $timer.Stop(); if ($stream) { $stream.Dispose() } })
    if ($PreviewPath) {
        $visual = $window.Content
        $visual.Measure([Windows.Size]::new(268,252)); $visual.Arrange([Windows.Rect]::new(0,0,268,252)); $visual.UpdateLayout()
        $bitmap = [Windows.Media.Imaging.RenderTargetBitmap]::new(268,252,96,96,[Windows.Media.PixelFormats]::Pbgra32)
        $bitmap.Render($visual)
        $encoder = [Windows.Media.Imaging.PngBitmapEncoder]::new()
        $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
        $file = [IO.File]::Create($PreviewPath)
        try { $encoder.Save($file) } finally { $file.Dispose(); if ($stream) { $stream.Dispose() } }
    } else {
        $timer.Start()
        [void]$window.ShowDialog()
    }
} catch {
    if ($SmokeTest -or $PreviewPath) { throw }
    Add-Type -AssemblyName PresentationFramework
    [void][Windows.MessageBox]::Show($_.Exception.Message, 'Webby could not start')
    exit 1
}
