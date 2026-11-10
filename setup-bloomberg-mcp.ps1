# Sets up Claude Code + the xbbg Bloomberg MCP server on a fresh Windows profile.
# Paste into a normal PowerShell window (not into Claude Code). Safe to re-run.
# Requires: Bloomberg Terminal open and logged in (bbcomm running) for data to flow.

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'   # makes Invoke-WebRequest much faster in Windows PowerShell 5.1
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$binDir = "$HOME\.local\bin"
$claude = "$binDir\claude.exe"
$root   = "$HOME\tools\xbbg-mcp"
$zip    = "$root\x.zip"
$exe    = "$root\bin\xbbg-mcp.exe"
$url    = 'https://github.com/underloam/xbbg/releases/download/v1.5.0/xbbg-mcp-v1.5.0-windows-amd64.zip'

# SHA256 of the v1.5.0 zip from the first successful setup. A mismatch means the file changed
# since then. It does NOT prove the publisher is trustworthy.
$expectedHash = '657E8BF401024FA13F9FF1444BD132352A4C1FD718CCC443CDECC416DB49223B'

Write-Host "`n[1/5] Claude Code" -ForegroundColor Cyan
if (-not (Test-Path $claude)) {
    Write-Host 'Installing Claude Code...'
    irm https://claude.ai/install.ps1 | iex
}
if (-not (Test-Path $claude)) { throw "Claude Code not found at $claude after install." }

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$parts = @()
if ($userPath) { $parts = $userPath -split ';' }
if ($parts -notcontains $binDir) {
    [Environment]::SetEnvironmentVariable('Path', (($parts + $binDir) -join ';'), 'User')
    Write-Host "Added $binDir to your user PATH (applies to new windows)."
}
$env:Path += ";$binDir"
Write-Host ("Claude Code version: " + (& $claude --version))

Write-Host "`n[2/5] xbbg-mcp download" -ForegroundColor Cyan
if (Test-Path $exe) {
    Write-Host "Already present: $exe"
} else {
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    Invoke-WebRequest -Uri $url -OutFile $zip
    $size = (Get-Item $zip).Length
    $hash = (Get-FileHash $zip -Algorithm SHA256).Hash
    Write-Host "Zip size: $size bytes"
    Write-Host "SHA256:   $hash"
    if ($hash -ne $expectedHash) {
        Remove-Item $zip -Force
        throw 'Hash does not match the expected value. Stopped and deleted the zip. Do not run it.'
    }
    Expand-Archive -Path $zip -DestinationPath "$root\bin" -Force
    Remove-Item $zip -Force
    if (-not (Test-Path $exe)) { throw "Expected $exe after extraction, but it is missing." }
    Write-Host "Extracted: $exe"
}
Write-Host ("Signature status: " + (Get-AuthenticodeSignature $exe).Status + " (NotSigned is expected)")

Write-Host "`n[3/5] Registering MCP server" -ForegroundColor Cyan
$ErrorActionPreference = 'Continue'
& $claude mcp remove xbbg --scope user *> $null    # ignore 'not found' on a fresh profile
$ErrorActionPreference = 'Stop'
& $claude mcp add --scope user --transport stdio xbbg -- $exe
if ($LASTEXITCODE -ne 0) { throw 'claude mcp add failed.' }

Write-Host "`n[4/5] Bloomberg checks" -ForegroundColor Cyan
$wintrv = Get-Process wintrv -ErrorAction SilentlyContinue
$bbcomm = Get-Process bbcomm -ErrorAction SilentlyContinue
$port   = Get-NetTCPConnection -LocalPort 8194 -State Listen -ErrorAction SilentlyContinue
Write-Host ("Terminal (wintrv) running: " + [bool]$wintrv)
Write-Host ("bbcomm running:            " + [bool]$bbcomm)
Write-Host ("Port 8194 listening:       " + [bool]$port)
if (-not ($bbcomm -and $port)) {
    Write-Warning 'Bloomberg API is not up. Log in to the Terminal (restart it if needed), then re-run this check. The server will not return data until bbcomm is running and port 8194 is listening.'
}

Write-Host "`n[5/5] Done" -ForegroundColor Green
Write-Host 'Next: open a NEW PowerShell window, run:  claude'
Write-Host 'Then ask:  Use Bloomberg to get PX_LAST for AAPL US Equity.'
