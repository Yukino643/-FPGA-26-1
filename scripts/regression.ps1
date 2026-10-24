param([switch]$Full, [switch]$SimOnly, [switch]$ReuseVerified, [string]$Filter)
$ErrorActionPreference='Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw '需要PowerShell 7' }
[Console]::OutputEncoding=[System.Text.UTF8Encoding]::new($false)
$OutputEncoding=[System.Text.UTF8Encoding]::new($false)
$regArgs=@('-X','utf8',(Join-Path $PSScriptRoot 'regression_native.py'))
if ($Full) { $regArgs+='--full' }
if ($SimOnly) { $regArgs+='--sim-only' }
if ($ReuseVerified) { $regArgs+='--reuse' }
if ($Filter) { $regArgs+=@('--filter',$Filter) }
& 'D:/miniconda3/python.exe' @regArgs
exit $LASTEXITCODE
