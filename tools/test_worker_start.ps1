# Synthetic helper failures only. No real process/service/cloud/microphone.
param([string]$WorkDirectory=$env:TEMP)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\launcher\start-voice.ps1')
$suite=Join-Path ([IO.Path]::GetFullPath($WorkDirectory)) ('worker-start-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($suite)|Out-Null
$paths=[pscustomobject]@{nodeExe='C:\synthetic\node.exe'}
$path=Join-Path $suite 'paths.json'
$script:mode='ok';$script:disposed=0
$privateValue='SYNTHETIC-private-'+[guid]::NewGuid().ToString('N')
function Start-Process {
    param($FilePath,$ArgumentList,$WindowStyle,[switch]$PassThru)
    if($script:mode -eq 'exception'){throw $privateValue}
    $exitCode=0;if($script:mode -eq 'exit'){$exitCode=1}
    $process=[pscustomobject]@{ExitCode=$exitCode}
    $process|Add-Member ScriptMethod WaitForExit {param($Milliseconds) return ($script:mode -ne 'timeout')}
    $process|Add-Member ScriptMethod Dispose {$script:disposed++}
    if($ArgumentList -match '--status "([^"]+)"'){
        $target=$Matches[1]
        if($script:mode -eq 'ok'){[IO.File]::WriteAllText($target,'{"ready":true,"pid":123}')}
        if($script:mode -eq 'notready'){[IO.File]::WriteAllText($target,'{"ready":false,"reason":"WorkerSpawnFailed"}')}
    }
    return $process
}
$passed=@()
try{
    Start-Worker $paths $path 'host' '' $true
    if(@(Get-ChildItem -LiteralPath $suite -Filter 'worker-*').Count -ne 0){throw 'Acknowledgement was not cleaned'}
    $passed+='spawn-acknowledgement-required-and-cleaned'
    foreach($case in @('exception','timeout','exit','missing','notready')){
        $script:mode=$case;$failure=$null
        try{Start-Worker $paths $path 'bridge' '' $true}catch{$failure=$_.Exception}
        if($null -eq $failure -or -not $failure.Data.Contains('VoiceLauncherSafe') -or $failure.Message.Contains($privateValue)){throw 'Unsafe/missing startup failure'}
        if(@(Get-ChildItem -LiteralPath $suite -Filter 'worker-*').Count -ne 0){throw 'Failure acknowledgement was not cleaned'}
        $passed+=('safe-failure-'+$case)
    }
    if($script:disposed -ne 5){throw 'Helper handles not disposed'}
    [ordered]@{ok=$true;tests=$passed;real_services_changed=0;cloud_calls=0} | ConvertTo-Json -Compress
}finally{
    Assert-HistoryTree $suite ([IO.Path]::GetFullPath($WorkDirectory))
    Remove-Item -LiteralPath $suite -Recurse -Force
}
