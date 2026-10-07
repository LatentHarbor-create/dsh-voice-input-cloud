# Windows PowerShell 5.1+. Process identity is checked before any termination.
function Get-VoiceProcesses {
    try { return @(Get-CimInstance Win32_Process -ErrorAction Stop) }
    catch { Stop-Voice 'Cannot inspect process identities. Check Windows permissions; no process was stopped.' }
}
function Get-WindowsArguments([string]$CommandLine) {
    if (-not ('VoiceLauncherArguments' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class VoiceLauncherArguments {
    [DllImport("shell32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern IntPtr CommandLineToArgvW(string commandLine, out int count);
    [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr memory);
    public static string[] Split(string commandLine) {
        int count; IntPtr memory = CommandLineToArgvW(commandLine, out count);
        if (memory == IntPtr.Zero) throw new InvalidOperationException();
        try {
            string[] args = new string[count];
            for (int i=0; i<count; i++) args[i] = Marshal.PtrToStringUni(Marshal.ReadIntPtr(memory, i*IntPtr.Size));
            return args;
        } finally { LocalFree(memory); }
    }
}
'@ | Out-Null
    }
    return [VoiceLauncherArguments]::Split($CommandLine)
}
function Test-ScriptProcess($Process, [string]$Executable, [string]$Entry) {
    if ((Get-Field $Process 'ExecutablePath' '') -ine $Executable) { return $false }
    $line = Get-Field $Process 'CommandLine' ''
    if (-not $line) { return $false }
    $arguments = @(Get-WindowsArguments $line)
    # Only the entry argument counts. A path in an unrelated option is not ownership.
    return ($arguments.Count -ge 2 -and $arguments[1] -ieq $Entry)
}
function Assert-ControlPaths($Paths) {
    foreach ($field in @('epicenterExe','bridgeEntry','nodeExe','dshEntry')) {
        $value = Get-Field $Paths $field ''
        if ($value -isnot [string] -or -not [IO.Path]::IsPathRooted($value)) {
            Stop-Voice 'Saved program paths are invalid. Configure them before controlling services.'
        }
        Set-Field $Paths $field ([IO.Path]::GetFullPath($value))
    }
    $port = Get-Field $Paths 'dshPort' 3080
    if ($port -isnot [int] -or $port -lt 1024 -or $port -gt 65535 -or $port -eq 39152) {
        Stop-Voice 'The saved DSH port is invalid. Configure it before controlling services.'
    }
}
function Get-VoiceInventory($Paths) {
    # Listener PIDs must be sampled before processes, so a newly started listener
    # is included in the process snapshot rather than called unidentified.
    $bridgeOwners = @(Get-Listener 39152)
    $dshOwners = @(Get-Listener $Paths.dshPort)
    $processes = @(Get-VoiceProcesses)
    $hosts = @($processes | Where-Object { (Get-Field $_ 'ExecutablePath' '') -ieq $Paths.epicenterExe })
    $bridges = @($processes | Where-Object { Test-ScriptProcess $_ $Paths.nodeExe $Paths.bridgeEntry })
    $bridgeIds = @($bridges | ForEach-Object { [int]$_.ProcessId })
    $bridgeConflict = @($bridgeOwners | Where-Object { $_ -notin $bridgeIds }).Count -gt 0
    $dshConflict = $false
    foreach ($owner in $dshOwners) {
        $matching = @($processes | Where-Object { [int]$_.ProcessId -eq $owner })
        if ($matching.Count -ne 1 -or -not (Test-ScriptProcess $matching[0] $Paths.nodeExe $Paths.dshEntry)) { $dshConflict = $true }
    }
    $hostName = [IO.Path]::GetFileName($Paths.epicenterExe)
    $hostConflict = @($processes | Where-Object {
        (Get-Field $_ 'Name' '') -in @('epicenter.exe', $hostName) -and
        (Get-Field $_ 'ExecutablePath' '') -ine $Paths.epicenterExe
    }).Count -gt 0
    return [pscustomobject]@{
        processes=$processes; hosts=$hosts; bridges=$bridges; bridgeOwners=$bridgeOwners
        dshOwners=$dshOwners; bridgeConflict=$bridgeConflict; hostConflict=$hostConflict; dshConflict=$dshConflict
    }
}
function Get-StableVoiceInventory($Paths) {
    for($attempt=0;$attempt -lt 3;$attempt++) {
        $inventory=Get-VoiceInventory $Paths
        if(-not ($inventory.bridgeConflict -or $inventory.hostConflict -or $inventory.dshConflict)){return $inventory}
        if($attempt -lt 2){Start-Sleep -Milliseconds 400}
    }
    return $inventory
}
function Assert-VoiceInventoryOwnership($Inventory,[bool]$IncludeDsh=$false) {
    if($Inventory.bridgeConflict){Stop-Voice ('Port 39152 belongs to an unidentified process (PID: '+($Inventory.bridgeOwners -join ', ')+'). No process was stopped. Run Status and check paths.json.')}
    if($Inventory.hostConflict){Stop-Voice 'A different Epicenter installation, or one whose identity is unreadable, is running. No process was stopped. Run Status and check the selected host path.'}
    if($IncludeDsh -and $Inventory.dshConflict){Stop-Voice ('The DSH port belongs to an unidentified process (PID: '+($Inventory.dshOwners -join ', ')+'). No process was stopped.')}
}
function Get-VoiceStatus($Paths, $Config) {
    $inventory = Get-StableVoiceInventory $Paths
    $health = $false
    # Never send the pairing token to an unrelated process occupying the port.
    if (-not $inventory.bridgeConflict -and $inventory.bridgeOwners.Count -gt 0 -and $null -ne $Config) {
        $health = Get-BridgeHealth $Config
    }
    $bridge = 'stopped'; $hostState = 'stopped'; $dsh = 'stopped'
    if ($inventory.bridges.Count -gt 0) { $bridge = 'running (not listening)' }
    if ($inventory.bridgeOwners.Count -gt 0 -and -not $inventory.bridgeConflict) { $bridge = 'running' }
    if ($inventory.hosts.Count -gt 0) { $hostState = 'running' }
    if ($inventory.dshOwners.Count -gt 0) { $dsh = 'running' }
    if ($inventory.bridgeConflict) { $bridge = 'conflict (unidentified port owner)' }
    if ($inventory.hostConflict) { $hostState = 'conflict (other or unidentified installation)' }
    if ($inventory.dshConflict) { $dsh = 'conflict (unidentified port owner)' }
    $hostHealth=$false
    if($inventory.hosts.Count -gt 0 -and -not $inventory.hostConflict){$hostHealth=Get-EpicenterHealth $Paths}
    return [pscustomobject]@{
        bridge=$bridge; host=$hostState; dsh=$dsh; healthy=($health -and -not $inventory.hostConflict -and $inventory.hosts.Count -gt 0 -and $inventory.bridges.Count -gt 0)
        bridgePids=@($inventory.bridges | ForEach-Object {[int]$_.ProcessId})
        hostPids=@($inventory.hosts | ForEach-Object {[int]$_.ProcessId})
        dshPids=@($inventory.dshOwners)
        conflict=($inventory.bridgeConflict -or $inventory.hostConflict -or $inventory.dshConflict)
        hostHealthy=$hostHealth
    }
}
function Show-VoiceStatus($Paths, $Config) {
    $state = Get-VoiceStatus $Paths $Config
    Write-Host ('Voice Bridge : ' + $state.bridge + ' | PID: ' + ($state.bridgePids -join ', '))
    Write-Host ('Epicenter    : ' + $state.host + ' | PID: ' + ($state.hostPids -join ', '))
    Write-Host ('DSH frontend : ' + $state.dsh + ' | PID: ' + ($state.dshPids -join ', '))
    if($state.hostHealthy){Write-Host 'Epicenter health: OK.'}else{Write-Host 'Epicenter health: NOT READY.'}
    if ($state.healthy) { Write-Host 'Voice backend health: OK.' }
    elseif ($null -eq $Config) { Write-Host 'Voice backend health: unavailable (local config missing or invalid).' }
    else { Write-Host 'Voice backend health: NOT READY.' }
    Write-Host 'Status is read-only. No recording or cloud request was made.'
    return $state
}
function Get-StopTargets($Inventory) {
    $targets = New-Object Collections.Generic.List[object]
    foreach ($process in @($Inventory.bridges) + @($Inventory.hosts)) {
        if ($null -eq (Get-Field $process 'CreationDate' $null)) { Stop-Voice 'A process creation time is unavailable. No process was stopped.' }
        $targets.Add($process)
    }
    # Capture host descendants while the parent still exists. Do not use taskkill /IM or /T.
    $parents = @($Inventory.hosts)
    while ($parents.Count -gt 0) {
        $next = New-Object Collections.Generic.List[object]
        foreach ($parent in $parents) {
            foreach ($child in $Inventory.processes) {
                if ([int]$child.ParentProcessId -ne [int]$parent.ProcessId) { continue }
                if ($null -eq (Get-Field $child 'CreationDate' $null)) {
                    Stop-Voice 'A host descendant identity is ambiguous. No process was stopped.'
                }
                # Windows keeps the original parent PID after parent exit. A child
                # older than this live parent belongs to an earlier PID incarnation.
                if ($child.CreationDate -lt $parent.CreationDate) { continue }
                if ([int]$child.ProcessId -notin @($targets | ForEach-Object {[int]$_.ProcessId})) {
                    $targets.Add($child); $next.Add($child)
                }
            }
        }
        $parents = @($next.ToArray())
    }
    return $targets.ToArray()
}
function Test-SameSnapshot($Before, $Now) {
    return ($null -ne $Now -and [int]$Before.ProcessId -eq [int]$Now.ProcessId -and
        $Before.CreationDate -eq $Now.CreationDate -and
        (Get-Field $Before 'ExecutablePath' '') -ieq (Get-Field $Now 'ExecutablePath' '') -and
        (Get-Field $Before 'CommandLine' '') -ceq (Get-Field $Now 'CommandLine' ''))
}
function Open-VerifiedProcess($Snapshot) {
    $process = $null
    try {
        $process = [Diagnostics.Process]::GetProcessById([int]$Snapshot.ProcessId)
        # Hold the OS handle before rechecking identity, preventing PID reuse from redirecting Kill().
        $null = $process.Handle
        $now = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$Snapshot.ProcessId) -ErrorAction Stop
        if (-not (Test-SameSnapshot $Snapshot $now) -or
            [Math]::Abs(($process.StartTime.ToUniversalTime() - $Snapshot.CreationDate.ToUniversalTime()).TotalMilliseconds) -gt 1) {
            Stop-Voice 'A process identity changed during inspection. Run the command again; it was not stopped.'
        }
        return $process
    } catch {
        if ($null -ne $process) { $process.Dispose() }
        # Already-exited processes are safe to skip, but inspection/identity failures are not.
        $current = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$Snapshot.ProcessId) -ErrorAction Stop
        if ($null -eq $current) { return $null }
        Stop-Voice 'Cannot safely acquire a selected process. No termination was attempted; run status and retry.'
    }
}
function Close-VerifiedProcess($Process) {
    if ($Process.HasExited) { return }
    $Process.Kill()
    if (-not $Process.WaitForExit(8000)) { Stop-Voice 'A selected service did not exit. Restart was cancelled.' }
}
function Stop-VerifiedVoiceTargets($Targets) {
    $handles = New-Object Collections.Generic.List[object]
    try {
        # Acquire and validate every handle before stopping any process.
        foreach ($target in $Targets) {
            $handle = Open-VerifiedProcess $target
            if ($null -ne $handle) { $handles.Add($handle) }
        }
        # Bridge first, then host and its captured descendants. DSH is never a stop target.
        foreach ($handle in $handles) { Close-VerifiedProcess $handle }
    } finally { foreach ($handle in $handles) { $handle.Dispose() } }
}
function Invoke-VoiceStop($Paths) {
    $inventory = Get-StableVoiceInventory $Paths
    Assert-VoiceInventoryOwnership $inventory
    Stop-VerifiedVoiceTargets @(Get-StopTargets $inventory)
    $remaining = Get-StableVoiceInventory $Paths
    if ($remaining.bridges.Count -gt 0 -or $remaining.hosts.Count -gt 0 -or $remaining.bridgeOwners.Count -gt 0) {
        Stop-Voice 'A voice service restarted or the bridge port is still occupied. Restart was cancelled; inspect status.'
    }
    Write-Host 'Voice Bridge and selected Epicenter host stopped. DSH frontend and its drafts were preserved.'
}
function Invoke-VoiceComponentStop($Paths,[ValidateSet('host','bridge')][string]$Role) {
    $inventory=Get-StableVoiceInventory $Paths
    Assert-VoiceInventoryOwnership $inventory
    $selected=[pscustomobject]@{processes=$inventory.processes;hosts=@();bridges=@()}
    if($Role -eq 'host'){$selected.hosts=$inventory.hosts}else{$selected.bridges=$inventory.bridges}
    Stop-VerifiedVoiceTargets @(Get-StopTargets $selected)
    $remaining=Get-StableVoiceInventory $Paths
    if(($Role -eq 'host' -and $remaining.hosts.Count -gt 0) -or
       ($Role -eq 'bridge' -and ($remaining.bridges.Count -gt 0 -or $remaining.bridgeOwners.Count -gt 0))) {
        Stop-Voice ('The '+$Role+' component did not stop. Run Status before retrying.')
    }
}
function Get-EpicenterHealth($Paths) {
    $response=$null
    try {
        $discoveryPath=Join-Path ([IO.Path]::GetDirectoryName((Get-VoiceBlobRoot))) 'voice-bridge.json'
        if(-not [IO.File]::Exists($discoveryPath)){return $false}
        $discovery=Read-JsonFile $discoveryPath
        $port=Get-Field $discovery 'port' 0
        $token=Get-Field $discovery 'token' ''
        if($port -isnot [int] -or $port -lt 1024 -or $port -gt 65535 -or $token -isnot [string] -or -not $token){return $false}
        $owners=@(Get-Listener $port)
        $hosts=@((Get-StableVoiceInventory $Paths).hosts | ForEach-Object {[int]$_.ProcessId})
        if($owners.Count -eq 0 -or @($owners | Where-Object {$_ -notin $hosts}).Count -gt 0){return $false}
        $request=[Net.HttpWebRequest]::Create('http://127.0.0.1:'+ $port +'/health')
        $request.Proxy=$null;$request.AllowAutoRedirect=$false;$request.Timeout=1500
        $request.Headers['Authorization']='Bearer '+$token
        $response=$request.GetResponse()
        $reader=New-Object IO.StreamReader($response.GetResponseStream())
        try{$health=$reader.ReadToEnd() | ConvertFrom-Json}finally{$reader.Dispose()}
        return ([int]$response.StatusCode -eq 200 -and (Get-Field $health 'ok' $false) -eq $true)
    }catch{return $false}finally{if($null -ne $response){$response.Dispose()}}
}
function Wait-VoiceComponentHealth($Paths,$Config,[string]$Role,[int]$Attempts=18) {
    for($attempt=0;$attempt -lt $Attempts;$attempt++) {
        $inventory=Get-StableVoiceInventory $Paths
        Assert-VoiceInventoryOwnership $inventory
        $healthy=$false
        if($Role -eq 'host'){$healthy=Get-EpicenterHealth $Paths}
        elseif($inventory.bridges.Count -gt 0 -and $inventory.bridgeOwners.Count -gt 0){$healthy=Get-BridgeHealth $Config}
        if($healthy){return $true}
        Start-Sleep -Milliseconds 400
    }
    return $false
}
function Invoke-VoiceEnsureBackend($Paths,$Config,[string]$Path) {
    $inventory=Get-StableVoiceInventory $Paths
    Assert-VoiceInventoryOwnership $inventory $true
    $script:LauncherStep='Ensure Epicenter host'
    if($inventory.hosts.Count -eq 0){
        Write-Host 'Epicenter: missing; starting.'
        Start-Worker $Paths $Path 'host' '' $true
    }elseif(Wait-VoiceComponentHealth $Paths $Config 'host' 3){
        Write-Host 'Epicenter: healthy; keeping existing process.'
    }else{
        Assert-NoActiveVoiceRecording $Paths
        Write-Host 'Epicenter: unresponsive; restarting only the verified host.'
        Invoke-VoiceComponentStop $Paths 'host'
        Start-Worker $Paths $Path 'host' '' $true
    }
    if(-not (Wait-VoiceComponentHealth $Paths $Config 'host')){Stop-Voice 'Epicenter did not become healthy. Bridge/DSH were not started; run Status and check the host/Bun installation.'}
    $script:LauncherStep='Ensure Voice Bridge'
    $inventory=Get-StableVoiceInventory $Paths
    Assert-VoiceInventoryOwnership $inventory $true
    if($inventory.bridges.Count -eq 0){
        Write-Host 'Voice Bridge: missing; starting.'
        Start-Worker $Paths $Path 'bridge' '' $true
    }elseif(Wait-VoiceComponentHealth $Paths $Config 'bridge' 3){
        Write-Host 'Voice Bridge: healthy; keeping existing process.'
    }else{
        Assert-NoActiveVoiceRecording $Paths
        Write-Host 'Voice Bridge: unresponsive; restarting only the verified bridge.'
        Invoke-VoiceComponentStop $Paths 'bridge'
        Start-Worker $Paths $Path 'bridge' '' $true
    }
    if(-not (Wait-VoiceComponentHealth $Paths $Config 'bridge')){Stop-Voice 'Voice Bridge did not become healthy. DSH was not started; run Status and check the local Bridge installation.'}
}
function Invoke-VoiceBackendStart($Paths, $Config, [string]$Path) {
    Invoke-VoiceEnsureBackend $Paths $Config $Path
    $script:LauncherStep = 'Wait for voice backend health'
    for ($attempt=0; $attempt -lt 35; $attempt++) {
        $state = Get-VoiceStatus $Paths $Config
        if ($state.healthy -and $state.hostPids.Count -gt 0) {
            Start-Sleep -Milliseconds 600
            $stable = Get-VoiceStatus $Paths $Config
            if ($stable.healthy -and ($stable.hostPids -join ',') -eq ($state.hostPids -join ',') -and
                ($stable.bridgePids -join ',') -eq ($state.bridgePids -join ',')) {
                Write-Host 'Voice backend ready. DSH frontend was not restarted; no browser was opened.'
                return
            }
        }
        Start-Sleep -Milliseconds 600
    }
    Stop-Voice 'Voice backend did not become stably healthy. Check status and local installation.'
}
