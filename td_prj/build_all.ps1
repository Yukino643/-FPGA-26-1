param([switch]$SynOnly, [string]$OutputDirectory)
$ErrorActionPreference='Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw '需要PowerShell 7' }
[Console]::OutputEncoding=[System.Text.UTF8Encoding]::new($false)
$OutputEncoding=[System.Text.UTF8Encoding]::new($false)
if (-not $OutputDirectory) { $OutputDirectory=Join-Path $PSScriptRoot '../build/720p/td' }
$buildArgs=@('-X','utf8',(Join-Path $PSScriptRoot 'build_native.py'),'--output',$OutputDirectory)
if ($SynOnly) { $buildArgs+='--syn-only' }
& 'D:/miniconda3/python.exe' @buildArgs
exit $LASTEXITCODE
