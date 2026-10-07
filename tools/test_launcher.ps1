# Synthetic only: temp profile files, mocked service state. No real services or credentials.
param([string]$WorkDirectory = $env:TEMP)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\launcher\start-voice.ps1')
$suite = Join-Path ([IO.Path]::GetFullPath($WorkDirectory)) ('voice-launcher-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($suite) | Out-Null
$passed = New-Object Collections.Generic.List[string]
function Assert($Condition, [string]$Label) { if (-not $Condition) { throw ('Test failed: ' + $Label) } }
function Pass([string]$Name) { $passed.Add($Name) }
function Expect-Failure([scriptblock]$Action, [string]$Label) {
    $failed = $false
    try { & $Action | Out-Null } catch { $failed = $true }
    Assert $failed $Label
}
$cfg = New-BridgeConfig
Assert ($cfg.token.Length -ge 32 -and -not $cfg.transformation.enabled) 'fresh-config'
Pass 'fresh-config-token-and-optional-polish'
$cfgPath = Join-Path $suite 'synthetic.json'
Write-JsonAtomic $cfgPath $cfg $null
$before = [IO.File]::ReadAllText($cfgPath)
$tokenBefore = $cfg.token
$speechValue = 'SYNTHETIC-SPEECH-' + [guid]::NewGuid().ToString('N')
$polishValue = 'SYNTHETIC-POLISH-' + [guid]::NewGuid().ToString('N')
Set-Field $cfg.transcription 'apiKey' $speechValue
Set-Field $cfg.transformation 'apiKey' $polishValue
Set-Field $cfg 'customField' 'preserved'
Write-JsonAtomic $cfgPath $cfg $before
$after = Read-JsonFile $cfgPath
Assert ($after.token -ceq $tokenBefore -and $after.customField -eq 'preserved') 'preserved'
Assert (@(Get-ChildItem -LiteralPath $suite -Filter 'synthetic.json.backup-*').Count -eq 1) 'backup'
Pass 'atomic-update-preserves-token-unknown-fields-and-backup'
Expect-Failure { Write-JsonAtomic $cfgPath $cfg $before } 'concurrent-edit'
Pass 'concurrent-edit-refused'
$bad = Join-Path $suite 'invalid.json'
[IO.File]::WriteAllText($bad, '{broken')
Expect-Failure { Read-JsonFile $bad } 'invalid-json'
Assert ([IO.File]::ReadAllText($bad) -ceq '{broken') 'invalid-preserved'
Pass 'invalid-config-preserved'
$deep = [pscustomobject]@{leaf='synthetic-deep-value'}
for ($i=0;$i -lt 52;$i++) { $deep = [pscustomobject]@{nested=$deep} }
$deepPath = Join-Path $suite 'deep.json'
Write-JsonAtomic $deepPath $deep $null
$roundtrip = Read-JsonFile $deepPath
for ($i=0;$i -lt 52;$i++) { $roundtrip = $roundtrip.nested }
Assert ($roundtrip.leaf -eq 'synthetic-deep-value') 'deep-data-preserved'
$deepBefore = [IO.File]::ReadAllText($deepPath)
for ($i=0;$i -lt 40;$i++) { $deep = [pscustomobject]@{nested=$deep} }
Expect-Failure { Write-JsonAtomic $deepPath $deep $deepBefore } 'too-deep-refused'
Assert ([IO.File]::ReadAllText($deepPath) -ceq $deepBefore) 'too-deep-no-overwrite'
Pass 'deep-json-preserved-or-refused-without-truncation'
foreach ($invalidField in @('requireToken','apiKey','enabled','token','port')) {
    $invalid = New-BridgeConfig
    switch ($invalidField) {
        'requireToken' { $invalid.requireToken = 'false' }
        'apiKey' { $invalid.transcription.apiKey = @('synthetic') }
        'enabled' { $invalid.transformation.enabled = 'false' }
        'token' { $invalid.token = ('X' * 32) + "'" }
        'port' { $invalid.port = '39152' }
    }
    Expect-Failure { Assert-BridgeConfig $invalid } ('invalid-config-field-type-' + $invalidField)
}
Pass 'invalid-config-field-types-and-unsafe-token-refused'
$syntheticHost = Join-Path $suite 'epicenter.exe'
$hostProcesses = @([pscustomobject]@{Name='epicenter.exe';ExecutablePath=$syntheticHost})
Assert (Assert-EpicenterProcesses $hostProcesses $syntheticHost) 'matching-host-reuse'
$otherHost = Join-Path $suite 'other\epicenter.exe'
Expect-Failure { Assert-EpicenterProcesses $hostProcesses $otherHost } 'different-host-refused'
Expect-Failure { Assert-EpicenterProcesses @([pscustomobject]@{Name='epicenter.exe';ExecutablePath=$null}) $syntheticHost } 'unidentified-host-refused'
Pass 'selected-host-reuse-and-other-installation-conflict'
Assert ((Normalize-BaseURL 'https://api.openai.com/v1/chat/completions') -eq 'https://api.openai.com/v1') 'endpoint-normalization'
Expect-Failure { Normalize-BaseURL ('https://' + 'name:password@example.invalid/v1') } 'userinfo'
Expect-Failure { Normalize-BaseURL 'http://example.invalid/v1' } 'https'
Pass 'endpoint-normalization-and-credential-url-refusal'
function Read-Host { param([string]$Prompt,[switch]$AsSecureString)
    if ($script:answers.Count -eq 0) { throw 'No synthetic answer' }
    $value = $script:answers.Dequeue()
    if ($AsSecureString) {
        $secureValue = New-Object Security.SecureString
        foreach ($character in $value.ToCharArray()) { $secureValue.AppendChar($character) }
        return $secureValue
    }
    return $value
}
$script:answers = New-Object Collections.Generic.Queue[string]
$script:answers.Enqueue(''); $script:answers.Enqueue(''); $script:answers.Enqueue(''); $script:answers.Enqueue('')
Set-CloudSettings $cfg.transcription $false | Out-Null
Assert ($cfg.transcription.apiKey -ceq $speechValue) 'blank-preserves-key'
Pass 'hidden-entry-keeps-existing-key'
$script:answers.Enqueue('2'); $script:answers.Enqueue(''); $script:answers.Enqueue(''); $script:answers.Enqueue('')
Expect-Failure { Set-CloudSettings $cfg.transcription $false } 'provider-change-needs-key'
Pass 'changed-provider-cannot-reuse-old-key'
$unicodeName = [string][char]0x6E2C + [char]0x8A66 + ' space & sample.mjs'
$unicodePath = Join-Path $suite $unicodeName
[IO.File]::WriteAllText($unicodePath, '// synthetic')
Assert ((Resolve-LocalFile $unicodePath @('.mjs')) -ceq $unicodePath) 'unicode-path'
Pass 'chinese-space-and-metacharacter-path'
$script:owners = @(12345)
$script:commandLine = 'node "' + $unicodePath + '"'
function Get-Listener { param([int]$Port) return $script:owners }
function Get-CimInstance { param([string]$ClassName,[string]$Filter) return [pscustomobject]@{ CommandLine=$script:commandLine; ExecutablePath='unused' } }
Assert (Assert-PortOwner 39152 $unicodePath) 'matching-owner'
$script:commandLine = 'node "' + $unicodePath + '.other"'
Expect-Failure { Assert-PortOwner 39152 $unicodePath } 'partial-match'
Pass 'exact-process-entry-and-unrelated-port-conflict'
$script:commandLine = 'node "' + $unicodePath + '"'
$paths = [pscustomobject]@{ bridgeEntry=$unicodePath; epicenterExe='synthetic'; dshEntry=$unicodePath; dshPort=3080; nodeExe='unused' }
$script:started = New-Object Collections.Generic.List[string]
function Start-Worker { param($Paths,$Path,$Role,$StatusPath,$SkipBrowser) $script:started.Add($Role) }
function Test-EpicenterRunning { param($Exe) return $true }
function Get-BridgeHealth { param($Config) return $true }
function Invoke-VoiceEnsureBackend {param($Paths,$Config,$Path)
    if(-not(Get-BridgeHealth $Config)){Stop-Voice 'Synthetic backend not healthy'}
}
Invoke-Startup $paths $cfg $cfgPath $false $true | Out-Null
Assert ($script:started.Count -eq 0) 'reuse'
Invoke-Startup $paths $cfg $cfgPath $true $true | Out-Null
Assert ($script:started.Count -eq 0) 'check-only'
Pass 'reuse-services-and-read-only-check'
$script:browserAttempts=0
function Start-Process { $script:browserAttempts++;throw 'SYNTHETIC private browser failure' }
Invoke-Startup $paths $cfg $cfgPath $false $false | Out-Null
Assert ($script:browserAttempts -eq 1 -and $script:started.Count -eq 0) 'browser-failure-services-remain-ready'
Pass 'existing-dsh-browser-open-failure-is-nonfatal'
function Get-BridgeHealth { param($Config) return $false }
function Start-Sleep { param($Milliseconds) }
Expect-Failure { Invoke-Startup $paths $cfg $cfgPath $false $true } 'health-failure'
Assert ($script:started.Count -eq 0) 'no-dsh-on-failed-health'
Pass 'failed-health-blocks-dsh-without-stopping-services'
# Exercise the missing-DSH branch, including typed launcher Status switch regression.
function Get-BridgeHealth { param($Config) return $true }
function Invoke-VoiceEnsureBackend {param($Paths,$Config,$Path)
    if(-not(Get-BridgeHealth $Config)){Stop-Voice 'Synthetic backend not healthy'}
}
function Assert-PortOwner { param($Port,$Entry,$NodeExe) return ($Port -eq 39152 -or $script:dshAnnounced) }
$script:dshAnnounced=$false
function Start-Worker {
    param($Paths,$Path,$Role,$StatusPath,$SkipBrowser)
    if($Role -eq 'dsh'){
        $script:dshAnnounced=$true
        [IO.File]::WriteAllText($StatusPath,'{"ready":true,"browserOpened":false}')
    }else{throw 'Unexpected synthetic backend start'}
}
Invoke-Startup $paths $cfg $cfgPath $false $true | Out-Null
Assert $script:dshAnnounced 'missing-dsh-started'
Assert (@(Get-ChildItem -LiteralPath $suite -Filter 'launch-*.json').Count -eq 0) 'dsh-status-file-removed'
Pass 'missing-dsh-startup-status-path-without-switch-variable-collision'
# Test real setup logic with synthetic files and mocked interactive answers.
$hostPath = Join-Path $suite 'host.exe'; [IO.File]::WriteAllText($hostPath, 'synthetic-not-an-executable')
$dshPath = Join-Path $suite 'cli.js'; [IO.File]::WriteAllText($dshPath, '// synthetic')
$settings = Join-Path $suite 'paths.json'
$settingsValue = [pscustomobject]@{epicenterExe=$hostPath;bridgeEntry=$unicodePath;nodeExe=(Find-Node);dshEntry=$dshPath;dshPort=3080}
Write-JsonAtomic $settings $settingsValue $null
$original = Read-JsonFile $cfgPath
foreach ($answer in @('','','','','','','','','','n')) { $script:answers.Enqueue($answer) }
Invoke-Setup $settings $cfgPath | Out-Null
$saved = Read-JsonFile $cfgPath
Assert ($saved.token -ceq $original.token -and $saved.transcription.apiKey -ceq $speechValue -and
        $saved.transformation.apiKey -ceq $polishValue -and -not $saved.transformation.enabled) 'full-setup-preservation'
Pass 'full-setup-retains-both-keys-token-and-disabled-polish'
$freshPaths = Join-Path $suite 'fresh-paths.json'
$freshConfig = Join-Path $suite 'fresh-config.json'
foreach ($answer in @($hostPath,$unicodePath,(Find-Node),$dshPath,'3087','1','','',$speechValue,'y','1','','',$polishValue,'SYNTHETIC line one\nline two')) {
    $script:answers.Enqueue($answer)
}
Invoke-Setup $freshPaths $freshConfig | Out-Null
$fresh = Read-JsonFile $freshConfig
Assert ($fresh.transcription.apiKey -ceq $speechValue -and $fresh.transformation.apiKey -ceq $polishValue -and
        $fresh.transformation.enabled -and $fresh.transformation.model -eq 'gpt-5.4-mini' -and
        $fresh.transformation.prompt.Contains("`n") -and $fresh.token -cne $tokenBefore) 'fresh-wizard'
Pass 'fresh-wizard-distinct-hidden-keys-single-prompt-and-model'
Write-Output (([ordered]@{ok=$true;tests=$passed;real_cloud_calls=0;real_services_started=0;microphone_used=$false} | ConvertTo-Json -Depth 5 -Compress))
