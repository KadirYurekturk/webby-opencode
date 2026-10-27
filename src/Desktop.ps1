function Get-WebbyServiceFile {
    $root = $env:XDG_STATE_HOME
    if (-not $root) { $root = Join-Path $env:USERPROFILE '.local/state' }
    Join-Path $root 'opencode/service.json'
}

function Get-WebbyEndpoint([string]$ServerUrl, [string]$ServiceFile) {
    if ($ServerUrl) {
        $username = $env:OPENCODE_SERVER_USERNAME
        if (-not $username) { $username = 'opencode' }
        $endpoint = @{ Url=$ServerUrl; Username=$username; Password=$env:OPENCODE_PASSWORD }
    } else {
        if (-not (Test-Path -LiteralPath $ServiceFile)) { return $null }
        try { $registration = Get-Content -LiteralPath $ServiceFile -Raw | ConvertFrom-Json } catch { return $null }
        if ([string]$registration.version -notmatch '^2\.') { return $null }
        $endpoint = @{ Url=[string]$registration.url; Username='opencode'; Password=[string]$registration.password }
    }
    $uri = $null
    if (-not [uri]::TryCreate($endpoint.Url, [UriKind]::Absolute, [ref]$uri) -or
        -not $uri.IsLoopback -or $uri.Scheme -notin 'http','https' -or $uri.UserInfo -or
        $uri.AbsolutePath -ne '/' -or $uri.Query -or $uri.Fragment) {
        if ($ServerUrl) { throw 'Use a loopback server URL without a path or credentials.' }
        return $null
    }
    $endpoint.Url = $uri.GetLeftPart([UriPartial]::Authority)
    $endpoint
}

function Get-WebbyDock([double]$Left, [double]$Top, $Area, [double]$Width, [double]$Height) {
    $mode = if (($Top + $Height / 2) -lt ($Area.Top + $Area.Height / 2)) { 'hanging' } else { 'perched' }
    $x = [math]::Max($Area.Left, [math]::Min($Left, $Area.Right - $Width))
    $y = if ($mode -eq 'hanging') { $Area.Top } else { $Area.Bottom - $Height }
    @{ Left=$x; Top=$y; Mode=$mode }
}

function Write-WebbySettings($Path, $Settings) {
    $folder = Split-Path -Parent $Path
    [void][IO.Directory]::CreateDirectory($folder)
    $Settings | ConvertTo-Json | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Write-WebbyLog([string]$Message) {
    # Only application-owned messages; never log server payloads or credentials.
    $folder = Join-Path $env:LOCALAPPDATA 'Webby'
    [void][IO.Directory]::CreateDirectory($folder)
    $path = Join-Path $folder 'webby.log'
    if ((Test-Path $path) -and (Get-Item $path).Length -gt 65536) { [IO.File]::WriteAllText($path, '') }
    Add-Content -LiteralPath $path -Value ((Get-Date -Format s) + ' ' + $Message)
}
