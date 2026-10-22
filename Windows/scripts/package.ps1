param(
    [ValidateSet('win-x64', 'win-arm64')][string]$Runtime = 'win-x64',
    [switch]$SkipChecks
)
$ErrorActionPreference = 'Stop'
$WindowsRoot = Split-Path $PSScriptRoot -Parent
$RepositoryRoot = Split-Path $WindowsRoot -Parent
$Version = '1.2.2'
$Publish = Join-Path $WindowsRoot "bin/publish/$Runtime"
$Dist = Join-Path $RepositoryRoot 'dist'
$Stage = Join-Path $Dist "MacPet-$Version-windows-$($Runtime.Replace('win-', ''))"
$Results = Join-Path $WindowsRoot "test-results/$Runtime"
New-Item -ItemType Directory -Force $Dist, $Results | Out-Null
& dotnet publish (Join-Path $WindowsRoot 'MacPet.Windows.csproj') -c Release -r $Runtime --self-contained true -p:PublishSingleFile=true -o $Publish
if ($LASTEXITCODE -ne 0) { throw 'Windows publish failed' }
$Executable = Join-Path $Publish 'MacPet.exe'
if (!(Test-Path $Executable)) { throw 'MacPet.exe missing' }
if (!$SkipChecks -and $Runtime -eq 'win-x64' -and [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq 'X64') {
    foreach ($Mode in @('verify-release', 'smoke-test')) {
        $Report = Join-Path $Results "$Mode.json"
        $Process = Start-Process -FilePath $Executable -ArgumentList @("--$Mode", '--report', "`"$Report`"") -Wait -PassThru
        if (!(Test-Path $Report)) { throw "$Mode did not produce a report (exit $($Process.ExitCode))" }
        $Result = Get-Content $Report -Raw | ConvertFrom-Json
        Get-Content $Report
        if ($Process.ExitCode -ne 0 -or !$Result.passed) { throw "$Mode failed" }
    }
}
if (Test-Path $Stage) { Remove-Item -LiteralPath $Stage -Recurse -Force }
New-Item -ItemType Directory -Force $Stage | Out-Null
Copy-Item (Join-Path $Publish '*') $Stage -Recurse
Copy-Item (Join-Path $WindowsRoot 'INSTALL.zh-CN.txt') (Join-Path $Stage '安装说明.txt')
Copy-Item (Join-Path $RepositoryRoot 'LICENSE') (Join-Path $Stage 'LICENSE.txt')
$Archive = "$Stage.zip"
Compress-Archive -Path (Join-Path $Stage '*') -DestinationPath $Archive -CompressionLevel Optimal -Force
$Hash = (Get-FileHash $Archive -Algorithm SHA256).Hash.ToLowerInvariant()
"$Hash  $(Split-Path $Archive -Leaf)" | Set-Content "$Archive.sha256" -Encoding ascii
Write-Output "Built $Archive"
