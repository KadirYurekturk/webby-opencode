# Stage directions use only event kinds/session IDs, never response content.
function New-WebbyTheatre {
    @{ Thinking=@{}; ThinkAt=$null; IdleAt=$null; NextIdle=45.0; IdleIndex=0; ActAt=$null; Act=''; Web=0.0; CollectAt=$null; CollectWeb=0.0 }
}
function Add-WebbyTheatreEvent($Stage, $Event, [double]$Now) {
    $sid = [string]$Event.data.sessionID
    if ($Event.type -eq 'session.reasoning.started' -and $sid) {
        if (-not $Stage.Thinking.Count) { $Stage.ThinkAt = $Now }
        $Stage.Thinking[$sid] = $true
    } elseif ($Event.type -in 'session.text.delta','session.tool.input.started','session.execution.succeeded','session.execution.failed','session.execution.interrupted','session.deleted') {
        $Stage.Thinking.Remove($sid)
    } elseif ($Event.type -eq 'transport.disconnected') { $Stage.Thinking.Clear() }
}
function Get-WebbyTheatreFrame($Stage, [string]$Mood, [double]$Now, [bool]$Blocked = $false) {
    $f = @{Scene='rest';Left=0.0;Right=0.0;Bob=0.0;Sleep=0.0;Web=0.0;Thread=$false}
    if ($Blocked -or $Mood -in 'waiting','offline','error') {
        $Stage.IdleAt=$null; $Stage.ActAt=$null; $Stage.ThinkAt=$null; $Stage.CollectAt=$null
        $Stage.Thinking.Clear(); $Stage.Web=0.0; $Stage.NextIdle=45.0
        return $f
    }
    if ($Mood -ne 'idle') { $Stage.IdleAt=$null; $Stage.ActAt=$null; $Stage.NextIdle=45.0 }
    if ($Mood -eq 'working') {
        $Stage.CollectAt=$null
        if ($Stage.Thinking.Count) {
            if ($null -eq $Stage.ThinkAt) { $Stage.ThinkAt=$Now }
            $t=[math]::Max(0.0,$Now-$Stage.ThinkAt)
            $Stage.Web=[math]::Max($Stage.Web,[math]::Min(1.0,$t/8))
            $f.Scene='think'; $f.Left=-18+[math]::Sin($t*4)*12; $f.Right=12+[math]::Sin($t*4+2)*15; $f.Thread=$true
        } else {
            $f.Scene='weave'; $f.Left=[math]::Sin($Now*5)*14; $f.Right=[math]::Sin($Now*5+[math]::PI)*14
        }
    } elseif ($Mood -eq 'done' -or ($Mood -eq 'idle' -and $Stage.Web -gt 0)) {
        if ($null -eq $Stage.CollectAt) { $Stage.CollectAt=$Now; $Stage.CollectWeb=$Stage.Web }
        $p=[math]::Min(1.0,[math]::Max(0.0,($Now-$Stage.CollectAt)/3))
        $Stage.Web=$Stage.CollectWeb*(1-$p)
        $f.Scene=if ($p -lt 1) {'collect'} else {'rest'}
        $f.Left=[math]::Sin($p*[math]::PI*6)*18*(1-$p); $f.Right=-$f.Left; $f.Thread=$Stage.Web -gt 0
    } elseif ($Mood -eq 'idle') {
        if ($null -eq $Stage.IdleAt) { $Stage.IdleAt=$Now }
        $elapsed=$Now-$Stage.IdleAt
        if ($elapsed -ge 180) {
            $f.Scene='sleep'; $f.Sleep=[math]::Min(1.0,($elapsed-180)/3); $f.Bob=[math]::Sin($Now*1.3)*1.5
        } else {
            if ($null -eq $Stage.ActAt -and $elapsed -ge $Stage.NextIdle) {
                $Stage.Act=@('clean','tug')[$Stage.IdleIndex % 2]; $Stage.IdleIndex++; $Stage.ActAt=$Now
            }
            if ($null -ne $Stage.ActAt) {
                $t=$Now-$Stage.ActAt
                if ($t -ge 3.2) {
                    $Stage.ActAt=$null; $Stage.NextIdle=$elapsed+$(if ($Stage.IdleIndex % 2) {45} else {57})
                } else {
                    $e=[math]::Sin($t/3.2*[math]::PI); $f.Scene=$Stage.Act
                    if ($Stage.Act -eq 'clean') {
                        $f.Left=-32*$e+[math]::Sin($t*14)*5*$e; $f.Right=-$f.Left
                    } else {
                        $f.Left=-42*$e; $f.Right=22*$e; $f.Bob=-[math]::Abs([math]::Sin($t*4))*4*$e; $f.Thread=$true
                    }
                }
            }
        }
    }
    $f.Web=$Stage.Web
    return $f
}
function Get-WebbyWebSegments([double]$Progress) {
    $lines=[Collections.Generic.List[object]]::new()
    foreach ($l in @(@(228,12,162,12),@(228,12,167,39),@(228,12,182,61),@(228,12,211,76))) { $lines.Add($l) }
    foreach ($r in @(22,43,66)) {
        $points=@(@((228-$r),12),@((228-$r*.92),(12+$r*.41)),@((228-$r*.70),(12+$r*.74)),@((228-$r*.26),(12+$r*.97)))
        for ($i=0; $i -lt 3; $i++) { $lines.Add(@($points[$i][0],$points[$i][1],$points[$i+1][0],$points[$i+1][1])) }
    }
    for ($i=0; $i -lt $lines.Count; $i++) {
        $p=[math]::Max(0.0,[math]::Min(1.0,$Progress*$lines.Count-$i)); $l=$lines[$i]
        if ($p -gt 0) { ,@($l[0],$l[1],($l[0]+($l[2]-$l[0])*$p),($l[1]+($l[3]-$l[1])*$p)) }
    }
}
function Get-WebbyTheatreDemo([double]$Now) {
    $t=$Now % 36; $s=New-WebbyTheatre
    if ($t -lt 15) {
        $null=Get-WebbyTheatreFrame $s idle 0
        if ($t -lt 5) { $null=Get-WebbyTheatreFrame $s idle 45; return @{Mood='idle';Frame=(Get-WebbyTheatreFrame $s idle (45+$t))} }
        if ($t -lt 10) { $s.IdleIndex=1; $null=Get-WebbyTheatreFrame $s idle 45; return @{Mood='idle';Frame=(Get-WebbyTheatreFrame $s idle (45+$t-5))} }
        return @{Mood='idle';Frame=(Get-WebbyTheatreFrame $s idle (183+$t-10))}
    }
    Add-WebbyTheatreEvent $s ([pscustomobject]@{type='session.reasoning.started';data=@{sessionID='demo'}}) 0
    if ($t -lt 25) { return @{Mood='working';Frame=(Get-WebbyTheatreFrame $s working ($t-15))} }
    $null=Get-WebbyTheatreFrame $s working 8
    Add-WebbyTheatreEvent $s ([pscustomobject]@{type='session.text.delta';data=@{sessionID='demo'}}) 8
    if ($t -lt 30) { return @{Mood='working';Frame=(Get-WebbyTheatreFrame $s working ($t-17))} }
    $null=Get-WebbyTheatreFrame $s done 0
    return @{Mood='done';Frame=(Get-WebbyTheatreFrame $s done ($t-30))}
}
