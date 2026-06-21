# Entra Join State Reporter

PowerShell tooling for Microsoft Entra device join-state reporting and guarded local registration recovery.

## Scripts

- `Entra_Join_State_Reporter.ps1` — read-only join-state reporting.
- `Entra_Join_State_Repair_Toolkit.ps1` — targeted Primary Refresh Token, device-join task, service, and diagnostic actions.

The repair script does not leave Entra ID, remove workplace accounts, delete device certificates, or clear user identity caches.

## Repair actions

- `-RefreshPrt` — requests a Primary Refresh Token renewal in the current user context.
- `-TriggerDeviceJoin` — starts the built-in `Automatic-Device-Join` scheduled task.
- `-RestartIdentityServices` — starts or restarts available identity-related services.
- `-RunDebugDiagnostics` — writes detailed `dsregcmd /status /debug` output.

Service and scheduled-task actions require elevation. A PRT refresh can be run without elevation but must run in the affected user's session.

## Examples

Preview a PRT refresh:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Entra_Join_State_Repair_Toolkit.ps1 `
  -RefreshPrt -DryRun
```

Run a device-registration recovery sequence:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Entra_Join_State_Repair_Toolkit.ps1 `
  -RestartIdentityServices -TriggerDeviceJoin -RunDebugDiagnostics -Yes
```

Omit `-Yes` to require typing `YES`.

## Evidence and verification

Each run writes `before.json`, `after.json`, and `repair.log` to a timestamped directory under `%ProgramData%\EntraJoinRepair` unless `-OutputPath` is supplied. Additional files include `refresh-prt.txt` and `dsregcmd-debug.txt` when those actions are selected.

Verification checks the post-action `AzureAdPrt` state, scheduled-task LastRunTime, service state, and debug-output creation. A PRT can remain unavailable because of tenant policy, network, authentication, or device-registration problems; in that case the script exits with verification failure rather than claiming success.

`-DryRun` records intended actions without applying or verifying them.

## Exit codes

| Code | Meaning |
|---:|---|
| 0 | Completed successfully, including a successful dry run |
| 2 | Invalid arguments |
| 3 | Unsupported platform or missing `dsregcmd.exe` |
| 4 | Elevation required for service or task actions |
| 10 | User cancelled |
| 20 | One or more actions failed |
| 30 | Post-action verification failed |

## Validation status

The scripts were source-reviewed during this update. They were not runtime-tested on an Entra-joined Windows device.

## Author

Dewald Pretorius — L2 IT Support Engineer
