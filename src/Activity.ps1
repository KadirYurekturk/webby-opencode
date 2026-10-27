# Response fragments stay in memory and are never written to logs.
function New-WebbyActivity {
    @{ Pending=$null; Word=''; Session=''; StartedAt=[datetime]::MinValue; LastCastAt=[datetime]::MinValue; Buffer=''; BufferSession='' }
}

function Add-WebbyActivity($Activity, $Event, [datetime]$Now = [datetime]::UtcNow) {
    if (-not $Event.data.sessionID) { return }
    if ($Event.type -eq 'session.text.delta') {
        if ($Activity.BufferSession -ne $Event.data.sessionID) { $Activity.Buffer = ''; $Activity.BufferSession = [string]$Event.data.sessionID }
        $chunk = [string]$Event.data.delta
        if ($chunk.Length -gt 2048) { $chunk = $chunk.Substring(0,2048) }
        $combined = $Activity.Buffer + $chunk
        $matches = [regex]::Matches($combined, '(?<![\p{L}\p{N}_])[\p{L}]{3,10}(?![\p{L}\p{N}_])(?=\s|[.,!?;:])')
        foreach ($match in $matches) { $Activity.Pending = @{Word=$match.Value;At=$Now;Session=[string]$Event.data.sessionID;Reply=$true} }
        $tail = [regex]::Match($combined, '[\p{L}]+$').Value
        $Activity.Buffer = if ($tail.Length -le 10) { $tail } else { '' }
        return
    }
    if ($Event.type -in 'session.execution.succeeded','session.execution.failed','session.execution.interrupted','session.deleted') {
        $Activity.Buffer = ''; $Activity.BufferSession = ''
        if ($Activity.Pending -and $Activity.Pending.Session -eq $Event.data.sessionID -and -not $Activity.Pending.Reply) { $Activity.Pending = $null }
        if ($Activity.Session -eq $Event.data.sessionID -and -not $Activity.IsReply) { $Activity.Word = ''; $Activity.Session = '' }
        return
    }
    $word = switch ([string]$Event.type) {
        'session.reasoning.started' { 'think' }
        'session.tool.input.started' {
            switch ([string]$Event.data.name) {
                { $_ -in 'read','read_file' } { 'read'; break }
                { $_ -in 'grep','glob','search','websearch','webfetch' } { 'search'; break }
                { $_ -in 'edit','write','patch','apply_patch' } { 'edit'; break }
                { $_ -in 'test','tests' } { 'test'; break }
                { $_ -in 'shell','bash','execute' } { 'run'; break }
                default { 'tool' }
            }
        }
        default { '' }
    }
    if ($word -and -not ($Activity.Pending -and $Activity.Pending.Reply)) { $Activity.Pending = @{Word=$word;At=$Now;Session=[string]$Event.data.sessionID;Reply=$false} }
}

function Get-WebbyActivityFrame($Activity, [string]$Mood, [bool]$Paused, [datetime]$Now = [datetime]::UtcNow) {
    if ($Paused -or $Mood -notin 'working','done') {
        $Activity.Pending = $null; $Activity.Word = ''; $Activity.Buffer = ''; $Activity.BufferSession = ''
        return $null
    }
    if ($Activity.Word -and ($Now - $Activity.StartedAt).TotalSeconds -ge 1.8) { $Activity.Word = '' }
    if (-not $Activity.Word -and $Activity.Pending) {
        if (($Now - $Activity.Pending.At).TotalSeconds -gt 6) { $Activity.Pending = $null }
        elseif (($Now - $Activity.LastCastAt).TotalSeconds -ge 4) {
            $Activity.Word = $Activity.Pending.Word; $Activity.Session = $Activity.Pending.Session; $Activity.IsReply = $Activity.Pending.Reply; $Activity.Pending = $null
            $Activity.StartedAt = $Now; $Activity.LastCastAt = $Now
        }
    }
    if (-not $Activity.Word) { return $null }
    $elapsed = [math]::Max(0.0, ($Now - $Activity.StartedAt).TotalSeconds)
    $pull = [math]::Min(1.0, [math]::Max(0.0, ($elapsed - 0.3) / 1.5))
    @{ Word=$Activity.Word; Cast=[math]::Min(1.0,$elapsed/0.3); Pull=($pull*$pull*(3-2*$pull)); Opacity=[math]::Min(1.0,(1-$pull)*4) }
}
