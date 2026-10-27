param([string]$ProjectDirectory, [string]$ServerUrl)
$ErrorActionPreference = 'Stop'
try {
    Set-Location -LiteralPath $ProjectDirectory
    $host.UI.RawUI.WindowTitle = 'OpenCode'
    if ($ServerUrl) { & opencode --server $ServerUrl } else { & opencode }
} catch {
    Write-Host 'OpenCode could not start. Install OpenCode v2 and check the selected project folder.' -ForegroundColor Red
}
