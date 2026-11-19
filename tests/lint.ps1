# Adventurer's Kit static lint (no Lua needed).
#   powershell -ExecutionPolicy Bypass -File tests\lint.ps1
# Exit code 0 = clean, 1 = problems found.
#
# Checks, per .lua file of the 3 code addons:
#   0. unterminated strings (a quote left over after strings and comments are stripped)
#   1. block balance: function/do/then/repeat - elseif == end/until (strings and comments stripped)
#   2. ( ) { } [ ] balance
#   3. single-backslash texture paths in quoted strings ("Interface\Icons" instead of "Interface\\Icons")
#   4. multi-return truncation: `local a, b = x and f()` (a multi-target assignment whose single
#      right-hand expression has a top-level and/or keeps only one value)
#   5. accidental globals (heuristic): `name = ...` or `function name(` at table depth 0 where the name
#      is not declared local anywhere in the file and not on the allow list below
#   6. every file listed in a .toc exists
param([string]$Root = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
$folders = @('AdventurersKit', 'AdventurersKit_Bags', 'AdventurersKit_Buffs')

# Globals the addon sets on purpose (SavedVariables, slash commands, key binding labels, frames by name).
$allowGlobals = @('QuestFocusDB', 'QuestFocusCharDB')
$allowGlobalPatterns = @('^SLASH_', '^BINDING_', '^QuestFocus', '^AdventurersKit', '^StaticPopupDialogs$')

$problems = New-Object System.Collections.Generic.List[string]
function Add-Problem([string]$file, [int]$line, [string]$msg) {
    $rel = $file.Substring($Root.Length).TrimStart('\', '/')
    if ($line -gt 0) { $problems.Add("${rel}:${line}: $msg") } else { $problems.Add("${rel}: $msg") }
}

# Comments and strings, leftmost match wins (that is how the Lua lexer scans too).
$tokenRx = New-Object System.Text.RegularExpressions.Regex (
    '--\[(=*)\[[\s\S]*?\]\1\]|--[^\n]*|\[(=*)\[[\s\S]*?\]\2\]|"(?:\\[\s\S]|[^"\\\n])*"|''(?:\\[\s\S]|[^''\\\n])*''')

function Get-LineNo([string]$text, [int]$index) {
    $n = 1
    for ($i = 0; $i -lt $index; $i++) { if ($text[$i] -eq "`n") { $n++ } }
    return $n
}

function Get-TopLevelSplit([string]$s) {
    # Split on commas at depth 0 (strings are already blanked).
    $parts = @(); $depth = 0; $cur = ''
    foreach ($ch in $s.ToCharArray()) {
        if ('({['.Contains($ch)) { $depth++ } elseif (')}]'.Contains($ch)) { $depth-- }
        if ($ch -eq ',' -and $depth -eq 0) { $parts += $cur; $cur = '' } else { $cur += $ch }
    }
    $parts += $cur
    return , $parts
}

function Remove-Nested([string]$s) {
    # Drop everything inside brackets, so only the top-level expression is left.
    $out = ''; $depth = 0
    foreach ($ch in $s.ToCharArray()) {
        if ('({['.Contains($ch)) { if ($depth -eq 0) { $out += $ch }; $depth++; continue }
        if (')}]'.Contains($ch)) { $depth--; if ($depth -eq 0) { $out += $ch }; continue }
        if ($depth -eq 0) { $out += $ch }
    }
    return $out
}

$files = foreach ($f in $folders) { Get-ChildItem -Path (Join-Path $Root $f) -Recurse -Filter *.lua }

foreach ($file in $files) {
    $raw = [IO.File]::ReadAllText($file.FullName)
    $text = $raw -replace "`r`n", "`n"

    # 3. texture paths: only in quoted strings (inside [[ ]] a single backslash is right).
    foreach ($m in $tokenRx.Matches($text)) {
        $v = $m.Value
        if ($v.StartsWith('"') -or $v.StartsWith("'")) {
            if ($v -match '(?i)Interface\\(?!\\)') {
                Add-Problem $file.FullName (Get-LineNo $text $m.Index) "single-backslash texture path: $v"
            }
        }
    }

    # Strip: comments -> nothing, strings -> "" (newlines kept so line numbers stay right).
    $code = $tokenRx.Replace($text, {
            param($m)
            $nl = ($m.Value -split "`n").Count - 1
            $keep = if ($m.Value.StartsWith('--')) { '' } else { '_S_' }
            return $keep + ("`n" * $nl)
        })

    # 0. a quote left after stripping = a string that never ends on its line (e.g. "\", ...)
    $ln0 = 0
    foreach ($l in ($code -split "`n")) {
        $ln0++
        if ($l -match '["'']') { Add-Problem $file.FullName $ln0 "unterminated string: $($l.Trim())" }
    }

    # 1. block balance
    $open = ([regex]::Matches($code, '\b(function|do|then|repeat)\b')).Count
    $elseif = ([regex]::Matches($code, '\belseif\b')).Count
    $close = ([regex]::Matches($code, '\b(end|until)\b')).Count
    if (($open - $elseif) -ne $close) {
        Add-Problem $file.FullName 0 "block balance: function/do/then/repeat-elseif = $($open - $elseif), end/until = $close"
    }
    # 2. bracket balance
    foreach ($pair in @(@('(', ')'), @('{', '}'), @('[', ']'))) {
        $a = ($code.ToCharArray() | Where-Object { $_ -eq $pair[0] }).Count
        $b = ($code.ToCharArray() | Where-Object { $_ -eq $pair[1] }).Count
        if ($a -ne $b) { Add-Problem $file.FullName 0 "'$($pair[0])' x$a vs '$($pair[1])' x$b" }
    }

    $lines = $code -split "`n"

    # Names declared local anywhere in the file (scope-insensitive: a heuristic).
    $declared = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($m in [regex]::Matches($code, '\blocal\s+function\s+([A-Za-z_]\w*)')) { [void]$declared.Add($m.Groups[1].Value) }
    foreach ($m in [regex]::Matches($code, '\blocal\s+((?:[A-Za-z_]\w*\s*,\s*)*[A-Za-z_]\w*)')) {
        foreach ($n in ($m.Groups[1].Value -split ',')) { [void]$declared.Add($n.Trim()) }
    }
    foreach ($m in [regex]::Matches($code, '\bfunction\b[^(\n]*\(([^)]*)\)')) {
        foreach ($n in ($m.Groups[1].Value -split ',')) { $n = $n.Trim(); if ($n -match '^[A-Za-z_]\w*$') { [void]$declared.Add($n) } }
    }
    foreach ($m in [regex]::Matches($code, '\bfor\s+((?:[A-Za-z_]\w*\s*,\s*)*[A-Za-z_]\w*)\s*(=|\bin\b)')) {
        foreach ($n in ($m.Groups[1].Value -split ',')) { [void]$declared.Add($n.Trim()) }
    }

    $depth = 0  # { } depth at the start of the line
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $ln = $lines[$i]
        $lineNo = $i + 1

        # 4. multi-return truncation
        $mm = [regex]::Match($ln, '^\s*(?:local\s+)?([A-Za-z_][\w.]*(?:\s*,\s*[A-Za-z_][\w.]*)+)\s*=(?!=)\s*(.+)$')
        if ($mm.Success) {
            $rhs = $mm.Groups[2].Value
            $parts = Get-TopLevelSplit $rhs
            if ($parts.Count -eq 1 -and (Remove-Nested $rhs) -match '\b(and|or)\b') {
                Add-Problem $file.FullName $lineNo "multi-return truncation (only the first target gets a value): $($ln.Trim())"
            }
        }

        # 5. accidental globals
        if ($depth -eq 0) {
            $g = $null
            $ma = [regex]::Match($ln, '^\s*([A-Za-z_]\w*)\s*(?:,\s*[A-Za-z_][\w.]*\s*)*=(?!=)')
            $mf = [regex]::Match($ln, '^\s*function\s+([A-Za-z_]\w*)\s*\(')
            if ($mf.Success) { $g = $mf.Groups[1].Value } elseif ($ma.Success -and $ln -notmatch '^\s*local\b') { $g = $ma.Groups[1].Value }
            if ($g -and -not $declared.Contains($g) -and $allowGlobals -notcontains $g) {
                $ok = $false
                foreach ($p in $allowGlobalPatterns) { if ($g -match $p) { $ok = $true } }
                if (-not $ok) { Add-Problem $file.FullName $lineNo "possible accidental global '$g': $($ln.Trim())" }
            }
        }
        $depth += ([regex]::Matches($ln, '\{')).Count - ([regex]::Matches($ln, '\}')).Count
        if ($depth -lt 0) { $depth = 0 }
    }
}

# 6. .toc file lists
foreach ($f in $folders) {
    foreach ($toc in Get-ChildItem -Path (Join-Path $Root $f) -Filter *.toc) {
        $n = 0
        foreach ($l in [IO.File]::ReadAllLines($toc.FullName)) {
            $n++
            $t = $l.Trim()
            if ($t -eq '' -or $t.StartsWith('#')) { continue }
            if (-not (Test-Path (Join-Path $toc.DirectoryName $t))) { Add-Problem $toc.FullName $n "listed file missing: $t" }
        }
    }
}

Write-Host ("lint: {0} files checked" -f @($files).Count)
if ($problems.Count -gt 0) {
    $problems | ForEach-Object { Write-Host "  $_" }
    Write-Host ("lint: {0} problem(s)" -f $problems.Count) -ForegroundColor Red
    exit 1
}
Write-Host 'lint: OK' -ForegroundColor Green
exit 0
