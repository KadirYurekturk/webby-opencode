# All theatre decorations are click-through. The original sprite owns interaction.
function Initialize-WebbyTheatreView {
    $script:theatreShapes=[Collections.Generic.List[object]]::new()
    # Exclude the original front pair at render time; the source PNG is unchanged.
    $clip=[Windows.Media.Geometry]::Parse('M0,0 L112,0 112,112 0,112 Z M13.44,62.72 L40.32,62.72 40.32,89.6 13.44,89.6 Z M71.68,62.72 L98.56,62.72 98.56,89.6 71.68,89.6 Z')
    $spider.Clip=$clip
}
function Add-TheatreLine($Points, [string]$Color, [double]$Thickness) {
    $line=[Windows.Shapes.Polyline]::new(); $line.Stroke=[Windows.Media.BrushConverter]::new().ConvertFromString($Color)
    $line.StrokeThickness=$Thickness; $line.IsHitTestVisible=$false
    for ($i=0; $i -lt $Points.Count; $i+=2) { $line.Points.Add([Windows.Point]::new($Points[$i],$Points[$i+1])) }
    [Windows.Controls.Panel]::SetZIndex($line,2)
    [void]$scene.Children.Add($line); $theatreShapes.Add($line)
}
function Show-WebbyTheatreFrame($Frame, [double]$Bob) {
    foreach ($shape in $theatreShapes) { [void]$scene.Children.Remove($shape) }; $theatreShapes.Clear()
    $top=[Windows.Controls.Canvas]::GetTop($spider)+$Bob
    foreach ($line in @(Get-WebbyWebSegments $Frame.Web)) { Add-TheatreLine $line '#80589B8A' 1 }
    if ($Frame.Thread) {
        $target=if ($Frame.Web -gt 0) {@(207,51)} else {@(120,3)}
        Add-TheatreLine @(120,($top+68),$target[0],$target[1]) '#8870BDA8' 1
    }
    foreach ($side in @(-1,1)) {
        $angle=if ($side -eq -1) {$Frame.Left} else {$Frame.Right}
        $rad=$angle*[math]::PI/180; $rootX=120+$side*112*.15; $rootY=$top+112*.62
        $points=@($rootX,$rootY)
        foreach ($delta in @(@(($side*112*.16),(112*.02)),@(($side*112*.19),(112*.15)))) {
            $points+=@(($rootX+$delta[0]*[math]::Cos($rad)-$delta[1]*[math]::Sin($rad)),($rootY+$delta[0]*[math]::Sin($rad)+$delta[1]*[math]::Cos($rad)))
        }
        Add-TheatreLine $points '#171C29' 7
        Add-TheatreLine $points '#43DDA8' 2
    }
    if ($Frame.Sleep -gt 0) {
        foreach ($x in @((120-112*.072),(120+112*.066))) {
            $lid=[Windows.Shapes.Rectangle]::new(); $lid.Width=10; $lid.Height=11*$Frame.Sleep
            $lid.Fill=[Windows.Media.BrushConverter]::new().ConvertFromString('#303341'); $lid.IsHitTestVisible=$false
            [Windows.Controls.Canvas]::SetLeft($lid,($x-5)); [Windows.Controls.Canvas]::SetTop($lid,($top+112*.57))
            [Windows.Controls.Panel]::SetZIndex($lid,3)
            [void]$scene.Children.Add($lid); $theatreShapes.Add($lid)
        }
    }
}
