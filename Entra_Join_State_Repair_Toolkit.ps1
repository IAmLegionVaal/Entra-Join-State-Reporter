[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
param(
 [switch]$RefreshPrt,
 [switch]$TriggerDeviceJoin,
 [switch]$RestartIdentityServices,
 [switch]$RunDebugDiagnostics,
 [switch]$DryRun,
 [switch]$Yes,
 [string]$OutputPath=(Join-Path $env:ProgramData 'EntraJoinRepair')
)
$ErrorActionPreference='Stop';$script:Failures=0;$script:Actions=0
$run=Join-Path $OutputPath (Get-Date -Format yyyyMMdd_HHmmss);New-Item -ItemType Directory $run -Force|Out-Null
$log=Join-Path $run 'repair.log';$before=Join-Path $run 'before.txt';$after=Join-Path $run 'after.txt'
function Log($m){"$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $m"|Tee-Object -FilePath $log -Append}
function Admin{$p=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent());$p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)}
function State($path){@("Collected: $(Get-Date -Format o)",(& dsregcmd.exe /status|Out-String),(Get-Service TokenBroker,wlidsvc,NgcCtnrSvc,dmwappushservice -ErrorAction SilentlyContinue|Format-Table -Auto|Out-String),(Get-ScheduledTask -TaskPath '\Microsoft\Windows\Workplace Join\' -ErrorAction SilentlyContinue|Select-Object TaskName,State|Format-Table -Auto|Out-String))|Set-Content $path -Encoding UTF8}
function Act($d,[scriptblock]$a){$script:Actions++;Log $d;if($DryRun){Log "DRY-RUN: $d";return};try{&$a;Log "SUCCESS: $d"}catch{$script:Failures++;Log "FAILED: $d - $($_.Exception.Message)"}}
if(-not($RefreshPrt -or $TriggerDeviceJoin -or $RestartIdentityServices -or $RunDebugDiagnostics)){Write-Error 'Choose at least one repair action.';exit 2}
if(($TriggerDeviceJoin -or $RestartIdentityServices) -and -not $DryRun -and -not(Admin)){Write-Error 'Run from elevated PowerShell.';exit 4}
State $before
if(-not $Yes -and -not $DryRun){if((Read-Host 'Apply selected Entra join repairs? Type YES') -ne 'YES'){Log 'Cancelled.';exit 10}}
if($RestartIdentityServices){foreach($s in 'TokenBroker','wlidsvc','NgcCtnrSvc','dmwappushservice'){if(Get-Service $s -ErrorAction SilentlyContinue){Act "Restarting $s" {Restart-Service $s -Force -ErrorAction Stop}}}}
if($RefreshPrt){Act 'Requesting Primary Refresh Token renewal' {& dsregcmd.exe /refreshprt|Out-File (Join-Path $run 'refresh-prt.txt');if($LASTEXITCODE){throw "dsregcmd exited $LASTEXITCODE"}}}
if($TriggerDeviceJoin){$task=Get-ScheduledTask -TaskPath '\Microsoft\Windows\Workplace Join\' -TaskName 'Automatic-Device-Join' -ErrorAction Stop;Act 'Starting Automatic-Device-Join task' {Start-ScheduledTask -InputObject $task}}
if($RunDebugDiagnostics){Act 'Collecting detailed device-registration diagnostics' {& dsregcmd.exe /status /debug|Out-File (Join-Path $run 'dsregcmd-debug.txt')}}
Start-Sleep 4;State $after
if($script:Failures){exit 20};Log "Repair completed. Actions: $script:Actions";exit 0
