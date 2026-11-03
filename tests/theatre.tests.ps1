$ErrorActionPreference='Stop'
. "$PSScriptRoot/../src/Theatre.ps1"
$frames=[Collections.Generic.List[object]]::new()
foreach ($case in (Get-Content "$PSScriptRoot/theatre-cases.json" -Raw | ConvertFrom-Json)) {
    $stage=New-WebbyTheatre
    foreach ($step in $case.steps) {
        if ($step.event) {
            Add-WebbyTheatreEvent $stage ([pscustomobject]@{type=$step.event;data=@{sessionID=$step.session}}) $step.time
        } else {
            $f=Get-WebbyTheatreFrame $stage $step.mood $step.time ([bool]$step.blocked)
            foreach ($p in $step.expect.PSObject.Properties) {
                if ($f[$p.Name] -ne $p.Value) { throw "$($case.name) at $($step.time): $($p.Name) expected $($p.Value), got $($f[$p.Name])" }
            }
            $frames.Add($f)
        }
    }
}
if (@(Get-WebbyWebSegments 0).Count -ne 0 -or @(Get-WebbyWebSegments 1).Count -ne 13) { throw 'Web geometry failed' }
ConvertTo-Json -InputObject $frames.ToArray() -Depth 5 -Compress
