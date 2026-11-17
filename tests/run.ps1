# Runs the static lint and the offline smoke tests.
#   powershell -ExecutionPolicy Bypass -File tests\run.ps1            (lint + smoke tests)
#   powershell -ExecutionPolicy Bypass -File tests\run.ps1 -NoLint    (smoke tests only)
#   powershell -ExecutionPolicy Bypass -File tests\run.ps1 -Verbose   (passes -v to the runner)
# Lua 5.1 / LuaJIT is looked up in this order: $env:LUA, tests\bin\lua5.1.exe, tests\bin\lua.exe,
# then lua5.1 / lua51 / luajit / lua on PATH, last $env:LUA_DLL (a 64-bit lua51.dll, run through
# tests\luahost.ps1). Exit code 0 = everything passed.
param([switch]$NoLint, [switch]$Verbose)

$root = Split-Path -Parent $PSScriptRoot
$failed = $false

if (-not $NoLint) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'lint.ps1')
    if ($LASTEXITCODE -ne 0) { $failed = $true }
}

$lua = $null
$candidates = @()
if ($env:LUA) { $candidates += $env:LUA }
$candidates += (Join-Path $PSScriptRoot 'bin\lua5.1.exe'), (Join-Path $PSScriptRoot 'bin\lua.exe')
foreach ($c in $candidates) { if ($c -and (Test-Path $c)) { $lua = $c; break } }
if (-not $lua) {
    foreach ($n in 'lua5.1', 'lua51', 'luajit', 'lua') {
        $cmd = Get-Command $n -ErrorAction SilentlyContinue
        if ($cmd) { $lua = $cmd.Source; break }
    }
}
$dll = $null
if (-not $lua -and $env:LUA_DLL -and (Test-Path $env:LUA_DLL)) { $dll = $env:LUA_DLL }
if (-not $lua -and -not $dll) {
    Write-Host 'smoke tests: no Lua 5.1 interpreter found (see tests\README.md)' -ForegroundColor Yellow
    exit 2
}

Push-Location $root
try {
    if ($lua) {
        $luaArgs = @('tests/run.lua')
        if ($Verbose) { $luaArgs += '-v' }
        & $lua @luaArgs
    } else {
        # no lua.exe: an existing 64-bit lua51.dll (LuaJIT) hosted inside PowerShell
        $hostArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'luahost.ps1'),
            '-Dll', $dll, '-Script', (Join-Path $PSScriptRoot 'run.lua'))
        if ($Verbose) { $hostArgs += '-ScriptArgs', '-v' }
        & powershell @hostArgs
    }
    if ($LASTEXITCODE -ne 0) { $failed = $true }
} finally { Pop-Location }

if ($failed) { exit 1 }
exit 0
