param([string]$ServerUrl = 'http://127.0.0.1:4096')
$ErrorActionPreference = 'Stop'
Add-Type -Path "$PSScriptRoot/../src/EventStream.cs"
$user = $env:OPENCODE_SERVER_USERNAME
if (-not $user) { $user = 'opencode' }
$pair = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($user + ':' + $env:OPENCODE_PASSWORD))
$headers = @{ Authorization = 'Basic ' + $pair }
$info = Invoke-RestMethod "$ServerUrl/api/info" -Headers $headers
$stream = [SpiderEventStream]::new($ServerUrl, $user, $env:OPENCODE_PASSWORD)
try {
    $deadline = [datetime]::UtcNow.AddSeconds(10)
    $connected = $false
    do {
        $raw = ''
        while ($stream.Events.TryDequeue([ref]$raw)) {
            $event = $raw | ConvertFrom-Json
            if ($event.type -eq 'server.connected') { $connected = $true }
        }
        Start-Sleep -Milliseconds 100
    } until ($connected -or [datetime]::UtcNow -gt $deadline)
    if (-not $connected) { throw "No server.connected event: $($stream.Status)" }
    "PASS: authenticated SSE connection to OpenCode $($info.version)"
} finally { $stream.Dispose() }
