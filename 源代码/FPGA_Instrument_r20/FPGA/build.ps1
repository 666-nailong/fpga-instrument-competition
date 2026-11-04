# Build from an isolated directory with Gowin EDA V1.9.12.03.
# Example: ./build.ps1 -OutDir D:/Temp/instrument_build -GowinSh /path/to/gw_sh.exe
param(
    [Parameter(Mandatory)][string]$OutDir,
    [string]$GowinSh='gw_sh.exe'
)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $OutDir){throw 'Choose a fresh build directory'}
if(!(Get-Command $GowinSh -ErrorAction SilentlyContinue)){throw 'Pass the installed Gowin IDE/bin/gw_sh.exe path using -GowinSh'}
New-Item -ItemType Directory -Path $OutDir | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot src) -Destination $OutDir -Recurse
Copy-Item -LiteralPath (Join-Path $PSScriptRoot build.tcl) -Destination $OutDir
Push-Location $OutDir
try{
    & $GowinSh build.tcl
    if($LASTEXITCODE -ne 0){throw 'Gowin build failed'}
}finally{Pop-Location}
