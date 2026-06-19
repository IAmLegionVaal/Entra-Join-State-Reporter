#requires -Version 5.1
[CmdletBinding()]
param([string]$OutputPath)
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
if([string]::IsNullOrWhiteSpace($OutputPath)){$OutputPath=Join-Path ([Environment]::GetFolderPath('Desktop')) 'Entra_Join_Reports'}
New-Item -ItemType Directory -Path $OutputPath -Force|Out-Null
$raw=dsregcmd.exe /status 2>$null
$raw|Out-File (Join-Path $OutputPath "dsregcmd_$stamp.txt") -Encoding UTF8
$lookup=@{}
foreach($line in $raw){if($line -match '^\s*([^:]+)\s*:\s*(.+)$'){$lookup[$matches[1].Trim()]=$matches[2].Trim()}}
$cs=Get-CimInstance Win32_ComputerSystem
$summary=[PSCustomObject]@{Computer=$env:COMPUTERNAME;Domain=$cs.Domain;PartOfDomain=$cs.PartOfDomain;AzureAdJoined=$lookup['AzureAdJoined'];EnterpriseJoined=$lookup['EnterpriseJoined'];DomainJoined=$lookup['DomainJoined'];WorkplaceJoined=$lookup['WorkplaceJoined'];DeviceId=$lookup['DeviceId'];TenantName=$lookup['TenantName'];AzureAdPrt=$lookup['AzureAdPrt'];Generated=Get-Date}
$summary|ConvertTo-Json|Set-Content (Join-Path $OutputPath "entra_join_summary_$stamp.json") -Encoding UTF8
$html="<h1>Entra Join State - $env:COMPUTERNAME</h1><p>Generated $(Get-Date)</p>$(@($summary)|ConvertTo-Html -Fragment)"
$html|ConvertTo-Html -Title 'Entra Join State'|Set-Content (Join-Path $OutputPath "entra_join_summary_$stamp.html") -Encoding UTF8
$summary|Format-List
Write-Host "Reports saved to: $OutputPath" -ForegroundColor Green
