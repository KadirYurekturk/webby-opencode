function New-SpiderState {
    @{ Connected = $false; Sessions = @{}; Permissions = @{}; LastResult = 'idle'; LastResultAt = [datetime]::MinValue }
}

function Update-SpiderState($State, $Event) {
    $type = [string]$Event.type
    $data = $Event.data
    $session = [string]$data.sessionID
    switch ($type) {
        'server.connected' { $State.Connected = $true }
        'transport.disconnected' {
            $State.Connected = $false
            $State.Sessions.Clear()
            $State.Permissions.Clear()
            $State.LastResult = 'idle'
        }
        'session.execution.started' {
            if ($session) { $State.Sessions[$session] = $true }
            $State.LastResult = 'idle'
        }
        'permission.asked' {
            if ($session -and $data.id) { $State.Permissions[[string]$data.id] = $session }
        }
        'permission.replied' {
            $id = [string]$data.requestID
            $State.Permissions.Remove($id)
        }
        { $_ -in 'session.execution.succeeded','session.execution.failed','session.execution.interrupted','session.deleted' } {
            if (-not $session) { return }
            $State.Sessions.Remove($session)
            foreach ($key in @($State.Permissions.Keys)) {
                if ($State.Permissions[$key] -eq $session) { $State.Permissions.Remove($key) }
            }
            $State.LastResult = switch ($type) {
                'session.execution.succeeded' { 'done' }
                'session.execution.failed' { 'error' }
                default { 'idle' }
            }
            $State.LastResultAt = [datetime]::UtcNow
        }
    }
}

function Get-SpiderMood($State) {
    if (-not $State.Connected) { return 'offline' }
    if ($State.Permissions.Count) { return 'waiting' }
    if ($State.Sessions.Count) { return 'working' }
    if (([datetime]::UtcNow - $State.LastResultAt).TotalSeconds -lt 8) { return $State.LastResult }
    'idle'
}
