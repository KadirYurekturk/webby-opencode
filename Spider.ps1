param(
    [string]$ServerUrl, [string]$ServiceFile,
    [string]$ProjectDirectory = (Get-Location).Path,
    [switch]$Demo, [switch]$SmokeTest, [string]$PreviewPath
)
$ErrorActionPreference = 'Stop'
$script:stream = $null; $script:tray = $null; $script:mutex = $null
$script:ownsMutex = $false; $script:iconHandle = [IntPtr]::Zero
try {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing
    . "$PSScriptRoot/src/State.ps1"
    . "$PSScriptRoot/src/Desktop.ps1"
    . "$PSScriptRoot/src/Activity.ps1"
    Add-Type -Path "$PSScriptRoot/src/Native.cs"
    if (-not $Demo) { Add-Type -Path "$PSScriptRoot/src/EventStream.cs" }
    if (-not $ServiceFile) { $ServiceFile = Get-WebbyServiceFile }
    if ($ServerUrl) { $null = Get-WebbyEndpoint $ServerUrl $ServiceFile }
    if (-not (Test-Path -LiteralPath $ProjectDirectory -PathType Container)) { throw 'Project folder does not exist.' }
    $script:project = (Resolve-Path -LiteralPath $ProjectDirectory).Path
    $script:settingsPath = Join-Path $env:LOCALAPPDATA 'Webby/settings.json'
    $script:startupPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'Webby.lnk'
    $script:isolated = $SmokeTest -or [bool]$PreviewPath
    if (-not $isolated) {
        $script:mutex = [Threading.Mutex]::new($false, 'Local\Webby.Desktop')
        try { $script:ownsMutex = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $script:ownsMutex = $true }
        if (-not $ownsMutex) { return }
    }
    $script:state = New-SpiderState
    $script:activity = New-WebbyActivity
    $script:lastDemoActivity = [datetime]::MinValue
    $script:mode = 'hanging'; $script:paused = -not [Windows.SystemParameters]::ClientAreaAnimation
    $script:frame = 0; $script:dragging = $false; $script:moved = $false; $script:hovered = $false
    $script:lastMood = ''; $script:notice = ''; $script:noticeUntil = [datetime]::MinValue
    $script:changedAt = [datetime]::UtcNow; $script:started = [datetime]::UtcNow
    $script:lastDiscover = [datetime]::MinValue; $script:endpoint = $null; $script:uiFailure = $null
    $script:moods = @('idle','working','waiting','done','error','offline')
    $script:labels = @{idle='Ready when you are';working='Weaving code...';waiting='Permission needed';done='All done!';error='Something went wrong';offline='Click to open OpenCode'}
    $script:colors = @{idle='#91EACB';working='#80DFFF';waiting='#FFCE77';done='#B7F59A';error='#FF9BB0';offline='#B7C5D7'}
    [xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Webby" Width="240" Height="230"
        WindowStyle="None" ResizeMode="NoResize" AllowsTransparency="True" Background="{x:Null}"
        Topmost="True" ShowInTaskbar="False" ShowActivated="False">
  <Canvas x:Name="Scene" Background="{x:Null}">
    <Line x:Name="Silk" X1="120" Y1="0" X2="120" Y2="112" Stroke="#7791EACB" StrokeThickness="1" IsHitTestVisible="False"/>
    <Line x:Name="CastWeb" Stroke="#C591EACB" StrokeThickness="1" Visibility="Collapsed" IsHitTestVisible="False"/>
    <TextBlock x:Name="CaughtWord" Width="64" TextAlignment="Center" FontFamily="Consolas" FontSize="13"
               FontWeight="Bold" Foreground="#91EACB" Visibility="Collapsed" IsHitTestVisible="False"/>
    <Ellipse x:Name="WebKnot" Canvas.Left="115" Width="10" Height="10" Stroke="#B7F59A" StrokeThickness="2"
             Visibility="Collapsed" IsHitTestVisible="False"/>
    <Image x:Name="Spider" Canvas.Left="64" Canvas.Top="76" Width="112" Height="112" Stretch="Uniform"
           RenderTransformOrigin="0.5,0.15" Focusable="True" Cursor="Hand" RenderOptions.BitmapScalingMode="NearestNeighbor"
           AutomationProperties.Name="Webby. Open OpenCode. Drag to move; right-click for options.">
      <Image.RenderTransform><TransformGroup><RotateTransform/><TranslateTransform/></TransformGroup></Image.RenderTransform>
    </Image>
    <Border x:Name="Bubble" Canvas.Left="4" Canvas.Top="192" Width="232" Height="32" CornerRadius="10"
            Background="#F21A2230" BorderBrush="#455668" BorderThickness="1" Visibility="Collapsed" IsHitTestVisible="False">
      <TextBlock x:Name="Status" TextAlignment="Center" VerticalAlignment="Center" FontFamily="Segoe UI" FontSize="12" FontWeight="SemiBold" Foreground="#91EACB"/>
    </Border>
  </Canvas>
</Window>
'@
    $script:window = [Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($xaml))
    $script:scene = $window.FindName('Scene'); $script:spider = $window.FindName('Spider')
    $script:silk = $window.FindName('Silk'); $script:bubble = $window.FindName('Bubble'); $script:label = $window.FindName('Status')
    $script:castWeb = $window.FindName('CastWeb'); $script:caughtWord = $window.FindName('CaughtWord')
    $script:webKnot = $window.FindName('WebKnot')
    $spritePath = Join-Path $PSScriptRoot 'assets/webby.png'
    $bitmap = [Windows.Media.Imaging.BitmapImage]::new()
    $bitmap.BeginInit(); $bitmap.CacheOption = 'OnLoad'; $bitmap.UriSource = [uri]$spritePath; $bitmap.EndInit(); $bitmap.Freeze()
    $spider.Source = $bitmap
    $area = [Windows.SystemParameters]::WorkArea
    $window.Left = $area.Right - $window.Width - 24; $window.Top = $area.Top
    $script:scale = 1.0
    $window.Add_SourceInitialized({
        $source = [Windows.PresentationSource]::FromVisual($window)
        if ($source.CompositionTarget) { $script:scale = $source.CompositionTarget.TransformFromDevice.M11 }
    })
    function Save-Preferences {
        if ($isolated) { return }
        try { Write-WebbySettings $settingsPath @{Left=$window.Left;Top=$window.Top;Mode=$mode;Paused=$paused;Topmost=$window.Topmost;Project=$project} }
        catch { Write-WebbyLog 'Could not save preferences.' }
    }
    function Set-Notice([string]$Text) { $script:notice = $Text; $script:noticeUntil = [datetime]::UtcNow.AddSeconds(5) }
    function Set-Dock([string]$DockMode, $WorkArea) {
        $script:mode = $DockMode
        $window.Left = [math]::Max($WorkArea.Left,[math]::Min($window.Left,$WorkArea.Right - $window.Width))
        $window.Top = if ($mode -eq 'hanging') { $WorkArea.Top } else { $WorkArea.Bottom - $window.Height }
        $silk.Visibility = if ($mode -eq 'hanging') { 'Visible' } else { 'Collapsed' }
        [Windows.Controls.Canvas]::SetTop($spider, $(if ($mode -eq 'hanging') {76} else {112}))
        [Windows.Controls.Canvas]::SetTop($bubble, $(if ($mode -eq 'hanging') {192} else {72}))
    }
    function Get-CurrentArea {
        $screen = [Windows.Forms.Screen]::FromPoint([Drawing.Point]::new([int](($window.Left + 120)/$scale),[int](($window.Top + 115)/$scale)))
        $a = $screen.WorkingArea
        @{Left=$a.Left*$scale;Right=$a.Right*$scale;Top=$a.Top*$scale;Bottom=$a.Bottom*$scale;Height=$a.Height*$scale}
    }
    function Open-OpenCode {
        if ($isolated) { Set-Notice 'OpenCode action checked'; return }
        if ([WebbyNative]::FocusOpenCode()) { return }
        if (-not (Get-Command opencode -ErrorAction SilentlyContinue)) { Set-Notice 'Install OpenCode v2 first'; return }
        $launcher = Join-Path $PSScriptRoot 'src/Launch-OpenCode.ps1'
        # Arguments are data to a fixed script, never interpolated PowerShell code.
        $launchDirectory = if ($project.EndsWith('\')) { $project + '.' } else { $project }
        $args = '-NoProfile -NoExit -File "' + $launcher + '" -ProjectDirectory "' + $launchDirectory + '"'
        if ($ServerUrl) { $args += ' -ServerUrl "' + $ServerUrl + '"' }
        try { Start-Process powershell.exe -ArgumentList $args -WindowStyle Normal | Out-Null }
        catch { Set-Notice 'Could not open OpenCode'; Write-WebbyLog 'OpenCode launch failed.' }
    }
    if (-not $isolated -and (Test-Path $settingsPath)) {
        try {
            $saved = Get-Content $settingsPath -Raw | ConvertFrom-Json
            if ($saved.Mode -in 'hanging','perched') { $script:mode = $saved.Mode }
            if ($saved.Paused -is [bool]) { $script:paused = $saved.Paused -or -not [Windows.SystemParameters]::ClientAreaAnimation }
            if ($saved.Topmost -is [bool]) { $window.Topmost = $saved.Topmost }
            if (-not $PSBoundParameters.ContainsKey('ProjectDirectory') -and (Test-Path -LiteralPath $saved.Project -PathType Container)) { $script:project = $saved.Project }
            if ($null -ne $saved.Left -and $null -ne $saved.Top) { $window.Left = [double]$saved.Left; $window.Top = [double]$saved.Top }
        } catch { Write-WebbyLog 'Ignored invalid preferences.' }
    }
    Set-Dock $mode (Get-CurrentArea)
    $spider.Add_MouseEnter({ $script:hovered = $true }); $spider.Add_MouseLeave({ $script:hovered = $false })
    $spider.Add_MouseLeftButtonDown({
        $script:dragging = $true; $script:moved = $false; $script:dragStart = [Windows.Forms.Cursor]::Position
        $script:initialLeft = $window.Left; $script:initialTop = $window.Top
        [void]$spider.CaptureMouse(); $_.Handled = $true
    })
    $spider.Add_MouseMove({
        if (-not $dragging) { return }
        $cursor = [Windows.Forms.Cursor]::Position
        $dx = ($cursor.X - $dragStart.X)*$scale; $dy = ($cursor.Y - $dragStart.Y)*$scale
        if ([math]::Abs($dx) + [math]::Abs($dy) -gt 5) { $script:moved = $true }
        if ($moved) { $window.Left = $initialLeft + $dx; $window.Top = $initialTop + $dy }
    })
    $spider.Add_MouseLeftButtonUp({
        $script:dragging = $false; $spider.ReleaseMouseCapture()
        if ($moved) {
            $a = Get-CurrentArea; $dock = Get-WebbyDock $window.Left $window.Top $a $window.Width $window.Height
            Set-Dock $dock.Mode $a; Save-Preferences
        } else { Open-OpenCode }
        $_.Handled = $true
    })
    $spider.Add_LostMouseCapture({ $script:dragging = $false })
    $spider.Add_KeyDown({ if ($_.Key -in 'Enter','Space') { Open-OpenCode; $_.Handled = $true } })
    $script:tray = [Windows.Forms.NotifyIcon]::new()
    $iconSource = [Drawing.Bitmap]::new($spritePath)
    $iconBitmap = [Drawing.Bitmap]::new($iconSource,32,32); $script:iconHandle = $iconBitmap.GetHicon()
    $tray.Icon = [Drawing.Icon]::FromHandle($iconHandle); $iconBitmap.Dispose(); $iconSource.Dispose()
    $tray.Text = 'Webby - OpenCode companion'; $menu = [Windows.Forms.ContextMenuStrip]::new()
    function Add-MenuItem([string]$Text, [scriptblock]$Action) {
        $item = [Windows.Forms.ToolStripMenuItem]::new($Text); $item.Add_Click($Action)
        [void]$menu.Items.Add($item); return $item
    }
    $null = Add-MenuItem 'Open OpenCode' { Open-OpenCode }
    $null = Add-MenuItem 'Show / hide Webby' { if ($window.IsVisible) { $window.Hide() } else { $window.Show() } }
    $null = Add-MenuItem 'Choose project folder...' {
        $dialog = [Windows.Forms.FolderBrowserDialog]::new()
        $dialog.Description = 'Project to open when no OpenCode window is available'; $dialog.SelectedPath = $project
        if ($dialog.ShowDialog() -eq 'OK') { $script:project = $dialog.SelectedPath; Save-Preferences; Set-Notice 'Project folder saved' }
        $dialog.Dispose()
    }
    [void]$menu.Items.Add([Windows.Forms.ToolStripSeparator]::new())
    $null = Add-MenuItem 'Hang from top edge' { Set-Dock 'hanging' (Get-CurrentArea); Save-Preferences }
    $null = Add-MenuItem 'Perch above taskbar' { Set-Dock 'perched' (Get-CurrentArea); Save-Preferences }
    $pauseItem = Add-MenuItem 'Reduce motion' { $script:paused = -not $paused; $pauseItem.Checked = $paused; Save-Preferences }
    $pauseItem.Checked = $paused
    $pinItem = Add-MenuItem 'Always on top' { $window.Topmost = -not $window.Topmost; $pinItem.Checked = $window.Topmost; Save-Preferences }
    $pinItem.Checked = $window.Topmost
    $startupItem = Add-MenuItem 'Start with Windows' {
        try {
            if (Test-Path -LiteralPath $startupPath) { Remove-Item -LiteralPath $startupPath }
            else {
                $shell = New-Object -ComObject WScript.Shell; $shortcut = $shell.CreateShortcut($startupPath)
                $shortcut.TargetPath = (Join-Path $PSHOME 'powershell.exe')
                $shortcut.Arguments = '-NoProfile -STA -WindowStyle Hidden -File "' + (Join-Path $PSScriptRoot 'Spider.ps1') + '"'
                $shortcut.WorkingDirectory = $PSScriptRoot; $shortcut.WindowStyle = 7; $shortcut.Save()
            }
            $startupItem.Checked = Test-Path -LiteralPath $startupPath
        } catch { Set-Notice 'Could not change startup'; Write-WebbyLog 'Startup shortcut update failed.' }
    }
    $startupItem.Checked = Test-Path -LiteralPath $startupPath
    [void]$menu.Items.Add([Windows.Forms.ToolStripSeparator]::new())
    $null = Add-MenuItem 'Exit Webby' { $window.Close() }
    $tray.ContextMenuStrip = $menu; $tray.Add_DoubleClick({ $window.Show(); Open-OpenCode })
    $spider.Add_MouseRightButtonUp({ $menu.Show([Windows.Forms.Cursor]::Position); $_.Handled = $true })
    if (-not $isolated) { $tray.Visible = $true }
    function Update-Connection {
        if ($Demo -or $isolated) { return }
        if (([datetime]::UtcNow - $lastDiscover).TotalSeconds -lt 3) { return }
        $script:lastDiscover = [datetime]::UtcNow; $next = Get-WebbyEndpoint $ServerUrl $ServiceFile
        $different = ($null -eq $next) -ne ($null -eq $endpoint)
        if ($next -and $endpoint) { $different = $next.Url -ne $endpoint.Url -or $next.Password -ne $endpoint.Password -or $next.Username -ne $endpoint.Username }
        if ($different -or ($next -and -not $stream)) {
            if ($stream) { $stream.Dispose(); $script:stream = $null }
            Update-SpiderState $state ([pscustomobject]@{type='transport.disconnected';data=@{}})
            $script:endpoint = $next
            if ($next) { $script:stream = [SpiderEventStream]::new($next.Url,$next.Username,$next.Password) }
        }
    }
    function Update-View {
        Update-Connection
        if ($stream) {
            $raw = ''; $count = 0
            while ($count -lt 100 -and $stream.Events.TryDequeue([ref]$raw)) {
                try {
                    $event = ConvertFrom-Json $raw
                    Update-SpiderState $state $event
                    Add-WebbyActivity $activity $event
                } catch { }
                $count++
            }
        }
        $mood = Get-SpiderMood $state
        if ($Demo) { $mood = $moods[[int][math]::Floor((([datetime]::UtcNow - $started).TotalSeconds / 4)) % $moods.Count] }
        if ($Demo -and $mood -eq 'working' -and ([datetime]::UtcNow - $lastDemoActivity).TotalSeconds -ge 4) {
            $script:lastDemoActivity = [datetime]::UtcNow
            Add-WebbyActivity $activity ([pscustomobject]@{type='session.tool.input.started';data=@{sessionID='demo';name='read'}})
        }
        $activityFrame = Get-WebbyActivityFrame $activity $mood ($paused -or $dragging -or -not $window.IsVisible)
        Show-ActivityFrame $activityFrame
        $timer.Interval = [timespan]::FromMilliseconds($(if ($activityFrame) {50} else {100}))
        if ($lastMood -ne $mood) { $script:lastMood = $mood; $script:changedAt = [datetime]::UtcNow }
        $webKnot.Visibility = if ($mood -eq 'done' -and -not $paused -and ([datetime]::UtcNow - $changedAt).TotalSeconds -lt 2) { 'Visible' } else { 'Collapsed' }
        [Windows.Controls.Canvas]::SetTop($webKnot,([Windows.Controls.Canvas]::GetTop($spider) + 20))
        if (-not $paused) { $script:frame++ }
        $rotation = 0.0; $bob = 0.0
        if (-not $paused -and -not $dragging) {
            $speed = if ($mood -eq 'working') { 0.45 } else { 0.10 }
            $rotation = [math]::Sin($frame*$speed)*$(if ($mode -eq 'hanging') {4} else {1.5})
            if ($mood -in 'working','done') { $bob = -[math]::Abs([math]::Sin($frame*$speed))*4 }
        }
        $spider.RenderTransform.Children[0].Angle = $rotation; $spider.RenderTransform.Children[1].Y = $bob
        $spider.Opacity = if ($mood -eq 'offline') {0.65} else {1.0}
        $label.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString($colors[$mood])
        $label.Text = $labels[$mood]
        if ($Demo) { $label.Text = 'Demo: ' + $label.Text }
        $show = $hovered -or $mood -in 'waiting','done','error' -or (([datetime]::UtcNow - $changedAt).TotalSeconds -lt 5)
        if ([datetime]::UtcNow -lt $noticeUntil) { $label.Text = $notice; $show = $true }
        $bubble.Visibility = if ($show) {'Visible'} else {'Collapsed'}
        $tray.Text = ('Webby: ' + $labels[$mood])
        $spider.ToolTip = if ($stream) { $stream.Status + "`nClick: OpenCode | Drag: move | Right-click: options" } else { 'Click: OpenCode | Drag: move | Right-click: options' }
        if ($SmokeTest -and ([datetime]::UtcNow - $started).TotalSeconds -gt 2) {
            Show-ActivityFrame @{Word='search';Cast=1.0;Pull=0.4;Opacity=1.0}
            if ($caughtWord.Text -ne 'search' -or $castWeb.Visibility -ne 'Visible') { throw 'Word capture layout failed' }
            if ($PreviewPath) { Save-Preview $PreviewPath }
            Show-ActivityFrame $null
            if ($caughtWord.Visibility -ne 'Collapsed') { throw 'Word capture cleanup failed' }
            Set-Dock 'perched' (Get-CurrentArea)
            if ($silk.Visibility -ne 'Collapsed') { throw 'Perch layout failed' }
            Set-Dock 'hanging' (Get-CurrentArea)
            if ($silk.Visibility -ne 'Visible') { throw 'Hanging layout failed' }
            Open-OpenCode
            if ($notice -ne 'OpenCode action checked') { throw 'Click action failed' }
            if ($window.ShowInTaskbar -or $window.Background) { throw 'Frameless contract failed' }
            $window.Close()
        }
    }
    function Show-ActivityFrame($Frame) {
        if (-not $Frame) {
            $castWeb.Visibility = 'Collapsed'; $caughtWord.Visibility = 'Collapsed'
            return
        }
        $bodyY = [Windows.Controls.Canvas]::GetTop($spider) + 56
        $wordX = 190 + (120 - 190)*$Frame.Pull
        $wordY = ($bodyY - 50) + 50*$Frame.Pull
        $castWeb.X1 = 120; $castWeb.Y1 = $bodyY
        $castWeb.X2 = 120 + ($wordX - 120)*$Frame.Cast
        $castWeb.Y2 = $bodyY + ($wordY - $bodyY)*$Frame.Cast
        $castWeb.Opacity = $Frame.Opacity
        $caughtWord.Text = $Frame.Word; $caughtWord.Opacity = $Frame.Opacity
        [Windows.Controls.Canvas]::SetLeft($caughtWord,$wordX - 32)
        [Windows.Controls.Canvas]::SetTop($caughtWord,$wordY - 9)
        $castWeb.Visibility = 'Visible'; $caughtWord.Visibility = 'Visible'
    }
    function Save-Preview([string]$Path) {
        $scene.Measure([Windows.Size]::new(240,230)); $scene.Arrange([Windows.Rect]::new(0,0,240,230)); $scene.UpdateLayout()
        $render = [Windows.Media.Imaging.RenderTargetBitmap]::new(240,230,96,96,[Windows.Media.PixelFormats]::Pbgra32); $render.Render($scene)
        $encoder = [Windows.Media.Imaging.PngBitmapEncoder]::new(); $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($render))
        $file = [IO.File]::Create($Path)
        try { $encoder.Save($file) } finally { $file.Dispose() }
    }
    $script:timer = [Windows.Threading.DispatcherTimer]::new(); $timer.Interval = [timespan]::FromMilliseconds(100)
    $timer.Add_Tick({ try { Update-View } catch { $script:uiFailure = $_; $window.Close() } })
    $window.Add_Closed({ $timer.Stop(); Save-Preferences })
    Update-View
    if ($PreviewPath -and -not $SmokeTest) { Save-Preview $PreviewPath }
    else {
        $application = [Windows.Application]::new()
        $application.ShutdownMode = 'OnMainWindowClose'
        $timer.Start(); [void]$application.Run($window)
        if ($uiFailure) { throw $uiFailure }
        if ($SmokeTest) { 'PASS: frameless WPF, hanging/perched layout, isolated click and cleanup' }
    }
} catch {
    if ($SmokeTest -or $PreviewPath) { throw }
    Write-WebbyLog 'Application stopped after an error.'
    Add-Type -AssemblyName PresentationFramework
    [void][Windows.MessageBox]::Show('Webby could not start. Check Windows PowerShell 5.1, the sprite file and your server URL. See %LOCALAPPDATA%\Webby\webby.log.', 'Webby')
    exit 1
} finally {
    if ($stream) { $stream.Dispose() }
    if ($tray) { $tray.Visible = $false; $tray.Dispose() }
    if ($iconHandle -ne [IntPtr]::Zero) { [void][WebbyNative]::DestroyIcon($iconHandle) }
    if ($ownsMutex) { $mutex.ReleaseMutex() }
    if ($mutex) { $mutex.Dispose() }
}
