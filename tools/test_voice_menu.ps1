# Menu navigation uses synthetic input and mocked commands, no real services.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\launcher\start-voice.ps1')
$script:answers=New-Object Collections.Generic.Queue[string]
$script:invocations=New-Object Collections.Generic.List[string]
$script:codes=New-Object Collections.Generic.Queue[int]
function Read-Host([string]$Prompt) {
    if($script:answers.Count -eq 0){throw 'Unexpected extra menu prompt'}
    return $script:answers.Dequeue()
}
function Invoke-VoiceMenuCommand($Command) {
    $script:invocations.Add($Command.Action + ':' + $Command.SetupOnly)
    $script:MenuCommandExitCode=$script:codes.Dequeue()
}
foreach($value in @('invalid & exit','1','','2','','3','','4','','5','','0')){$script:answers.Enqueue($value)}
foreach($value in @(0,1,0,2,0)){$script:codes.Enqueue($value)}
Invoke-VoiceMenu | Out-Null
if(($script:invocations -join ',') -ne 'Start:False,Stop:False,Restart:False,Status:False,Start:True'){throw 'Menu action dispatch failed'}
if($script:answers.Count -ne 0 -or $script:codes.Count -ne 0){throw 'Menu did not return after each result'}
if($null -ne (Get-VoiceMenuCommand '4; Stop-Process node')){throw 'Invalid choice accepted'}
$before=$script:invocations.Count
$script:answers.Enqueue('0')
Invoke-VoiceMenu | Out-Null
if($script:invocations.Count -ne $before){throw 'Exit performed a service action'}
$Action='Stop';$refused=$false
try{Invoke-VoiceMenu}catch{$refused=$true}
if(-not $refused){throw 'Menu accepted conflicting action flags'}
Write-Output '{"ok":true,"menu_actions":5,"return_after_success_failure_and_notready":true,"invalid_input_rejected":true,"exit_leaves_services_running":true,"real_services_changed":0}'
