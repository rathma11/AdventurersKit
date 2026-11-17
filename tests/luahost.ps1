# Runs a Lua script inside PowerShell through an existing 64-bit lua51.dll (LuaJIT / Lua 5.1 C API),
# for machines with no lua.exe. tests\run.ps1 uses it when $env:LUA_DLL is set.
#   powershell -File tests\luahost.ps1 -Dll <path\lua51.dll> -Script tests\run.lua [-ScriptArgs -v]
# The script's io.write output is collected and printed at the end; os.exit(n) becomes this
# script's exit code.
param([Parameter(Mandatory)][string]$Dll, [Parameter(Mandatory)][string]$Script, [string[]]$ScriptArgs = @())

if (-not (Test-Path $Dll)) { Write-Host "luahost: $Dll not found"; exit 2 }
$env:PATH = (Split-Path (Resolve-Path $Dll)) + ';' + $env:PATH
if (-not ('AkLuaHost' -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class AkLuaHost {
    const string D = "lua51.dll";
    [DllImport(D, CallingConvention = CallingConvention.Cdecl)] public static extern IntPtr luaL_newstate();
    [DllImport(D, CallingConvention = CallingConvention.Cdecl)] public static extern void luaL_openlibs(IntPtr L);
    [DllImport(D, CallingConvention = CallingConvention.Cdecl)] public static extern int luaL_loadstring(IntPtr L, string s);
    [DllImport(D, CallingConvention = CallingConvention.Cdecl)] public static extern int lua_pcall(IntPtr L, int nargs, int nres, int errf);
    [DllImport(D, CallingConvention = CallingConvention.Cdecl)] public static extern void lua_getfield(IntPtr L, int idx, string k);
    [DllImport(D, CallingConvention = CallingConvention.Cdecl)] public static extern IntPtr lua_tolstring(IntPtr L, int idx, out UIntPtr len);
    [DllImport(D, CallingConvention = CallingConvention.Cdecl)] public static extern void lua_close(IntPtr L);
    public static string Run(string code) {
        IntPtr L = luaL_newstate();
        luaL_openlibs(L);
        UIntPtr n;
        if (luaL_loadstring(L, code) != 0 || lua_pcall(L, 0, 0, 0) != 0) {
            return "[host error] " + Marshal.PtrToStringAnsi(lua_tolstring(L, -1, out n)) + "\n[exit 2]";
        }
        lua_getfield(L, -10002, "RESULT"); // LUA_GLOBALSINDEX
        string s = Marshal.PtrToStringAnsi(lua_tolstring(L, -1, out n));
        lua_close(L);
        return s;
    }
}
"@
}

function Quote([string]$s) { "'" + $s.Replace('\', '/').Replace("'", "\'") + "'" }
$path = Quote ((Resolve-Path $Script).Path)
$argList = ($ScriptArgs | ForEach-Object { Quote $_ }) -join ', '
$boot = @"
local buf = {}
io.write = function(...) for i = 1, select('#', ...) do buf[#buf + 1] = tostring((select(i, ...))) end end
EXITCODE = 0
os.exit = function(c) EXITCODE = c or 0; error('__exit__', 0) end
arg = { [0] = $path, $argList }
local ok, err = pcall(dofile, $path)
if not ok and err ~= '__exit__' then buf[#buf + 1] = '\n[script error] ' .. tostring(err); EXITCODE = 2 end
RESULT = table.concat(buf) .. '\n[exit ' .. tostring(EXITCODE) .. ']'
"@
$result = [AkLuaHost]::Run($boot)
$code = 2
if ($result -match '\[exit (\d+)\]\s*$') { $code = [int]$Matches[1]; $result = $result -replace '\r?\n?\[exit \d+\]\s*$', '' }
Write-Output $result
exit $code
