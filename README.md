# Azure Subscription KeepAlive Tagger

This repository contains a PowerShell script that applies a
subscription-level tag named `keepalive` to all enabled subscriptions in a
tenant.

The tag value is set to today's date in `yyyyMMdd` format (for example, `20260406`).

## What the Script Does

Script: `set-keepalive-tags.ps1`

Behavior:

- Validates that Azure CLI (`az`) is installed and available in `PATH`.
- Ensures you are authenticated to Azure (`az login` if needed).
- Reads all subscriptions available to your signed-in account.
  - Tries `az account subscription list` first.
  - Falls back to `az account list --all` for CLI compatibility.
- Filters subscriptions to:
  - The target tenant (`-TenantId`, or your current tenant if omitted)
  - State = `Enabled` (case-insensitive)
  - Compatible tenant fields (`tenantId` or `homeTenantId`)
- Applies or updates the tag on each subscription using:
  - `az tag update --operation Merge`
- Prints a success/failure summary and exits with:
  - `0` if all updates succeed
  - `1` if one or more updates fail

The script merges tags, so existing tags are preserved and only the specified
tag is added/updated.

## Prerequisites

1. PowerShell 7+ (recommended) or Windows PowerShell 5.1.
2. Azure CLI installed and signed in.
3. Permissions to write tags at subscription scope for each target subscription.

Minimum effective permission is typically one of:

- `Owner`
- `Contributor`
- A custom role with `Microsoft.Resources/tags/*` permissions at subscription
  scope

## Script Parameters

- `-TenantId` (optional)
  - Target tenant ID (GUID).
  - If omitted, the script uses the tenant from your current Azure CLI context.

- `-TagName` (optional)
  - Defaults to `keepalive`.

- `-TagValue` (optional)
  - If omitted, script uses `Get-Date -Format "yyyyMMdd"`.

- `-WhatIf` (optional switch)
  - Preview mode. Displays the `az tag update` operations without making
    changes.

## Usage Examples

### 1) Dry run against a specific tenant

```powershell
.\set-keepalive-tags.ps1 -TenantId "00000000-0000-0000-0000-000000000000" -WhatIf
```

### 2) Apply keepalive tag using today's date

```powershell
.\set-keepalive-tags.ps1 -TenantId "00000000-0000-0000-0000-000000000000"
```

### 3) Use current Azure CLI tenant automatically

```powershell
.\set-keepalive-tags.ps1
```

### 4) Override tag name and value

```powershell
.\set-keepalive-tags.ps1 -TenantId "00000000-0000-0000-0000-000000000000" `
  -TagName "keepalive" -TagValue "20260406"
```

## Typical Output

```text
No tenant supplied; using current tenant: <tenant-guid>
Found 12 enabled subscription(s) to update in tenant '<tenant-guid>'.
Applying tag: keepalive=20260406
[Subscription-A] <subscription-guid>
  Updated
[Subscription-B] <subscription-guid>
  Updated
Done. Successful: 12, Failed: 0
```

If one or more subscriptions fail (for example, missing permissions), the
script logs warnings and returns a non-zero exit code.

## Operational Notes

- The script only updates subscriptions in `Enabled` state.
- The command is idempotent for the same day/value; re-running with the same
  value does not create duplicate tags.
- Existing tags are preserved because `Merge` is used.
- If your account can see subscriptions across multiple tenants, always supply
  `-TenantId` for explicit targeting.
- Subscription discovery is designed to work across WSL and Windows PowerShell
  hosts with different Azure CLI output shapes.

## Why is this Necessary?

MCAPS Enforcement policy: Azure Managed Tenant Cost Optimization Control

>Subscriptions which are inactive for 90 days will be cancelled.  Subscription activity is determined by management operations on Azure resources (i.e. activity log entries) performed by a user account.  Actions performed by service accounts are not evaluated.  Subscription owners will receive an email notification at time of cancellation.  If the subscription is still needed, the user can reactivate it using the Azure portal.  Subscriptions not reactivated will be deleted 90 days after cancellation.

## Troubleshooting

### `az` not found

Install Azure CLI and ensure it is in your shell `PATH`.

### Authentication errors

Run:

```powershell
az login
```

If needed:

```powershell
az login --tenant "<tenant-guid>"
```

### Authorization/tag update failures

Verify role assignments at subscription scope and confirm the role includes tag
write permissions.

### No subscriptions found

Check that:

- You are logged into the expected tenant.
- Subscriptions are in `Enabled` state.
- Your account has visibility to those subscriptions.

If this occurs only in the VS Code PowerShell terminal, compare behavior with:

```powershell
pwsh -NoProfile -File .\set-keepalive-tags.ps1 -WhatIf
```

Then verify host and CLI versions in the same failing terminal:

```powershell
$PSVersionTable.PSVersion
az version
```

## Running on a Schedule (Optional)

You can schedule this script with:

- Windows Task Scheduler
- Azure Automation Hybrid Worker
- GitHub Actions runner (self-hosted or hosted with `az login` setup)

When scheduled, monitor exit code and logs to detect failed subscription
updates.
