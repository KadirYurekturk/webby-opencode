$ErrorActionPreference = 'Stop'
$root = (Resolve-Path "$PSScriptRoot/..").Path
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('webby-plugin-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Force $testRoot)
$pluginPath = $root.Replace('\','/')
$config = @{plugins=@($pluginPath)} | ConvertTo-Json
[IO.File]::WriteAllText((Join-Path $testRoot 'opencode.json'), $config, [Text.UTF8Encoding]::new($false))
$binary = Join-Path $root '.tools/package/bin/opencode.exe'
if (-not (Test-Path $binary)) { throw 'OpenCode v2.2.0 test binary is missing' }
$stdout = Join-Path $testRoot 'server.log'; $stderr = Join-Path $testRoot 'server-error.log'
$server = Start-Process -FilePath $binary -WorkingDirectory $testRoot -ArgumentList @('serve','--hostname','127.0.0.1','--port','4198') -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
try {
    $deadline = [datetime]::UtcNow.AddSeconds(25); $password = $null
    do {
        if (Test-Path $stdout) {
            $line = Get-Content $stdout | Where-Object { $_ -like 'server password *' } | Select-Object -First 1
            if ($line) { $password = $line.Substring(16) }
        }
        if (-not $password) { Start-Sleep -Milliseconds 250 }
    } until ($password -or [datetime]::UtcNow -gt $deadline -or $server.HasExited)
    if (-not $password) { throw 'OpenCode server did not start' }
    $auth = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('opencode:' + $password))
    $headers = @{Authorization='Basic ' + $auth}
    $deadline = [datetime]::UtcNow.AddSeconds(15)
    do {
        $pluginResult = Invoke-RestMethod 'http://127.0.0.1:4198/api/plugin' -Headers $headers
        $plugin = @($pluginResult.data | Where-Object { $_.id -eq 'webby' })
        if ($plugin.Count -eq 0) { Start-Sleep -Milliseconds 500 }
    } until ($plugin.Count -gt 0 -or [datetime]::UtcNow -gt $deadline)
    if ($plugin.Count -ne 1) { throw 'Webby plugin not discovered by OpenCode v2.2.0' }
    $deadline = [datetime]::UtcNow.AddSeconds(15)
    do {
        $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$($server.Id)" | Where-Object { $_.Name -eq 'powershell.exe' -and $_.CommandLine -like '*-PluginMode*' })
        if ($children.Count -eq 0) { Start-Sleep -Milliseconds 250 }
    } until ($children.Count -gt 0 -or [datetime]::UtcNow -gt $deadline)
    if ($children.Count -ne 1) { throw "Expected one Webby child process, found $($children.Count)" }
    'PASS: OpenCode v2.2.0 discovers Webby and launches its Windows companion'
} finally {
    if (-not $server.HasExited) { Stop-Process -Id $server.Id }
    foreach ($child in $children) { Stop-Process -Id $child.ProcessId -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $stdout,$stderr -ErrorAction SilentlyContinue
}
