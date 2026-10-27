$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/../src/State.ps1"
function Assert-Equal($actual, $expected, $message) {
    if ($actual -ne $expected) { throw "$message : expected '$expected', got '$actual'" }
}
function Send-Event($type, $session = 'a', $id = 'p1') {
    Update-SpiderState $state ([pscustomobject]@{ type=$type; data=[pscustomobject]@{sessionID=$session; id=$id; requestID=$id} })
}
$state = New-SpiderState
Assert-Equal (Get-SpiderMood $state) 'offline' 'Starts disconnected'
Send-Event 'server.connected'
Assert-Equal (Get-SpiderMood $state) 'idle' 'Connected'
Send-Event 'session.execution.started'
Assert-Equal (Get-SpiderMood $state) 'working' 'Execution starts'
Send-Event 'permission.asked'
Send-Event 'session.execution.started' 'b'
Assert-Equal (Get-SpiderMood $state) 'waiting' 'Permission has priority across sessions'
Send-Event 'permission.asked' 'a' 'p2'
Send-Event 'permission.replied'
Assert-Equal (Get-SpiderMood $state) 'waiting' 'Second permission remains pending'
Send-Event 'permission.replied' 'a' 'p2'
Assert-Equal (Get-SpiderMood $state) 'working' 'Resumes after all permissions'
Send-Event 'session.execution.succeeded'
Assert-Equal (Get-SpiderMood $state) 'working' 'Other session still running'
Send-Event 'session.execution.failed' 'b'
Assert-Equal (Get-SpiderMood $state) 'error' 'Execution error'
Send-Event 'session.execution.started' 'b'
Send-Event 'session.execution.succeeded' 'b'
Assert-Equal (Get-SpiderMood $state) 'done' 'Completion'
$state.LastResultAt = [datetime]::UtcNow.AddSeconds(-10)
Assert-Equal (Get-SpiderMood $state) 'idle' 'Completion expires'
Send-Event 'session.execution.started'
Send-Event 'session.execution.interrupted'
Assert-Equal (Get-SpiderMood $state) 'idle' 'Interrupted session stops working'
Send-Event 'permission.asked'
Send-Event 'session.deleted'
Assert-Equal (Get-SpiderMood $state) 'idle' 'Deleting session clears pending permissions'
Send-Event 'transport.disconnected'
Assert-Equal (Get-SpiderMood $state) 'offline' 'Disconnect clears stale state'
Send-Event 'unknown.event'
Assert-Equal (Get-SpiderMood $state) 'offline' 'Unknown events ignored'
'PASS: state transitions, concurrent sessions, permissions, disconnect, result expiry'

. "$PSScriptRoot/../src/Desktop.ps1"
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('webby-' + [guid]::NewGuid().ToString() + '.json')
try {
    '{"version":"2.2.0","url":"http://127.0.0.1:4096","password":"test-only"}' | Set-Content $fixture
    $endpoint = Get-WebbyEndpoint '' $fixture
    Assert-Equal $endpoint.Url 'http://127.0.0.1:4096' 'Discover registered service'
    Assert-Equal $endpoint.Password 'test-only' 'Use registered authentication in memory'
    '{"version":"2.2.0","url":"https://example.com","password":"test-only"}' | Set-Content $fixture
    Assert-Equal (Get-WebbyEndpoint '' $fixture) $null 'Reject non-loopback registration'
    '{broken json' | Set-Content $fixture
    Assert-Equal (Get-WebbyEndpoint '' $fixture) $null 'Tolerate partial registration writes'
    $rejected = $false
    try { $null = Get-WebbyEndpoint 'http://user:pass@localhost:4096' '' } catch { $rejected = $true }
    Assert-Equal $rejected $true 'Reject credentials in URL'
    $area = @{Left=0;Right=1920;Top=0;Bottom=1040;Height=1040}
    $dock = Get-WebbyDock 1800 40 $area 240 230
    Assert-Equal $dock.Mode 'hanging' 'Upper half docks at top'
    Assert-Equal $dock.Left 1680 'Clamp to work area'
    $dock = Get-WebbyDock -20 900 $area 240 230
    Assert-Equal $dock.Mode 'perched' 'Lower half docks above taskbar'
    Assert-Equal $dock.Top 810 'Respect taskbar work area'
    Assert-Equal $dock.Left 0 'Clamp left edge'
    Write-WebbySettings $fixture @{Mode='perched';Paused=$true;Project='C:\project'}
    $saved = Get-Content $fixture -Raw | ConvertFrom-Json
    Assert-Equal $saved.Mode 'perched' 'Preferences round trip'
    'PASS: service discovery, URL validation, docking and preferences'
} finally { if (Test-Path $fixture) { Remove-Item -LiteralPath $fixture } }

. "$PSScriptRoot/../src/Activity.ps1"
$activity = New-WebbyActivity
$now = [datetime]'2026-10-27T12:00:00Z'
function Send-Activity($type, $name, $at = $now) {
    Add-WebbyActivity $activity ([pscustomobject]@{type=$type;data=@{sessionID='s1';name=$name;input=@{secret='must-not-render'}}}) $at
}
Send-Activity 'session.tool.input.started' 'read'
$frame = Get-WebbyActivityFrame $activity 'working' $false $now
Assert-Equal $frame.Word 'read' 'Tool name maps to safe word'
Assert-Equal $frame.Cast 0 'Cast starts at spider'
$frame = Get-WebbyActivityFrame $activity 'working' $false $now.AddSeconds(1)
if ($frame.Pull -le 0 -or $frame.Pull -ge 1) { throw 'Word must be pulled toward spider' }
Send-Activity 'session.tool.input.started' 'edit' $now.AddSeconds(1)
Assert-Equal (Get-WebbyActivityFrame $activity 'working' $false $now.AddSeconds(2)) $null 'No overlapping or rapid casts'
Assert-Equal (Get-WebbyActivityFrame $activity 'working' $false $now.AddSeconds(4)).Word 'edit' 'Latest event waits for cooldown'
Assert-Equal (Get-WebbyActivityFrame $activity 'waiting' $false $now.AddSeconds(4.1)) $null 'Permission interrupts animation'
Send-Activity 'session.tool.input.started' 'private-custom-tool-name' $now.AddSeconds(9)
Assert-Equal (Get-WebbyActivityFrame $activity 'working' $false $now.AddSeconds(9)).Word 'tool' 'Custom names never exposed'
Assert-Equal (Get-WebbyActivityFrame $activity 'working' $true $now.AddSeconds(9.1)) $null 'Reduced motion clears activity'
Send-Activity 'session.reasoning.started' '' $now.AddSeconds(14)
Assert-Equal (Get-WebbyActivityFrame $activity 'working' $false $now.AddSeconds(14)).Word 'think' 'Reasoning produces fixed label'
Send-Activity 'session.execution.succeeded' '' $now.AddSeconds(14.2)
Assert-Equal (Get-WebbyActivityFrame $activity 'working' $false $now.AddSeconds(14.3)) $null 'Finished session clears animation even while others work'
Send-Activity 'session.tool.input.started' 'grep' $now.AddSeconds(20)
Assert-Equal (Get-WebbyActivityFrame $activity 'working' $false $now.AddSeconds(27)) $null 'Discard stale activity'
Send-Activity 'session.reasoning.delta' 'secret words' $now.AddSeconds(28)
Assert-Equal $activity.Pending $null 'Ignore model content'
Add-WebbyActivity $activity ([pscustomobject]@{type='session.text.delta';data=@{sessionID='s1';delta='Mer'}}) $now.AddSeconds(30)
Assert-Equal $activity.Pending $null 'Wait for whole word'
Add-WebbyActivity $activity ([pscustomobject]@{type='session.text.delta';data=@{sessionID='s1';delta='haba dunya '}}) $now.AddSeconds(30)
Assert-Equal (Get-WebbyActivityFrame $activity 'working' $false $now.AddSeconds(30)).Word 'dunya' 'Display response word assembled from chunks'
'PASS: safe activity words, pull timing, cooldown, cancellation and reduced motion'
