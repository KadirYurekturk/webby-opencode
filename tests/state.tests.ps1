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
