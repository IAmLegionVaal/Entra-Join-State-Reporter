[CmdletBinding()]
param(
    [switch]$RefreshPrt,
    [switch]$TriggerDeviceJoin,
    [switch]$RestartIdentityServices,
    [switch]$RunDebugDiagnostics,
    [switch]$DryRun,
    [switch]$Yes,
    [string]$OutputPath = (Join-Path $env:ProgramData 'EntraJoinRepair')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Failures = 0
$script:VerificationFailures = 0
$script:Actions = 0

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if ($env:OS -ne 'Windows_NT') { Write-Error 'This tool requires Windows.'; exit 3 }
if (-not ($RefreshPrt -or $TriggerDeviceJoin -or $RestartIdentityServices -or $RunDebugDiagnostics)) { Write-Error 'Choose at least one repair action.'; exit 2 }
if (-not (Get-Command dsregcmd.exe -ErrorAction SilentlyContinue)) { Write-Error 'dsregcmd.exe is required.'; exit 3 }
if (($TriggerDeviceJoin -or $RestartIdentityServices) -and -not $DryRun -and -not (Test-Administrator)) { Write-Error 'Run from an elevated PowerShell session for service or scheduled-task repairs.'; exit 4 }

$runPath = Join-Path $OutputPath (Get-Date -Format 'yyyyMMdd_HHmmss')
New-Item -ItemType Directory -Path $runPath -Force | Out-Null
$logPath = Join-Path $runPath 'repair.log'
$beforePath = Join-Path $runPath 'before.json'
$afterPath = Join-Path $runPath 'after.json'
$debugPath = Join-Path $runPath 'dsregcmd-debug.txt'

function Write-Log([string]$Message) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message" | Tee-Object -FilePath $logPath -Append
}
function Invoke-RepairAction([string]$Description,[scriptblock]$Script) {
    $script:Actions++
    Write-Log "ACTION: $Description"
    if ($DryRun) { Write-Log "DRY-RUN: $Description"; return }
    try {
        $result = & $Script 2>&1
        if ($null -ne $result) { $result | Out-String | Add-Content $logPath }
        Write-Log "SUCCESS: $Description"
    } catch {
        $script:Failures++
        Write-Log "FAILED: $Description - $($_.Exception.Message)"
    }
}
function Get-JoinState {
    $statusOutput = & dsregcmd.exe /status 2>&1 | Out-String
    $services = @(Get-Service TokenBroker,wlidsvc,NgcCtnrSvc,dmwappushservice -ErrorAction SilentlyContinue | Select-Object Name,Status,StartType)
    $tasks = @()
    if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
        foreach ($task in @(Get-ScheduledTask -TaskPath '\Microsoft\Windows\Workplace Join\' -ErrorAction SilentlyContinue)) {
            $info = Get-ScheduledTaskInfo -InputObject $task -ErrorAction SilentlyContinue
            $tasks += [pscustomobject]@{ TaskName=$task.TaskName; State=$task.State; LastRunTime=$info.LastRunTime; LastTaskResult=$info.LastTaskResult }
        }
    }
    [pscustomobject]@{ Collected=Get-Date; DsregStatus=$statusOutput; Services=$services; WorkplaceJoinTasks=$tasks }
}

$beforeState = Get-JoinState
$beforeState | ConvertTo-Json -Depth 7 | Set-Content $beforePath -Encoding UTF8
$beforeTask = $beforeState.WorkplaceJoinTasks | Where-Object TaskName -eq 'Automatic-Device-Join' | Select-Object -First 1
Write-Log "Saved pre-repair join evidence to $beforePath"

if (-not $DryRun -and -not $Yes) {
    if ((Read-Host 'Apply selected Entra join repairs? Type YES') -cne 'YES') { Write-Log 'Repair cancelled.'; exit 10 }
}

if ($RestartIdentityServices) {
    foreach ($serviceName in 'TokenBroker','wlidsvc','NgcCtnrSvc','dmwappushservice') {
        if (Get-Service $serviceName -ErrorAction SilentlyContinue) {
            Invoke-RepairAction "Starting or restarting $serviceName" {
                $service = Get-Service $serviceName -ErrorAction Stop
                if ($service.Status -eq 'Running') { Restart-Service $serviceName -Force } else { Start-Service $serviceName }
            }
        } else {
            Write-Log "INFO: service $serviceName is not installed on this device."
        }
    }
}
if ($RefreshPrt) {
    Invoke-RepairAction 'Requesting Primary Refresh Token renewal' {
        $output = & dsregcmd.exe /refreshprt 2>&1
        $output | Set-Content (Join-Path $runPath 'refresh-prt.txt') -Encoding UTF8
        if ($LASTEXITCODE -ne 0) { throw "dsregcmd /refreshprt exited with code $LASTEXITCODE." }
    }
}
if ($TriggerDeviceJoin) {
    Invoke-RepairAction 'Starting Automatic-Device-Join task' {
        $task = Get-ScheduledTask -TaskPath '\Microsoft\Windows\Workplace Join\' -TaskName 'Automatic-Device-Join' -ErrorAction Stop
        Start-ScheduledTask -InputObject $task
    }
}
if ($RunDebugDiagnostics) {
    Invoke-RepairAction 'Collecting detailed device-registration diagnostics' {
        $output = & dsregcmd.exe /status /debug 2>&1
        $output | Set-Content $debugPath -Encoding UTF8
        if ($LASTEXITCODE -ne 0) { throw "dsregcmd /status /debug exited with code $LASTEXITCODE." }
    }
}

if (-not $DryRun) { Start-Sleep -Seconds 5 }
$afterState = Get-JoinState
$afterState | ConvertTo-Json -Depth 7 | Set-Content $afterPath -Encoding UTF8

if (-not $DryRun) {
    if ($RefreshPrt -and $afterState.DsregStatus -notmatch 'AzureAdPrt\s*:\s*YES') { $script:VerificationFailures++; Write-Log 'VERIFY FAILED: AzureAdPrt is not YES after the refresh request.' }
    if ($TriggerDeviceJoin) {
        $afterTask = $afterState.WorkplaceJoinTasks | Where-Object TaskName -eq 'Automatic-Device-Join' | Select-Object -First 1
        if (-not $afterTask) { $script:VerificationFailures++; Write-Log 'VERIFY FAILED: Automatic-Device-Join task was not found after execution.' }
        elseif ($beforeTask -and $afterTask.LastRunTime -le $beforeTask.LastRunTime) { $script:VerificationFailures++; Write-Log 'VERIFY FAILED: Automatic-Device-Join LastRunTime did not advance.' }
    }
    if ($RestartIdentityServices) {
        foreach ($service in $afterState.Services) {
            if ($service.StartType -ne 'Disabled' -and $service.Status -ne 'Running') { $script:VerificationFailures++; Write-Log "VERIFY FAILED: $($service.Name) is not running." }
        }
    }
    if ($RunDebugDiagnostics -and (-not (Test-Path $debugPath) -or (Get-Item $debugPath).Length -eq 0)) { $script:VerificationFailures++; Write-Log 'VERIFY FAILED: debug diagnostics file is missing or empty.' }
}

if ($script:Failures -gt 0) { exit 20 }
if ($script:VerificationFailures -gt 0) { exit 30 }
Write-Log "Workflow completed. Actions: $script:Actions; DryRun: $DryRun"
exit 0
