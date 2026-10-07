# Synthetic process snapshots only; no installed service is stopped or started.
param([string]$WorkDirectory=$env:TEMP)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\launcher\start-voice.ps1')
$passed = New-Object Collections.Generic.List[string]
function Assert($Value, [string]$Label) { if (-not $Value) { throw ('Failed: ' + $Label) } }
function Fails([scriptblock]$Code, [string]$Label) {
    $failed=$false; try { & $Code | Out-Null } catch { $failed=$true }
    Assert $failed $Label
}
function Pass([string]$Name) { $passed.Add($Name) }
$paths = [pscustomobject]@{epicenterExe='C:\synthetic\epicenter.exe';bridgeEntry='C:\synthetic space\bridge.mjs';nodeExe='C:\Program Files\nodejs\node.exe';dshEntry='C:\synthetic\bin.js';dshPort=3080}
$time = [DateTime]::UtcNow.AddMinutes(-1)
function FakeProcess([int]$Id, [int]$Parent, [string]$Exe, [string]$Line, [int]$Seconds=0) {
    [pscustomobject]@{ProcessId=$Id;ParentProcessId=$Parent;Name=[IO.Path]::GetFileName($Exe);ExecutablePath=$Exe;CommandLine=$Line;CreationDate=$time.AddSeconds($Seconds)}
}
$bridge = FakeProcess 20 1 $paths.nodeExe ('"' + $paths.nodeExe + '" "' + $paths.bridgeEntry + '"')
$hostRoot = FakeProcess 30 1 $paths.epicenterExe ('"' + $paths.epicenterExe + '"')
$bun = FakeProcess 31 30 'C:\synthetic\bun.exe' 'bun run host' 1
$webview = FakeProcess 32 31 'C:\synthetic\webview.exe' 'webview' 2
$dsh = FakeProcess 40 1 $paths.nodeExe ('"' + $paths.nodeExe + '" "' + $paths.dshEntry + '" web')
$other = FakeProcess 50 1 $paths.nodeExe 'node other.js'
$script:all = @($bridge,$hostRoot,$bun,$webview,$dsh,$other)
$script:bridgePort = @(20); $script:dshPort=@(40)
function Get-VoiceProcesses { return $script:all }
function Get-Listener([int]$Port) { if ($Port -eq 39152) {return $script:bridgePort};return $script:dshPort }
$script:healthCalls=0; $script:health=$true
function Get-BridgeHealth($Config) { $script:healthCalls++; return $script:health }
Assert (Test-ScriptProcess $bridge $paths.nodeExe $paths.bridgeEntry) 'quoted-exact-entry'
$decoy = FakeProcess 21 1 $paths.nodeExe ('node other.js --label "' + $paths.bridgeEntry + '"')
Assert (-not (Test-ScriptProcess $decoy $paths.nodeExe $paths.bridgeEntry)) 'entry-in-option-is-not-ownership'
$prefix = FakeProcess 22 1 $paths.nodeExe ('node "' + $paths.bridgeEntry + '.other"')
Assert (-not (Test-ScriptProcess $prefix $paths.nodeExe $paths.bridgeEntry)) 'no-prefix-match'
Pass 'windows-argument-parsing-and-exact-script-position'
$state=Get-VoiceStatus $paths ([pscustomobject]@{})
Assert ($state.healthy -and $state.dsh -eq 'running' -and $state.hostPids[0] -eq 30) 'status'
Pass 'separate-host-bridge-dsh-status'
$script:bridgePort=@(50); $script:healthCalls=0
$state=Get-VoiceStatus $paths (New-BridgeConfig)
Assert ($state.conflict -and -not $state.healthy -and $script:healthCalls -eq 0) 'no-token-to-unknown-port'
Fails {Invoke-VoiceStop $paths} 'unrelated-port-refused'
Pass 'unknown-port-owner-blocks-stop-and-receives-no-health-token'
$script:bridgePort=@(20)
$inventory=Get-VoiceInventory $paths
$targets=@(Get-StopTargets $inventory)
Assert (($targets.ProcessId -join ',') -eq '20,30,31,32') 'captured-host-tree-only'
Pass 'captures-host-descendants-excludes-dsh-and-other-node'
$stale = FakeProcess 33 30 'C:\synthetic\old.exe' 'old' -1
$script:all += $stale
Assert (33 -notin @((Get-StopTargets (Get-VoiceInventory $paths)).ProcessId)) 'stale-parent-relation-excluded'
$stale.CreationDate=$null
Fails {Get-StopTargets (Get-VoiceInventory $paths)} 'unknown-child-creation-refused'
$script:all=@($bridge,$hostRoot,$bun,$webview,$dsh,$other)
Pass 'old-parent-pid-relations-excluded-missing-creation-refused'
$reused = FakeProcess 20 1 $paths.nodeExe $bridge.CommandLine 5
Assert (-not (Test-SameSnapshot $bridge $reused)) 'pid-reuse'
Assert (Test-SameSnapshot $bridge $bridge) 'stable-snapshot'
Pass 'same-pid-different-creation-time-refused'
$script:opened=New-Object Collections.Generic.List[int]
$script:killed=New-Object Collections.Generic.List[int]
$script:disposed=New-Object Collections.Generic.List[int]
$script:failAcquire=32
function Open-VerifiedProcess($Snapshot) {
    if ($Snapshot.ProcessId -eq $script:failAcquire) { Stop-Voice 'Synthetic identity change' }
    $script:opened.Add([int]$Snapshot.ProcessId)
    $handle=[pscustomobject]@{Id=[int]$Snapshot.ProcessId}
    $handle | Add-Member -MemberType ScriptMethod -Name Dispose -Value {$script:disposed.Add($this.Id)}
    return $handle
}
function Close-VerifiedProcess($Process) {
    $script:killed.Add($Process.Id)
    $script:all=@($script:all | Where-Object {$_.ProcessId -ne $Process.Id})
    $script:bridgePort=@($script:bridgePort | Where-Object {$_ -ne $Process.Id})
}
Fails {Invoke-VoiceStop $paths} 'all-acquired-before-stop'
Assert ($script:killed.Count -eq 0 -and $script:disposed.Count -eq 3) 'no-partial-stop-on-acquire-failure'
Pass 'acquisition-failure-before-any-stop-disposes-held-handles'
$script:failAcquire=-1; $script:opened.Clear(); $script:disposed.Clear()
Invoke-VoiceStop $paths | Out-Null
Assert (($script:killed -join ',') -eq '20,30,31,32' -and ($script:all.ProcessId -join ',') -eq '40,50') 'target-only-stop'
Assert ($script:disposed.Count -eq 4) 'dispose'
Invoke-VoiceStop $paths | Out-Null
Assert ($script:killed.Count -eq 4) 'idempotent-stop'
Pass 'stop-removes-selected-backend-tree-only-and-is-idempotent'
$script:all=@($dsh,$other); $script:bridgePort=@()
$state=Get-VoiceStatus $paths $null
Assert (-not $state.healthy -and $state.bridge -eq 'stopped' -and $state.dsh -eq 'running') 'stopped-status'
Pass 'stopped-backend-status-preserves-running-dsh'
$script:all=@($bridge,$hostRoot,$bun,$webview,$dsh,$other); $script:bridgePort=@(20)
$script:health=$false
$state=Get-VoiceStatus $paths ([pscustomobject]@{})
Assert (-not $state.healthy -and $state.bridge -eq 'running') 'degraded'
Pass 'running-but-unhealthy-distinguished'
$script:all += (FakeProcess 60 1 'C:\another\epicenter.exe' 'other host')
$script:killed.Clear()
Fails {Invoke-VoiceStop $paths} 'different-host'
Assert ($script:killed.Count -eq 0) 'host-conflict-stops-nothing'
Pass 'other-host-installation-blocks-mutations'
$script:all=@($dsh,$other); $script:bridgePort=@(); $script:health=$true
$script:started=New-Object Collections.Generic.List[string]
function Start-Worker($Paths,$Path,$Role,$StatusPath,$SkipBrowser) {
    $script:started.Add($Role)
    if ($Role -eq 'host') { $script:all += $hostRoot }
    if ($Role -eq 'bridge') { $script:all += $bridge; $script:bridgePort=@(20) }
}
function Start-Sleep {param($Milliseconds)}
function Invoke-VoiceEnsureBackend($Paths,$Config,$Path){
    # State reconciliation itself is covered by test_recovery_states.ps1.
    if(-not $script:health){Stop-Voice 'Synthetic component failure'}
    $inventory=Get-VoiceInventory $Paths
    if($inventory.hosts.Count -eq 0){Start-Worker $Paths $Path 'host' '' $true}
    if($inventory.bridges.Count -eq 0){Start-Worker $Paths $Path 'bridge' '' $true}
}
Invoke-VoiceBackendStart $paths ([pscustomobject]@{}) 'synthetic' | Out-Null
Assert (($script:started -join ',') -eq 'host,bridge' -and $script:all.ProcessId -contains 40) 'restart-backend-only'
Pass 'restart-starts-backend-and-validates-stable-health-without-dsh'
$script:health=$false; $script:started.Clear()
Fails {Invoke-VoiceBackendStart $paths ([pscustomobject]@{}) 'synthetic'} 'health-failure'
Assert ($script:started.Count -eq 0) 'failed-health-no-duplicate'
Pass 'health-failure-reports-failure-without-duplicate-start'
$Action='Start';$Stop=$false;$Restart=$true;$Status=$false;$Check=$false;$Configure=$false;$SetupOnly=$false;$NoBrowser=$false
Assert ((Resolve-LauncherAction) -eq 'Restart') 'restart-alias'
$Stop=$true
Fails {Resolve-LauncherAction} 'conflicting-aliases'
$Stop=$false;$Restart=$false;$Check=$true
Assert ((Resolve-LauncherAction) -eq 'Status') 'check-alias'
$SetupOnly=$true
Fails {Resolve-LauncherAction} 'status-config-refused'
Pass 'action-aliases-check-compatibility-and-conflicting-options'
$testProfile=Join-Path ([IO.Path]::GetFullPath($WorkDirectory)) ('voice-control-dispatch-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory((Join-Path $testProfile 'dsh-voice-bridge')) | Out-Null
$oldAppData=$env:APPDATA
try {
    $env:APPDATA=$testProfile
    $SettingsPath=Join-Path $testProfile 'paths.json'
    Write-JsonAtomic $SettingsPath $paths $null
    $brokenConfig=Join-Path $testProfile 'dsh-voice-bridge\config.json'
    [IO.File]::WriteAllText($brokenConfig,'{invalid')
    $Action='Stop';$Stop=$false;$Restart=$false;$Status=$false;$Check=$false;$Configure=$false;$SetupOnly=$false;$NoBrowser=$false
    Invoke-Launcher | Out-Null
    Assert ([IO.File]::ReadAllText($brokenConfig) -ceq '{invalid') 'stop-config-preserved'
    Pass 'stop-dispatch-with-invalid-config-and-missing-executables'
    $Action='Status';$script:LauncherExitCode=0
    Invoke-Launcher | Out-Null
    Assert ($script:LauncherExitCode -eq 2 -and [IO.File]::ReadAllText($brokenConfig) -ceq '{invalid') 'status-missing-key'
    Pass 'status-dispatch-works-with-invalid-config-and-reports-exit-two'
    $Action='Restart';$beforeKills=$script:killed.Count
    Fails {Invoke-Launcher} 'restart-prevalidation'
    Assert ($script:killed.Count -eq $beforeKills) 'no-stop-on-invalid-restart-paths'
    Pass 'restart-validates-executables-before-stopping'
} finally {
    $env:APPDATA=$oldAppData
    if(Test-Path -LiteralPath $SettingsPath){Remove-Item -LiteralPath $SettingsPath}
    if(Test-Path -LiteralPath (Join-Path $testProfile 'dsh-voice-bridge\config.json')){Remove-Item -LiteralPath (Join-Path $testProfile 'dsh-voice-bridge\config.json')}
    [IO.Directory]::Delete((Join-Path $testProfile 'dsh-voice-bridge'))
    [IO.Directory]::Delete($testProfile)
}
Write-Output (([ordered]@{ok=$true;tests=$passed;real_services_stopped=0;real_cloud_calls=0;microphone_used=$false} | ConvertTo-Json -Depth 5 -Compress))
