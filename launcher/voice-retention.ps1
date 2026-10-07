# Remove only marker-owned plugin history while the selected backend is stopped.
function Assert-NoReparsePath([string]$Path) {
    $current=[IO.Path]::GetFullPath($Path)
    while($current) {
        if(Test-Path -LiteralPath $current) {
            if(((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                Stop-Voice 'A history path uses a symbolic link or junction. Cleanup was refused.'
            }
        }
        $parent=[IO.Path]::GetDirectoryName($current.TrimEnd('\'))
        if(-not $parent -or $parent -eq $current){break}
        $current=$parent
    }
}
function Get-VoiceBlobRoot {
    $dataRoot=Join-Path $env:APPDATA 'so.epicenter'
    if(-not [string]::IsNullOrWhiteSpace($env:EPICENTER_DATA_DIR)) {
        if(-not [IO.Path]::IsPathRooted($env:EPICENTER_DATA_DIR)){Stop-Voice 'Epicenter data root must be absolute; cleanup was refused.'}
        $dataRoot=[IO.Path]::GetFullPath($env:EPICENTER_DATA_DIR)
    }
    $root=[IO.Path]::GetFullPath((Join-Path $dataRoot 'blobs'))
    Assert-NoReparsePath $root
    return $root
}
function Assert-ContainedHistoryPath([string]$Path,[string]$Root) {
    $full=[IO.Path]::GetFullPath($Path)
    $prefix=[IO.Path]::GetFullPath($Root).TrimEnd('\')+'\'
    if(-not $full.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) {
        Stop-Voice 'A history target is outside its intended directory. Cleanup was refused.'
    }
    Assert-NoReparsePath $full
}
function Assert-WavHistoryDirectory([string]$Directory,[string]$Root) {
    Assert-ContainedHistoryPath $Directory $Root
    if([IO.Path]::GetFileName($Directory) -notmatch '\Ablob_[a-z0-9]{21}\z'){Stop-Voice 'An audio blob directory has an unexpected name; cleanup was refused.'}
    $entries=@(Get-ChildItem -LiteralPath $Directory -Force)
    if($entries.Count -ne 2){Stop-Voice 'An audio blob contains unexpected files; cleanup was refused.'}
    foreach($entry in $entries) {
        if($entry.PSIsContainer -or $entry.Name -notin @('data','metadata.json')){Stop-Voice 'An audio blob has an unexpected layout; cleanup was refused.'}
        Assert-ContainedHistoryPath $entry.FullName $Directory
    }
    $metadata=Read-JsonFile (Join-Path $Directory 'metadata.json')
    if((Get-Field $metadata 'contentType' '') -ne 'audio/wav'){Stop-Voice 'A selected history file is no longer WAV audio; cleanup was refused.'}
    $data=Join-Path $Directory 'data'
    $stream=[IO.File]::OpenRead($data)
    try {
        $header=New-Object byte[] 12
        if($stream.Read($header,0,12) -ne 12 -or [Text.Encoding]::ASCII.GetString($header,0,4) -ne 'RIFF' -or
           [Text.Encoding]::ASCII.GetString($header,8,4) -ne 'WAVE'){Stop-Voice 'A selected audio file is not a WAV; cleanup was refused.'}
        if((Get-Field $metadata 'size' -1) -ne $stream.Length){Stop-Voice 'An audio blob size changed; cleanup was refused.'}
        return $stream.Length
    } finally {$stream.Dispose()}
}
function Assert-HistoryTree([string]$Path,[string]$Root) {
    Assert-ContainedHistoryPath $Path $Root
    $pending=New-Object Collections.Generic.Queue[string]
    $pending.Enqueue($Path)
    while($pending.Count -gt 0) {
        foreach($entry in @(Get-ChildItem -LiteralPath $pending.Dequeue() -Force)) {
            Assert-ContainedHistoryPath $entry.FullName $Path
            if($entry.PSIsContainer){$pending.Enqueue($entry.FullName)}
        }
    }
}
function Get-VoiceHistoryPlan($Paths) {
    $root=Get-VoiceBlobRoot
    $records=New-Object Collections.Generic.List[string]
    $markers=New-Object Collections.Generic.List[string]
    $owned=@{}
    $ownerRoot=Join-Path $env:APPDATA 'dsh-voice-bridge\recording-owners'
    Assert-NoReparsePath $ownerRoot
    if(Test-Path -LiteralPath $ownerRoot) {
        if(-not (Get-Item -LiteralPath $ownerRoot).PSIsContainer){Stop-Voice 'The ownership store is not a directory. Cleanup was refused.'}
        foreach($entry in @(Get-ChildItem -LiteralPath $ownerRoot -Force)) {
            Assert-ContainedHistoryPath $entry.FullName $ownerRoot
            if($entry.PSIsContainer -or $entry.Name -notmatch '\A(blob_[a-z0-9]{21})\.json\z') {
                Stop-Voice 'An ownership marker has an unexpected layout. Cleanup was refused.'
            }
            $id=$Matches[1]
            $marker=Read-JsonFile $entry.FullName
            if((Get-Field $marker 'version' 0) -ne 1 -or (Get-Field $marker 'owner' '') -ne 'voice-bridge' -or
               (Get-Field $marker 'blobId' '') -cne $id) {Stop-Voice 'An ownership marker is invalid. Cleanup was refused.'}
            $markedRoot=Get-Field $marker 'blobRoot' ''
            if(-not [IO.Path]::IsPathRooted($markedRoot)){Stop-Voice 'An ownership store path is invalid. Cleanup was refused.'}
            # Keep markers for a different Epicenter installation/data override.
            if([IO.Path]::GetFullPath($markedRoot).TrimEnd('\') -ine $root.TrimEnd('\')){continue}
            $owned[$id]=$true
            $markers.Add($entry.FullName)
        }
    }
    $bytes=[long]0
    $preservedWavs=0
    if(Test-Path -LiteralPath $root) {
        foreach($directory in @(Get-ChildItem -LiteralPath $root -Directory -Force)) {
            if($directory.Name -notmatch '\Ablob_[a-z0-9]{21}\z'){continue}
            Assert-ContainedHistoryPath $directory.FullName $root
            $metadataPath=Join-Path $directory.FullName 'metadata.json'
            if(-not [IO.File]::Exists($metadataPath)){continue}
            Assert-ContainedHistoryPath $metadataPath $directory.FullName
            $metadata=Read-JsonFile $metadataPath
            if((Get-Field $metadata 'contentType' '') -ne 'audio/wav'){continue}
            if(-not $owned.ContainsKey($directory.Name)){$preservedWavs++;continue}
            $bytes += Assert-WavHistoryDirectory $directory.FullName $root
            $records.Add($directory.FullName)
        }
    }
    $stagingRoot=Join-Path $root '.staging\rust'
    $staging=New-Object Collections.Generic.List[string]
    Assert-NoReparsePath $stagingRoot
    if(Test-Path -LiteralPath $stagingRoot) {
        foreach($entry in @(Get-ChildItem -LiteralPath $stagingRoot -Directory -Force)) {
            if($entry.Name -match '\A(blob_[a-z0-9]{21})-[0-9]+-[a-zA-Z0-9-]+\z' -and $owned.ContainsKey($Matches[1])) {
                Assert-HistoryTree $entry.FullName $stagingRoot
                $staging.Add($entry.FullName)
            }
        }
    }
    $logs=New-Object Collections.Generic.List[string]
    $candidates=@((Join-Path ([IO.Path]::GetDirectoryName($Paths.bridgeEntry)) 'bridge.log'))
    $extraLogs=Get-Field $Paths 'voiceHistoryLogs' @()
    foreach($extra in $extraLogs) {
        if($extra -isnot [string] -or -not [IO.Path]::IsPathRooted($extra) -or
           [IO.Path]::GetFileName($extra) -notin @('bridge.log','local-bridge-private.log')) {
            Stop-Voice 'An extra voice history log path is invalid. Cleanup was refused.'
        }
        $candidates += [IO.Path]::GetFullPath($extra)
    }
    foreach($log in @($candidates | Select-Object -Unique)) {
        Assert-NoReparsePath $log
        if(Test-Path -LiteralPath $log) {
            if((Get-Item -LiteralPath $log -Force).PSIsContainer){Stop-Voice 'A voice history log path is a directory. Cleanup was refused.'}
            $logs.Add($log)
        }
    }
    $state=Join-Path $env:APPDATA 'dsh-voice-bridge\state.json'
    Assert-NoReparsePath $state
    if((Test-Path -LiteralPath $state) -and (Get-Item -LiteralPath $state -Force).PSIsContainer) {
        Stop-Voice 'The voice tracking state path is a directory. Cleanup was refused.'
    }
    return [pscustomobject]@{root=$root;records=$records.ToArray();bytes=$bytes;staging=$staging.ToArray();stagingRoot=$stagingRoot;logs=$logs.ToArray();state=$state;markers=$markers.ToArray();ownerRoot=$ownerRoot;preservedWavs=$preservedWavs}
}
function Assert-NoActiveVoiceRecording($Paths) {
    $inventory=Get-VoiceInventory $Paths
    $statePath=Join-Path $env:APPDATA 'dsh-voice-bridge\state.json'
    # Native capture cannot remain active after the selected host has exited.
    if($inventory.hosts.Count -gt 0 -and [IO.File]::Exists($statePath)) {
        $state=Read-JsonFile $statePath
        if(-not [string]::IsNullOrWhiteSpace((Get-Field $state 'recordingId' ''))) {
            Stop-Voice 'Finish or cancel the current recording before Start/Restart. History was not cleared.'
        }
    }
}
function Invoke-VoiceHistoryCleanup($Paths) {
    $inventory=Get-VoiceInventory $Paths
    if($inventory.hosts.Count -gt 0 -or $inventory.bridges.Count -gt 0 -or $inventory.bridgeOwners.Count -gt 0 -or
       (Get-Field $inventory 'hostConflict' $false)) {
        Stop-Voice 'Stop the selected voice backend before clearing history. No history was removed.'
    }
    $plan=Get-VoiceHistoryPlan $Paths
    foreach($directory in $plan.records) {
        [void](Assert-WavHistoryDirectory $directory $plan.root)
        Remove-Item -LiteralPath $directory -Recurse -Force
    }
    foreach($staging in $plan.staging) {
        Assert-HistoryTree $staging $plan.stagingRoot
        Remove-Item -LiteralPath $staging -Recurse -Force
    }
    foreach($log in $plan.logs){Assert-NoReparsePath $log;Remove-Item -LiteralPath $log -Force}
    if(Test-Path -LiteralPath $plan.state){Remove-Item -LiteralPath $plan.state -Force}
    foreach($marker in $plan.markers){Assert-ContainedHistoryPath $marker $plan.ownerRoot;Remove-Item -LiteralPath $marker -Force}
    $script:LastVoiceCleanup=[pscustomobject]@{recordings=$plan.records.Count;audioBytes=$plan.bytes;logs=$plan.logs.Count;preservedWavs=$plan.preservedWavs}
    Write-Host ('Plugin voice history cleared: ' + $plan.records.Count + ' WAV recordings, ' + $plan.logs.Count + ' voice logs; ' + $plan.preservedWavs + ' unmarked WAVs retained.')
}
