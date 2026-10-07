# Windows PowerShell 5.1+, Windows only. Keys are read interactively, never as arguments.
[CmdletBinding()]
param(
    [switch]$Menu,
    [ValidateSet('Start','Stop','Restart','Status')][string]$Action = 'Start',
    [switch]$Stop,
    [switch]$Restart,
    [switch]$Status,
    [switch]$Configure,
    [switch]$SetupOnly,
    [switch]$Check,
    [switch]$NoBrowser,
    [string]$SettingsPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:LauncherDirectory = $PSScriptRoot
$script:LauncherStep = 'Initialization'
if (-not $PSBoundParameters.ContainsKey('SettingsPath')) {
    # PS5.1 does not reliably populate PSScriptRoot while binding parameter defaults.
    $besideLauncher = Join-Path $script:LauncherDirectory 'paths.json'
    if ([IO.File]::Exists($besideLauncher)) { $SettingsPath = $besideLauncher }
    else { $SettingsPath = Join-Path $env:LOCALAPPDATA 'dsh-voice-launcher\paths.json' }
}

function Stop-Voice([string]$Message) {
    $fault = New-Object InvalidOperationException($Message)
    $fault.Data['VoiceLauncherSafe'] = $true
    throw $fault
}

function Set-Field($Object, [string]$Name, $Value) {
    if ($null -eq $Object.PSObject.Properties[$Name]) {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    } else { $Object.$Name = $Value }
}
function Get-Field($Object, [string]$Name, $Default) {
    if ($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]) { return ,($Object.$Name) }
    return $Default
}
function Read-JsonFile([string]$Path) {
    try {
        $value = [IO.File]::ReadAllText($Path) | ConvertFrom-Json
        if ($null -eq $value -or $value -isnot [pscustomobject]) { Stop-Voice 'Invalid object' }
        return $value
    } catch { Stop-Voice 'A local settings file is invalid or unreadable. Correct it locally; it was not overwritten.' }
}
function Assert-JsonDepth($Value, [int]$Depth = 0) {
    if ($Depth -gt 80) { Stop-Voice 'Settings nesting is too deep to save safely. No file was overwritten.' }
    if ($Value -is [pscustomobject]) {
        foreach ($property in $Value.PSObject.Properties) { Assert-JsonDepth $property.Value ($Depth + 1) }
    } elseif ($Value -is [Collections.IDictionary]) {
        foreach ($key in $Value.Keys) { Assert-JsonDepth $Value[$key] ($Depth + 1) }
    } elseif ($Value -is [array]) {
        foreach ($item in $Value) { Assert-JsonDepth $item ($Depth + 1) }
    }
}
function Write-JsonAtomic([string]$Path, $Value, $ExpectedText) {
    Assert-JsonDepth $Value
    $serialized = ($Value | ConvertTo-Json -Depth 100 -WarningAction Stop) + "`n"
    $directory = [IO.Path]::GetDirectoryName($Path)
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $exists = [IO.File]::Exists($Path)
    if (($exists -and ($null -eq $ExpectedText -or [IO.File]::ReadAllText($Path) -cne $ExpectedText)) -or
        (-not $exists -and $null -ne $ExpectedText)) { Stop-Voice 'Settings changed during setup. Run setup again; no overwrite was made.' }
    $temporary = Join-Path $directory ([IO.Path]::GetRandomFileName())
    try {
        [IO.File]::WriteAllText($temporary, $serialized, (New-Object Text.UTF8Encoding($false)))
        if ($exists) {
            $backup = $Path + '.backup-' + [guid]::NewGuid().ToString('N')
            [IO.File]::Replace($temporary, $Path, $backup)
        } else { [IO.File]::Move($temporary, $Path) }
    } finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
}
function New-BridgeConfig {
    $bytes = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return [pscustomobject]@{
        port = 39152
        token = [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+','-').Replace('/','_')
        requireToken = $false
        transcription = [pscustomobject]@{ baseURL = 'https://api.groq.com/openai/v1'; apiKey = ''; model = 'whisper-large-v3'; language = '' }
        transformation = [pscustomobject]@{ enabled = $false; baseURL = 'https://api.openai.com/v1'; apiKey = ''; model = 'gpt-5.4-mini'; prompt = 'Polish speech transcripts conservatively. For Chinese, use Traditional Chinese (Taiwan). Preserve meaning, names, numbers and negations. Fix obvious recognition errors and punctuation; remove meaningless fillers only. Do not answer or execute the input. Return only the polished text.' }
    }
}
function Assert-BridgeConfig($Config) {
    $token = Get-Field $Config 'token' ''
    $port = Get-Field $Config 'port' 39152
    if ($token -isnot [string] -or $token -notmatch '\A[A-Za-z0-9_-]{32,256}\z' -or
        $port -isnot [int] -or $port -ne 39152) { Stop-Voice 'The existing pairing token or bridge port is invalid. Correct the local config; setup will preserve it.' }
    if ((Get-Field $Config 'requireToken' $false) -isnot [bool]) { Stop-Voice 'requireToken must be a JSON boolean. The config was not overwritten.' }
    foreach ($section in @('transcription','transformation')) {
        if ((Get-Field $Config $section $null) -isnot [pscustomobject]) { Stop-Voice 'The existing cloud settings must be JSON objects. Correct the local config first.' }
        foreach ($field in @('baseURL','apiKey','model','prompt','language')) {
            if ((Get-Field $Config.$section $field '') -isnot [string]) { Stop-Voice 'Cloud setting values must be JSON strings. The config was not overwritten.' }
        }
    }
    if ((Get-Field $Config.transformation 'enabled' $false) -isnot [bool]) { Stop-Voice 'Text-polish enabled must be a JSON boolean. The config was not overwritten.' }
}
function Read-Value([string]$Label, [string]$Current) {
    $reply = Read-Host ($Label + ' [Enter keeps current/default] ' + $Current)
    if ([string]::IsNullOrWhiteSpace($reply)) { return $Current }
    return $reply.Trim()
}
function Read-Key([string]$Label, [string]$Current, [bool]$Required) {
    $secure = Read-Host ($Label + ' (hidden; Enter keeps existing)') -AsSecureString
    $pointer = [IntPtr]::Zero
    try {
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        $reply = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
        if ([string]::IsNullOrWhiteSpace($reply)) { $reply = $Current }
        if ($Required -and [string]::IsNullOrWhiteSpace($reply)) { Stop-Voice 'A key is required for the selected cloud service. Run setup again.' }
        return $reply
    } finally {
        if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
        $secure.Dispose()
    }
}
function Normalize-BaseURL([string]$Value) {
    $uri = $null
    if (-not [Uri]::TryCreate($Value.Trim(), [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -ne 'https' -or
        $uri.UserInfo -or $uri.Query -or $uri.Fragment) { Stop-Voice 'Cloud baseURL must be HTTPS with no credentials, query or fragment.' }
    return ($uri.AbsoluteUri.TrimEnd('/') -replace '/(?:chat/completions|audio/transcriptions)$','')
}
function Set-CloudSettings($Section, [bool]$Polish) {
    $oldBase = Get-Field $Section 'baseURL' ''
    if ($Polish) { $choice = Read-Host 'Text polish: 1 OpenAI, 2 compatible service, Enter keep provider' }
    else { $choice = Read-Host 'Speech: 1 Groq, 2 OpenAI, 3 compatible service, Enter keep provider' }
    $base = $oldBase
    $model = Get-Field $Section 'model' ''
    if (($Polish -and $choice -eq '1') -or (-not $Polish -and $choice -eq '2')) {
        $base = 'https://api.openai.com/v1'
        if ($Polish) { $model = 'gpt-5.4-mini' } else { $model = 'whisper-1' }
    } elseif (-not $Polish -and $choice -eq '1') {
        $base = 'https://api.groq.com/openai/v1'; $model = 'whisper-large-v3'
    } elseif ($choice -and (($Polish -and $choice -ne '2') -or (-not $Polish -and $choice -ne '3'))) {
        Stop-Voice 'Unknown provider choice. Run setup again.'
    }
    $base = Normalize-BaseURL (Read-Value 'API baseURL (without endpoint suffix)' $base)
    $model = Read-Value 'Model supported by this provider' $model
    if ([string]::IsNullOrWhiteSpace($model)) { Stop-Voice 'A model is required.' }
    $existing = Get-Field $Section 'apiKey' ''
    if ($base -cne $oldBase) { $existing = ''; Write-Host 'Provider endpoint changed: enter its matching key.' }
    $label = 'Speech-to-text API Key'
    if ($Polish) { $label = 'Text-polish API Key' }
    Set-Field $Section 'baseURL' $base
    Set-Field $Section 'model' $model
    Set-Field $Section 'apiKey' (Read-Key $label $existing $true)
    if ($Polish) {
        $prompt = Read-Value 'One polish prompt (use \n for line breaks)' (Get-Field $Section 'prompt' '')
        if ([string]::IsNullOrWhiteSpace($prompt)) { Stop-Voice 'A polish prompt is required.' }
        Set-Field $Section 'prompt' ($prompt.Replace('\n',"`n"))
    }
}
function Resolve-LocalFile([string]$Value, [string[]]$Extensions) {
    try {
        $expanded = [Environment]::ExpandEnvironmentVariables($Value.Trim().Trim('"'))
        if (-not [IO.Path]::IsPathRooted($expanded)) { Stop-Voice 'Absolute path required' }
        $full = [IO.Path]::GetFullPath($expanded)
        if (-not [IO.File]::Exists($full) -or [IO.Path]::GetExtension($full).ToLowerInvariant() -notin $Extensions) { Stop-Voice 'Invalid file' }
        return $full
    } catch { Stop-Voice 'A required program path is invalid. Use an existing absolute file path; run with -Configure to change it.' }
}
function Find-Node {
    $command = Get-Command node.exe -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }
    return ''
}
function Find-DshEntry {
    $command = Get-Command dsh.cmd -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        $entry = Join-Path (Split-Path $command.Source) 'node_modules\@deepseek-ai\dsh\lib\bin.js'
        if ([IO.File]::Exists($entry)) { return $entry }
    }
    return ''
}
function Assert-Paths($Paths) {
    Set-Field $Paths 'epicenterExe' (Resolve-LocalFile (Get-Field $Paths 'epicenterExe' '') @('.exe'))
    Set-Field $Paths 'bridgeEntry' (Resolve-LocalFile (Get-Field $Paths 'bridgeEntry' '') @('.mjs'))
    Set-Field $Paths 'nodeExe' (Resolve-LocalFile (Get-Field $Paths 'nodeExe' '') @('.exe'))
    Set-Field $Paths 'dshEntry' (Resolve-LocalFile (Get-Field $Paths 'dshEntry' '') @('.js','.mjs'))
    $port = Get-Field $Paths 'dshPort' 3080
    if ($port -isnot [int] -or $port -lt 1024 -or $port -gt 65535 -or $port -eq 39152) { Stop-Voice 'DSH port must be an integer from 1024 to 65535, different from bridge port 39152.' }
    $version = & $Paths.nodeExe --version 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]$version -notmatch '^v(\d+)\.' -or [int]$Matches[1] -lt 18) { Stop-Voice 'Node 18 or newer is required.' }
}
function Invoke-Setup([string]$Path, [string]$ConfigPath) {
    Write-Host 'Windows voice setup. Keys stay in local bridge config; Enter preserves existing values.'
    $oldPaths = $null; $oldConfig = $null
    if ([IO.File]::Exists($Path)) { $oldPaths = [IO.File]::ReadAllText($Path); $paths = Read-JsonFile $Path }
    else {
        $paths = [pscustomobject]@{ epicenterExe = ''; bridgeEntry = [IO.Path]::GetFullPath((Join-Path $script:LauncherDirectory '..\bridge\bridge.mjs')); nodeExe = (Find-Node); dshEntry = (Find-DshEntry); dshPort = 3080 }
    }
    if ([IO.File]::Exists($ConfigPath)) { $oldConfig = [IO.File]::ReadAllText($ConfigPath); $config = Read-JsonFile $ConfigPath }
    else { $config = New-BridgeConfig }
    Assert-BridgeConfig $config
    foreach ($field in @('epicenterExe','bridgeEntry','nodeExe','dshEntry')) {
        Set-Field $paths $field (Read-Value $field (Get-Field $paths $field ''))
    }
    $portText = Read-Value 'DSH web port' ([string](Get-Field $paths 'dshPort' 3080))
    $portValue = 0
    if (-not [int]::TryParse($portText, [ref]$portValue)) { Stop-Voice 'DSH port must be an integer.' }
    Set-Field $paths 'dshPort' $portValue
    Assert-Paths $paths
    Set-CloudSettings $config.transcription $false
    $enabled = Get-Field $config.transformation 'enabled' $false
    $answer = Read-Host ('Enable optional text polish? y/n [Enter keeps ' + $enabled + ']')
    if ($answer -match '^(?i:y|yes)$') { $enabled = $true }
    elseif ($answer -match '^(?i:n|no)$') { $enabled = $false }
    elseif ($answer) { Stop-Voice 'Choose y or n for optional text polish.' }
    Set-Field $config.transformation 'enabled' $enabled
    if ($enabled) { Set-CloudSettings $config.transformation $true }
    Assert-JsonDepth $config
    Assert-JsonDepth $paths
    Write-JsonAtomic $ConfigPath $config $oldConfig
    Write-JsonAtomic $Path $paths $oldPaths
    Write-Host 'Saved locally. No cloud call was made. Keep config and backup files private.'
}
function Get-Listener([int]$Port) {
    # Include IPv6/other bindings: any listener may conflict; never kill by port.
    try {
        return @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop | Select-Object -ExpandProperty OwningProcess -Unique)
    } catch {
        if ($_.CategoryInfo.Category -eq 'ObjectNotFound') { return @() }
        Stop-Voice 'Cannot inspect local port owners. Check Windows permissions; no service was started.'
    }
}
function Assert-PortOwner([int]$Port, [string]$Entry, [string]$NodeExe = '') {
    $owners = @(Get-Listener $Port)
    foreach ($ownerId in $owners) {
        $owner = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$ownerId)
        $exactEntry = '(?:^|[\s"])' + [regex]::Escape($Entry) + '(?:$|[\s"])'
        if ($null -eq $owner -or [string]$owner.CommandLine -notmatch $exactEntry -or
            ($NodeExe -and (Get-Field $owner 'ExecutablePath' '') -ne $NodeExe)) {
            Stop-Voice 'A required port is occupied by a different or unidentified process. Resolve the conflict; no process was stopped.'
        }
    }
    return ($owners.Count -gt 0)
}
function Assert-EpicenterProcesses($Processes, [string]$Exe) {
    $found = $false
    $name = [IO.Path]::GetFileName($Exe)
    foreach ($process in $Processes) {
        $processPath = Get-Field $process 'ExecutablePath' ''
        if ($processPath -eq $Exe) { $found = $true }
        elseif ((Get-Field $process 'Name' '') -in @('epicenter.exe', $name)) {
            Stop-Voice 'Another or unidentified Epicenter installation is running. Resolve it locally before starting the selected host; no process was stopped.'
        }
    }
    return $found
}
function Test-EpicenterRunning([string]$Exe) {
    return (Assert-EpicenterProcesses @(Get-CimInstance Win32_Process) $Exe)
}
function Get-BridgeHealth($Config, [int]$Port = 39152) {
    $response = $null
    try {
        $request = [Net.HttpWebRequest]::Create('http://127.0.0.1:' + $Port + '/health')
        $request.Proxy = $null; $request.AllowAutoRedirect = $false; $request.Timeout = 1500
        if ((Get-Field $Config 'requireToken' $false) -eq $true) { $request.Headers['Authorization'] = 'Bearer ' + $Config.token }
        $response = $request.GetResponse()
        if ([int]$response.StatusCode -ne 200) { return $false }
        $reader = New-Object IO.StreamReader($response.GetResponseStream())
        try { $health = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
        return ((Get-Field $health 'ok' $false) -eq $true -and (Get-Field $health 'epicenter' '') -eq 'ok')
    } catch { return $false } finally { if ($null -ne $response) { $response.Dispose() } }
}
function Start-Worker($Paths, [string]$Path, [string]$Role, [string]$StatusPath, [bool]$SkipBrowser) {
    $script:LauncherStep = 'Start worker: ' + $Role
    $worker = Join-Path $script:LauncherDirectory 'launch-service.mjs'
    $acknowledgement = ''
    if ($Role -in @('host','bridge')) {
        $acknowledgement = Join-Path ([IO.Path]::GetDirectoryName($Path)) ('worker-' + [guid]::NewGuid().ToString('N') + '.json')
        $StatusPath = $acknowledgement
    }
    # All arguments are validated file paths or fixed strings; no shell evaluates them.
    $arguments = '"' + $worker + '" --settings "' + $Path + '" --role ' + $Role
    if ($StatusPath) { $arguments += ' --status "' + $StatusPath + '"' }
    if ($SkipBrowser) { $arguments += ' --no-browser' }
    $helper = $null
    try {
        try { $helper = Start-Process -FilePath $Paths.nodeExe -ArgumentList $arguments -WindowStyle Hidden -PassThru }
        catch { Stop-Voice ('Cannot launch the ' + $Role + ' worker. Check the Node path and Windows permissions; run Status before retrying.') }
        if ($acknowledgement) {
            if (-not $helper.WaitForExit(8000)) { Stop-Voice ('The ' + $Role + ' worker did not finish launching. Run Status before retrying.') }
            if ($helper.ExitCode -ne 0 -or -not [IO.File]::Exists($acknowledgement)) {
                Stop-Voice ('The ' + $Role + ' worker failed before confirming startup. Check paths.json, Node and local permissions; run Status before retrying.')
            }
            $result = Read-JsonFile $acknowledgement
            if ((Get-Field $result 'ready' $false) -ne $true) { Stop-Voice ('The ' + $Role + ' process could not be created. Run Status and check the executable locally.') }
        }
    } finally {
        if ($null -ne $helper) { $helper.Dispose() }
        if ($acknowledgement) {
            foreach ($temporary in @($acknowledgement, ($acknowledgement + '.tmp'))) {
                if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
            }
        }
    }
}
function Invoke-Startup($Paths, $Config, [string]$Path, [bool]$InspectOnly, [bool]$SkipBrowser) {
    $script:LauncherStep = 'Inspect startup processes'
    $bridgeRunning = Assert-PortOwner 39152 $Paths.bridgeEntry $Paths.nodeExe
    $dshRunning = Assert-PortOwner $Paths.dshPort $Paths.dshEntry $Paths.nodeExe
    if ($InspectOnly) {
        Write-Host 'Program paths and port ownership checked. No service started; no cloud call made.'
        if (Get-BridgeHealth $Config) { Write-Host 'Existing bridge and Epicenter health: OK.' }
        else { Write-Host 'Bridge/Epicenter not ready yet; use normal launch to start them.' }
        return
    }
    Invoke-VoiceEnsureBackend $Paths $Config $Path
    if ($dshRunning) {
        $script:LauncherStep = 'Open existing DSH browser'
        if (-not $SkipBrowser) {
            try { Start-Process ('http://127.0.0.1:' + $Paths.dshPort + '/') -ErrorAction Stop | Out-Null }
            catch { Write-Host ('Voice services are ready, but the browser could not be opened. Open http://127.0.0.1:' + $Paths.dshPort + '/ manually.') -ForegroundColor Yellow }
        }
        Write-Host 'Existing DSH preserved. If login is required, use its existing authenticated tab or launch link.'
    } else {
        $launchStatusPath = Join-Path ([IO.Path]::GetDirectoryName($Path)) ('launch-' + [guid]::NewGuid().ToString('N') + '.json')
        try {
            Start-Worker $Paths $Path 'dsh' $launchStatusPath $SkipBrowser
            $script:LauncherStep = 'Wait for DSH startup'
            $ready = $false
            for ($attempt = 0; $attempt -lt 50; $attempt++) {
                if ([IO.File]::Exists($launchStatusPath)) {
                    $result = Read-JsonFile $launchStatusPath
                    if ((Get-Field $result 'ready' $false) -eq $true) { $ready = $true; break }
                    Stop-Voice 'DSH startup failed. Check its installation/version locally. No raw output or login token was recorded.'
                }
                Start-Sleep -Milliseconds 600
            }
            if (-not $ready) { Stop-Voice 'DSH startup timed out. Check it locally before launching again; do not terminate other sessions.' }
            if (-not (Assert-PortOwner $Paths.dshPort $Paths.dshEntry $Paths.nodeExe)) { Stop-Voice 'DSH did not keep its web listener running. Check the local installation.' }
            if (-not $SkipBrowser -and (Get-Field $result 'browserOpened' $false) -ne $true) {
                Write-Host 'DSH is running, but browser opening failed or timed out. Open its ordinary loopback URL; use an existing authenticated tab if available. No login token was printed.'
            }
        } finally {
            if ([IO.File]::Exists($launchStatusPath)) { [IO.File]::Delete($launchStatusPath) }
        }
    }
    Write-Host 'Ready. Install/enable the voice plugin and pair the tab once as documented. No recording or cloud call was made.'
}
. (Join-Path $script:LauncherDirectory 'voice-control.ps1')
. (Join-Path $script:LauncherDirectory 'voice-retention.ps1')

function Get-VoiceMenuCommand([string]$Choice) {
    switch ($Choice) {
        '1' { return [pscustomobject]@{Action='Start';SetupOnly=$false} }
        '2' { return [pscustomobject]@{Action='Stop';SetupOnly=$false} }
        '3' { return [pscustomobject]@{Action='Restart';SetupOnly=$false} }
        '4' { return [pscustomobject]@{Action='Status';SetupOnly=$false} }
        '5' { return [pscustomobject]@{Action='Start';SetupOnly=$true} }
        default { return $null }
    }
}
function Invoke-VoiceMenuCommand($Command) {
    # Fixed menu choices become structured native arguments; user input is never evaluated.
    $arguments = @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',
        (Join-Path $script:LauncherDirectory 'start-voice.ps1'),'-SettingsPath',$SettingsPath)
    if ($Command.SetupOnly) { $arguments += '-SetupOnly' }
    else { $arguments += @('-Action',$Command.Action) }
    & powershell.exe @arguments
    $script:MenuCommandExitCode = $LASTEXITCODE
}
function Invoke-VoiceMenu {
    if ($Action -ne 'Start' -or $Stop -or $Restart -or $Status -or $Check -or $Configure -or $SetupOnly -or $NoBrowser) {
        Stop-Voice 'Use Menu on its own, or select one command without Menu.'
    }
    while ($true) {
        Write-Host ''
        Write-Host '========== Voice services =========='
        Write-Host '  1. Start services'
        Write-Host '  2. Stop voice backend'
        Write-Host '  3. Restart voice backend'
        Write-Host '  4. Status'
        Write-Host '  5. Settings (paths, keys, text polish)'
        Write-Host '  0. Exit menu (services keep running)'
        Write-Host 'Finish recording/transcription first. DSH and drafts are preserved.'
        Write-Host 'Cold Start/Restart clears plugin-owned audio. Partial recovery keeps healthy services.'
        $choice = (Read-Host 'Choose 0-5').Trim()
        if ($choice -eq '0') { return }
        $command = Get-VoiceMenuCommand $choice
        if ($null -eq $command) {
            Write-Host 'Enter a number from 0 to 5.' -ForegroundColor Yellow
            continue
        }
        $script:MenuCommandExitCode = 0
        Invoke-VoiceMenuCommand $command
        if ($script:MenuCommandExitCode -eq 1) {
            Write-Host 'Command failed; see the message above.' -ForegroundColor Yellow
        } elseif ($script:MenuCommandExitCode -eq 2) {
            Write-Host 'Services are not ready or conflicted.' -ForegroundColor Yellow
        }
        [void](Read-Host 'Press Enter to return to the menu')
    }
}

function Resolve-LauncherAction {
    $selected = @()
    if ($Stop) { $selected += 'Stop' }
    if ($Restart) { $selected += 'Restart' }
    if ($Status -or $Check) { $selected += 'Status' }
    if ($selected.Count -gt 1 -or ($selected.Count -gt 0 -and $Action -ne 'Start')) {
        Stop-Voice 'Choose only one action: Start, Stop, Restart or Status.'
    }
    $resolved = $Action
    if ($selected.Count -eq 1) { $resolved = $selected[0] }
    if ($resolved -ne 'Start' -and ($Configure -or $SetupOnly -or $NoBrowser)) {
        Stop-Voice 'Configure, SetupOnly and NoBrowser apply only to Start.'
    }
    return $resolved
}
function Invoke-Launcher {
    $script:LauncherStep = 'Validate settings'
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { Stop-Voice 'This launcher supports Windows only. macOS/Linux are not supported in this release.' }
    $selectedAction = Resolve-LauncherAction
    $path = [IO.Path]::GetFullPath($SettingsPath)
    $configPath = Join-Path $env:APPDATA 'dsh-voice-bridge\config.json'
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { $digest = [BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($configPath.ToLowerInvariant()))).Replace('-','') }
    finally { $hasher.Dispose() }
    $mutex = New-Object Threading.Mutex($false, ('Local\DSHVoiceLauncher-' + $digest))
    $locked = $false
    try {
        try { $locked = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked = $true }
        if (-not $locked) { Stop-Voice 'Another launcher/setup is running. Wait for it to finish.' }
        if ($selectedAction -ne 'Start' -and -not [IO.File]::Exists($path)) {
            Stop-Voice 'First-run settings are missing. Run the launcher normally or with -SetupOnly.'
        }
        if ($Configure -or $SetupOnly -or -not [IO.File]::Exists($path)) {
            Invoke-Setup $path $configPath
        }
        if ($SetupOnly) { return }
        $paths = Read-JsonFile $path; Assert-ControlPaths $paths
        if ($selectedAction -eq 'Stop') { Invoke-VoiceStop $paths; return }
        if ($selectedAction -eq 'Status') {
            $config = $null
            if ([IO.File]::Exists($configPath)) {
                try { $config = Read-JsonFile $configPath; Assert-BridgeConfig $config }
                catch { $config = $null }
            }
            $state = Show-VoiceStatus $paths $config
            if (-not $state.healthy -or $state.conflict) { $script:LauncherExitCode = 2 }
            return
        }
        # Validate startup requirements before stopping a running service for Restart.
        Assert-Paths $paths
        $config = Read-JsonFile $configPath; Assert-BridgeConfig $config
        if ([string]::IsNullOrWhiteSpace((Get-Field $config.transcription 'apiKey' ''))) { Stop-Voice 'Speech key is missing. Run with -Configure.' }
        [void](Normalize-BaseURL (Get-Field $config.transcription 'baseURL' ''))
        if ([string]::IsNullOrWhiteSpace((Get-Field $config.transcription 'model' ''))) { Stop-Voice 'Speech model is missing. Run with -Configure.' }
        $inventory=Get-StableVoiceInventory $paths
        Assert-VoiceInventoryOwnership $inventory ($selectedAction -eq 'Start')
        if ($selectedAction -eq 'Restart') {
            $script:LauncherStep = 'Validate history and recording state'
            Assert-NoActiveVoiceRecording $paths
            [void](Get-VoiceHistoryPlan $paths)
            $script:LauncherStep = 'Stop selected voice backend'
            Invoke-VoiceStop $paths
            $script:LauncherStep = 'Clear plugin-owned history'
            Invoke-VoiceHistoryCleanup $paths
            Invoke-VoiceBackendStart $paths $config $path
        } else {
            # Cold startup can purge safely. Partial recovery must not stop healthy
            # components or remove audio that an existing component could be using.
            if($inventory.hosts.Count -eq 0 -and $inventory.bridges.Count -eq 0) {
                $script:LauncherStep='Clear plugin-owned history before cold startup'
                Invoke-VoiceHistoryCleanup $paths
            } else { Write-Host 'Existing voice components will be checked and kept if healthy. History cleanup is deferred until Restart or a fully stopped Start.' }
            Invoke-Startup $paths $config $path $false ([bool]$NoBrowser)
        }
    } finally { if ($locked) { $mutex.ReleaseMutex() }; $mutex.Dispose() }
}
if ($MyInvocation.InvocationName -ne '.') {
    $script:LauncherExitCode = 0
    try {
        if ($Menu) { Invoke-VoiceMenu } else { Invoke-Launcher }
        exit $script:LauncherExitCode
    }
    catch {
        # Fixed actionable messages only. Never print arbitrary OS/provider exception details.
        $message = 'Launcher failed during: ' + $script:LauncherStep + '. Run Status before retrying. No private diagnostics were printed.'
        $fault = $_.Exception
        while ($null -ne $fault) {
            if ($fault.Data.Contains('VoiceLauncherSafe')) { $message = $fault.Message; break }
            $fault = $fault.InnerException
        }
        Write-Host ('Voice launcher: ' + $message) -ForegroundColor Red
        exit 1
    }
}
