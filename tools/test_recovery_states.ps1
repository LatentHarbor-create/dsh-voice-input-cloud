# Synthetic state matrix: absent, healthy, unresponsive, late exit and conflicts.
param([string]$WorkDirectory=$env:TEMP)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\launcher\start-voice.ps1')
$suite=Join-Path ([IO.Path]::GetFullPath($WorkDirectory)) ('recovery-states-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($suite)|Out-Null
$paths=[pscustomobject]@{epicenterExe='C:\synthetic\epicenter.exe';nodeExe='C:\synthetic\node.exe';bridgeEntry='C:\synthetic\bridge.mjs';dshEntry='C:\synthetic\bin.js';dshPort=3080}
$cfg=New-BridgeConfig
$script:hostUp=$false;$script:bridgeUp=$false;$script:dshUp=$false
$script:hostGood=$true;$script:bridgeGood=$true;$script:failRole=''
$script:conflict=$false;$script:transientConflict=0;$script:purges=0
$script:events=New-Object Collections.Generic.List[string]
function Assert($Condition,$Name){if(-not $Condition){throw ('Failed: '+$Name)}}
function Fails([scriptblock]$Code,$Name){$failed=$false;try{& $Code|Out-Null}catch{$failed=$true};Assert $failed $Name}
function Start-Sleep {param($Milliseconds)}
function Get-VoiceInventory($Paths){
    $conflict=$script:conflict
    if($script:transientConflict -gt 0){$script:transientConflict--;$conflict=$true}
    return [pscustomobject]@{hosts=@(if($script:hostUp){[pscustomobject]@{ProcessId=30}});bridges=@(if($script:bridgeUp){[pscustomobject]@{ProcessId=20}});bridgeOwners=@(if($script:bridgeUp){20});dshOwners=@(if($script:dshUp){40});bridgeConflict=$conflict;hostConflict=$false;dshConflict=$false;processes=@()}
}
function Get-EpicenterHealth($Paths){return ($script:hostUp -and $script:hostGood)}
function Get-BridgeHealth($Config){return ($script:hostUp -and $script:hostGood -and $script:bridgeUp -and $script:bridgeGood)}
function Assert-PortOwner($Port,$Entry,$NodeExe){if($Port -eq 39152){return $script:bridgeUp};return $script:dshUp}
function Start-Worker($Paths,$Path,$Role,$StatusPath,$SkipBrowser){
    $script:events.Add('start-'+$Role)
    if($Role -eq 'host'){$script:hostUp=$true;$script:hostGood=($script:failRole -ne 'host')}
    if($Role -eq 'bridge'){Assert (Get-EpicenterHealth $Paths) 'host-health-before-bridge';$script:bridgeUp=$true;$script:bridgeGood=($script:failRole -ne 'bridge')}
    if($Role -eq 'dsh'){Assert (Get-BridgeHealth $cfg) 'backend-health-before-dsh';$script:dshUp=$true;[IO.File]::WriteAllText($StatusPath,'{"ready":true,"browserOpened":false}')}
}
function Invoke-VoiceComponentStop($Paths,$Role){
    $script:events.Add('stop-'+$Role)
    if($Role -eq 'host'){$script:hostUp=$false}else{$script:bridgeUp=$false}
}
function Assert-NoActiveVoiceRecording($Paths){if($script:active){Stop-Voice 'Synthetic active capture'}}
function Assert-Paths($Paths){}
function Invoke-VoiceHistoryCleanup($Paths){Assert (-not $script:hostUp -and -not $script:bridgeUp) 'cleanup-only-fully-stopped';$script:purges++}
$script:active=$false
$oldApp=$env:APPDATA;$env:APPDATA=$suite
$SettingsPath=Join-Path $suite 'paths.json';Write-JsonAtomic $SettingsPath $paths $null
$cfg.transcription.apiKey=[guid]::NewGuid().ToString('N')
Write-JsonAtomic (Join-Path $suite 'dsh-voice-bridge\config.json') $cfg $null
$NoBrowser=$true;$Action='Start';$Stop=$false;$Restart=$false;$Status=$false;$Check=$false;$Configure=$false;$SetupOnly=$false
$passed=New-Object Collections.Generic.List[string]
try{
    for($mask=0;$mask -lt 8;$mask++){
        $script:hostUp=($mask -band 1) -ne 0;$script:bridgeUp=($mask -band 2) -ne 0;$script:dshUp=($mask -band 4) -ne 0
        $script:hostGood=$true;$script:bridgeGood=$true;$script:events.Clear();$script:purges=0
        $expected=@();if(-not $script:hostUp){$expected+='start-host'};if(-not $script:bridgeUp){$expected+='start-bridge'};if(-not $script:dshUp){$expected+='start-dsh'}
        Invoke-Launcher | Out-Null
        Assert (($script:events -join ',') -eq ($expected -join ',')) ('state-'+$mask+'-only-missing-in-dependency-order')
        Assert ($script:purges -eq [int](($mask -band 3) -eq 0)) ('state-'+$mask+'-cleanup-policy')
        Assert ($script:hostUp -and $script:bridgeUp -and $script:dshUp) ('state-'+$mask+'-all-ready')
        $passed.Add('presence-matrix-'+$mask)
    }
    $script:hostGood=$false;$script:events.Clear()
    Invoke-Launcher | Out-Null
    Assert (($script:events -join ',') -eq 'stop-host,start-host') 'recover-only-bad-host'
    $passed.Add('unresponsive-host-recovered-with-bridge-and-dsh-preserved')
    $script:bridgeGood=$false;$script:events.Clear()
    Invoke-Launcher | Out-Null
    Assert (($script:events -join ',') -eq 'stop-bridge,start-bridge') 'recover-only-bad-bridge'
    $passed.Add('unresponsive-bridge-recovered-with-host-and-dsh-preserved')
    $script:transientConflict=1;$script:events.Clear()
    Invoke-Launcher | Out-Null
    Assert ($script:events.Count -eq 0) 'transient-conflict-rechecked-without-stopping'
    $passed.Add('transient-process-snapshot-conflict-rechecked')
    $script:conflict=$true
    Fails {Invoke-Launcher} 'real-conflict-refused'
    Assert ($script:events.Count -eq 0) 'real-conflict-no-mutations'
    $script:conflict=$false;$passed.Add('persistent-unidentified-owner-refused-without-mutation')
    $script:hostUp=$false;$script:bridgeUp=$false;$script:dshUp=$false;$script:failRole='host';$script:events.Clear()
    Fails {Invoke-Launcher} 'host-does-not-start'
    Assert (($script:events -join ',') -eq 'start-host') 'host-failure-blocks-downstream'
    $passed.Add('host-never-ready-prevents-bridge-and-dsh-start')
    $script:hostGood=$true;$script:failRole='bridge';$script:events.Clear()
    Fails {Invoke-Launcher} 'bridge-does-not-start'
    Assert (($script:events -join ',') -eq 'start-bridge') 'bridge-failure-blocks-dsh'
    $passed.Add('bridge-never-ready-prevents-dsh-start')
    $script:failRole='';$script:active=$true;$script:events.Clear()
    Fails {Invoke-Launcher} 'active-recording-blocks-destructive-recovery'
    Assert ($script:events.Count -eq 0) 'active-no-stop'
    $passed.Add('active-capture-blocks-restart-of-unresponsive-component')
    [ordered]@{ok=$true;tests=$passed;real_services_changed=0;microphone_used=$false;cloud_calls=0} | ConvertTo-Json -Compress
}finally{
    $env:APPDATA=$oldApp
    Assert-HistoryTree $suite ([IO.Path]::GetFullPath($WorkDirectory));Remove-Item -LiteralPath $suite -Recurse -Force
}
