# Synthetic WAVs and fake service inventory only. No real recordings or services.
param([string]$WorkDirectory=$env:TEMP)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\launcher\start-voice.ps1')
$base=[IO.Path]::GetFullPath($WorkDirectory)
$suite=Join-Path $base ('voice-retention-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($suite)|Out-Null
$oldApp=$env:APPDATA;$oldOverride=$env:EPICENTER_DATA_DIR
$env:APPDATA=$suite;$env:EPICENTER_DATA_DIR=''
$passed=New-Object Collections.Generic.List[string]
function Assert($Value,[string]$Name){if(-not $Value){throw ('Failed: '+$Name)}}
function Fails([scriptblock]$Code,[string]$Name){$failed=$false;try{& $Code|Out-Null}catch{$failed=$true};Assert $failed $Name}
function Pass([string]$Name){$passed.Add($Name)}
$script:inventory=[pscustomobject]@{hosts=@();bridges=@();bridgeOwners=@();dshOwners=@();hostConflict=$false;bridgeConflict=$false;dshConflict=$false}
function Get-VoiceInventory($Paths){return $script:inventory}
$paths=[pscustomobject]@{bridgeEntry=(Join-Path $suite 'bridge\bridge.mjs');epicenterExe='C:\synthetic\epicenter.exe';nodeExe='C:\synthetic\node.exe';dshEntry='C:\synthetic\bin.js';dshPort=3080}
[IO.Directory]::CreateDirectory((Split-Path $paths.bridgeEntry))|Out-Null
$extra=Join-Path $suite 'local-bridge-private.log'
Set-Field $paths 'voiceHistoryLogs' @($extra)
$root=Get-VoiceBlobRoot
[IO.Directory]::CreateDirectory($root)|Out-Null
function Add-Wav([char]$Letter,[bool]$Valid=$true,[bool]$Owned=$true){
    $dir=Join-Path $root ('blob_' + ([string]$Letter * 21))
    [IO.Directory]::CreateDirectory($dir)|Out-Null
    $bytes=[Text.Encoding]::ASCII.GetBytes('RIFF0000WAVE')
    if(-not $Valid){$bytes=[Text.Encoding]::ASCII.GetBytes('NOPE0000WAVE')}
    [IO.File]::WriteAllBytes((Join-Path $dir 'data'),$bytes)
    [IO.File]::WriteAllText((Join-Path $dir 'metadata.json'),'{"contentType":"audio/wav","size":12}')
    if($Owned){
        $owners=Join-Path $suite 'dsh-voice-bridge\recording-owners'
        [IO.Directory]::CreateDirectory($owners)|Out-Null
        Write-JsonAtomic (Join-Path $owners ((Split-Path $dir -Leaf)+'.json')) ([pscustomobject]@{version=1;owner='voice-bridge';blobId=(Split-Path $dir -Leaf);blobRoot=$root}) $null
    }
    return $dir
}
try{
    $configPath=Join-Path $suite 'dsh-voice-bridge\config.json'
    $cfg=New-BridgeConfig
    $cfg.transcription.apiKey=[guid]::NewGuid().ToString('N')
    Write-JsonAtomic $configPath $cfg $null
    $configBefore=[IO.File]::ReadAllText($configPath)
    $statePath=Join-Path $suite 'dsh-voice-bridge\state.json'
    [IO.File]::WriteAllText($statePath,'{"recordingId":null}')
    $one=Add-Wav 'a';$two=Add-Wav 'b'
    $unowned=Add-Wav 'u' $true $false
    $other=Join-Path $root ('blob_' + ('z'*21));[IO.Directory]::CreateDirectory($other)|Out-Null
    [IO.File]::WriteAllText((Join-Path $other 'metadata.json'),'{"contentType":"application/octet-stream","size":9}')
    [IO.File]::WriteAllText((Join-Path $other 'data'),'unrelated')
    [IO.File]::WriteAllText((Join-Path (Split-Path $paths.bridgeEntry) 'bridge.log'),'synthetic history')
    [IO.File]::WriteAllText($extra,'synthetic history')
    $staging=Join-Path $root ('.staging\rust\blob_' + ('a'*21) + '-123-synthetic');[IO.Directory]::CreateDirectory($staging)|Out-Null
    [IO.File]::WriteAllText((Join-Path $staging 'data'),'partial synthetic capture')
    $unownedStaging=Join-Path $root ('.staging\rust\blob_' + ('u'*21) + '-123-synthetic');[IO.Directory]::CreateDirectory($unownedStaging)|Out-Null
    [IO.File]::WriteAllText((Join-Path $unownedStaging 'data'),'unrelated partial capture')
    Invoke-VoiceHistoryCleanup $paths | Out-Null
    Assert (-not(Test-Path -LiteralPath $one) -and -not(Test-Path -LiteralPath $two)) 'wav-deleted'
    Assert ((Get-Content -LiteralPath (Join-Path $other 'data') -Raw) -eq 'unrelated') 'non-audio-kept'
    Assert ((Test-Path -LiteralPath $unowned) -and (Test-Path -LiteralPath $unownedStaging)) 'unowned-audio-and-staging-kept'
    Assert ([IO.File]::ReadAllText($configPath) -ceq $configBefore) 'config-kept'
    Assert (-not(Test-Path -LiteralPath $extra) -and -not(Test-Path -LiteralPath $statePath) -and -not(Test-Path -LiteralPath $staging)) 'logs-state-staging-deleted'
    Assert ($script:LastVoiceCleanup.recordings -eq 2 -and $script:LastVoiceCleanup.logs -eq 2 -and $script:LastVoiceCleanup.preservedWavs -eq 1) 'counts'
    Pass 'owned-wavs-cleared-unowned-wavs-staging-non-audio-and-config-preserved'
    Invoke-VoiceHistoryCleanup $paths | Out-Null
    Assert ($script:LastVoiceCleanup.recordings -eq 0) 'repeat-empty-cleanup'
    Pass 'empty-history-cleanup-is-idempotent'
    $one=Add-Wav 'a';$script:inventory.hosts=@(1)
    Fails {Invoke-VoiceHistoryCleanup $paths} 'running-host-refused'
    Assert (Test-Path -LiteralPath $one) 'running-history-kept'
    [IO.File]::WriteAllText($statePath,'{"recordingId":"synthetic-active-capture"}')
    Fails {Assert-NoActiveVoiceRecording $paths} 'active-recording-refused'
    Assert (Test-Path -LiteralPath $one) 'active-history-kept'
    Pass 'running-backend-and-active-capture-block-cleanup'
    $script:inventory.hosts=@();Remove-Item -LiteralPath $statePath
    $script:inventory.bridges=@(1)
    [IO.File]::WriteAllText($statePath,'{"recordingId":"synthetic-orphan-after-host-exit"}')
    Assert-NoActiveVoiceRecording $paths
    $script:inventory.bridges=@();Remove-Item -LiteralPath $statePath
    $bad=Add-Wav 'b' $false
    Fails {Invoke-VoiceHistoryCleanup $paths} 'bad-header-refused'
    Assert ((Test-Path -LiteralPath $one) -and (Test-Path -LiteralPath $bad)) 'all-before-any-delete'
    Remove-Item -LiteralPath $bad -Recurse
    [IO.File]::WriteAllText((Join-Path $one 'unexpected.txt'),'unrelated')
    Fails {Invoke-VoiceHistoryCleanup $paths} 'unexpected-layout-refused'
    Remove-Item -LiteralPath (Join-Path $one 'unexpected.txt')
    Pass 'invalid-wav-and-extra-files-refused-before-any-deletion'
    Fails {Assert-ContainedHistoryPath (Join-Path $suite 'outside') $root} 'escape-refused'
    Set-Field $paths 'voiceHistoryLogs' @($configPath)
    Fails {Invoke-VoiceHistoryCleanup $paths} 'config-as-log-refused'
    Set-Field $paths 'voiceHistoryLogs' @($extra)
    Pass 'path-escape-and-non-log-target-refused'
    $ownerMarker=Join-Path $suite ('dsh-voice-bridge\recording-owners\blob_' + ('a'*21) + '.json')
    $markerBefore=[IO.File]::ReadAllText($ownerMarker)
    $marker=Read-JsonFile $ownerMarker;Set-Field $marker 'blobRoot' (Join-Path $suite 'different-store')
    [IO.File]::WriteAllText($ownerMarker,($marker | ConvertTo-Json -Compress))
    Assert ((Get-VoiceHistoryPlan $paths).records.Count -eq 0) 'different-store-not-selected'
    Assert (Test-Path -LiteralPath $ownerMarker) 'different-store-marker-preserved'
    Set-Field $marker 'owner' 'other-application';[IO.File]::WriteAllText($ownerMarker,($marker | ConvertTo-Json -Compress))
    Fails {Invoke-VoiceHistoryCleanup $paths} 'conflicting-owner-refused'
    Assert (Test-Path -LiteralPath $one) 'conflicting-owner-no-delete'
    [IO.File]::WriteAllText($ownerMarker,$markerBefore)
    Pass 'markers-bound-to-owner-id-and-exact-data-store'
    $outside=Join-Path $suite 'outside';[IO.Directory]::CreateDirectory($outside)|Out-Null
    $sentinel=Join-Path $outside 'keep.txt';[IO.File]::WriteAllText($sentinel,'keep')
    $link=Join-Path $root ('blob_' + ('j'*21))
    New-Item -ItemType Junction -Path $link -Target $outside | Out-Null
    try{Fails {Invoke-VoiceHistoryCleanup $paths} 'junction-refused';Assert (Test-Path -LiteralPath $sentinel) 'outside-kept'}
    finally{[IO.Directory]::Delete($link)}
    Pass 'junction-refused-with-external-target-preserved'
    $SettingsPath=Join-Path $suite 'paths.json';Write-JsonAtomic $SettingsPath $paths $null
    function Assert-Paths($Paths) {} # No synthetic executable is launched.
    $script:order=New-Object Collections.Generic.List[string]
    function Invoke-VoiceStop($Paths){$script:order.Add('stop')}
    function Invoke-Startup($Paths,$Config,$Path,$InspectOnly,$SkipBrowser){
        Assert (-not(Test-Path -LiteralPath $one)) 'cleanup-before-start'
        $script:order.Add('start')
    }
    function Invoke-VoiceBackendStart($Paths,$Config,$Path){
        Assert (-not(Test-Path -LiteralPath $one)) 'cleanup-before-restart'
        $script:order.Add('restart')
    }
    $Action='Start';$Stop=$false;$Restart=$false;$Status=$false;$Check=$false;$Configure=$false;$SetupOnly=$false;$NoBrowser=$false
    Invoke-Launcher | Out-Null
    Assert (($script:order -join ',') -eq 'start') 'cold-start-without-unnecessary-stop'
    $one=Add-Wav 'a';$script:order.Clear();$Action='Restart'
    Invoke-Launcher | Out-Null
    Assert (($script:order -join ',') -eq 'stop,restart') 'restart-order'
    Assert ([IO.File]::ReadAllText($configPath) -ceq $configBefore) 'final-config-kept'
    Pass 'both-start-and-restart-clean-before-launch-with-config-unchanged'
    Write-Output (([ordered]@{ok=$true;tests=$passed;real_recordings_deleted=0;real_services_changed=0;cloud_calls=0} | ConvertTo-Json -Depth 5 -Compress))
}finally{
    $env:APPDATA=$oldApp;$env:EPICENTER_DATA_DIR=$oldOverride
    Assert-HistoryTree $suite $base
    Remove-Item -LiteralPath $suite -Recurse -Force
}
