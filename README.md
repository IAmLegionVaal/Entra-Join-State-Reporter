# Entra Join State Reporter

PowerShell tools for Microsoft Entra device join-state reporting and guarded local registration repairs.

## Report

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Entra_Join_State_Reporter.ps1
```

## Repair

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Entra_Join_State_Repair_Toolkit.ps1 -RefreshPrt -DryRun
```

Examples:

```powershell
.\Entra_Join_State_Repair_Toolkit.ps1 -RefreshPrt
.\Entra_Join_State_Repair_Toolkit.ps1 -TriggerDeviceJoin
.\Entra_Join_State_Repair_Toolkit.ps1 -RestartIdentityServices
.\Entra_Join_State_Repair_Toolkit.ps1 -RunDebugDiagnostics
```

The repair script captures `dsregcmd`, service and scheduled-task state before and after repair and supports `-DryRun`, confirmation, logs and clear exit codes. It does not leave Entra ID, remove workplace accounts or delete device certificates.

## Author

Dewald Pretorius — L2 IT Support Engineer
