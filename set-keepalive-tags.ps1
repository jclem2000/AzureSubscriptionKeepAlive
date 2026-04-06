param(
    [Parameter(Mandatory = $false)]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$TagName = "keepalive",

    [Parameter(Mandatory = $false)]
    [string]$TagValue,

    [Parameter(Mandatory = $false)]
    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Test-AzCli {
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        throw "Azure CLI 'az' is not installed or not in PATH."
    }
}

function Connect-AzLogin {
    param(
        [string]$Tenant
    )

    $null = az account show 2>$null
    if ($LASTEXITCODE -eq 0) {
        return
    }

    if ([string]::IsNullOrWhiteSpace($Tenant)) {
        Write-Host "Not logged in. Running: az login"
        az login | Out-Null
    }
    else {
        Write-Host "Not logged in. Running: az login --tenant $Tenant"
        az login --tenant $Tenant | Out-Null
    }

    if ($LASTEXITCODE -ne 0) {
        throw "Azure login failed."
    }
}

function Get-TargetSubscriptions {
    param(
        [string]$Tenant
    )

    # Prefer newer CLI shape first, then fall back for older CLI versions.
    $allSubsJson = az account subscription list -o json 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($allSubsJson)) {
        $allSubsJson = az account list --all -o json
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to list subscriptions. Azure CLI did not support the attempted account list commands."
        }
    }

    $allSubsRaw = $allSubsJson | ConvertFrom-Json
    $allSubs = @($allSubsRaw) | ForEach-Object {
        $idValue = $null
        $nameValue = $null
        $stateValue = $null
        $tenantValue = $null

        if ($_.PSObject.Properties['subscriptionId']) {
            $idValue = $_.PSObject.Properties['subscriptionId'].Value
        }
        elseif ($_.PSObject.Properties['id']) {
            $idValue = $_.PSObject.Properties['id'].Value
        }

        if ($_.PSObject.Properties['displayName']) {
            $nameValue = $_.PSObject.Properties['displayName'].Value
        }
        elseif ($_.PSObject.Properties['name']) {
            $nameValue = $_.PSObject.Properties['name'].Value
        }

        if ($_.PSObject.Properties['state']) {
            $stateValue = $_.PSObject.Properties['state'].Value
        }

        if ($_.PSObject.Properties['tenantId']) {
            $tenantValue = $_.PSObject.Properties['tenantId'].Value
        }
        elseif ($_.PSObject.Properties['homeTenantId']) {
            $tenantValue = $_.PSObject.Properties['homeTenantId'].Value
        }

        [pscustomobject]@{
            id = $idValue
            name = $nameValue
            state = $stateValue
            tenantId = $tenantValue
        }
    }

    if ([string]::IsNullOrWhiteSpace($Tenant)) {
        $currentAccountJson = az account show -o json
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to read current account context."
        }

        $currentAccount = $currentAccountJson | ConvertFrom-Json
        $Tenant = $currentAccount.tenantId
        Write-Host "No tenant supplied; using current tenant: $Tenant"
    }

    $tenantNormalized = ([string]$Tenant).Trim().ToLowerInvariant()
    $filtered = $allSubs | Where-Object {
        $subTenant = ([string]$_.tenantId).Trim().ToLowerInvariant()
        $subState = ([string]$_.state).Trim().ToLowerInvariant()
        $subTenant -eq $tenantNormalized -and $subState -eq "enabled"
    }

    if (-not $filtered -or $filtered.Count -eq 0) {
        # Some host/CLI combinations can return shapes that don't normalize as expected.
        # Run a direct CLI-side filter as a compatibility fallback.
        $fallbackJson = az account list --all --query "[?(tenantId=='$Tenant' || homeTenantId=='$Tenant') && (state=='Enabled' || state=='enabled')].{id:id,name:name,state:state,tenantId:tenantId}" -o json 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($fallbackJson)) {
            $fallbackSubs = $fallbackJson | ConvertFrom-Json
            if ($fallbackSubs) {
                $filtered = @($fallbackSubs)
            }
        }
    }

    return $filtered
}

Test-AzCli
Connect-AzLogin -Tenant $TenantId

if ([string]::IsNullOrWhiteSpace($TagValue)) {
    # YYYYmmDD equivalent in .NET date formatting is yyyyMMdd.
    $TagValue = Get-Date -Format "yyyyMMdd"
}

$subscriptions = Get-TargetSubscriptions -Tenant $TenantId

$effectiveTenantId = $TenantId
if ([string]::IsNullOrWhiteSpace($effectiveTenantId)) {
    $currentAccountJson = az account show -o json
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($currentAccountJson)) {
        $effectiveTenantId = ($currentAccountJson | ConvertFrom-Json).tenantId
    }
}

if (-not $subscriptions -or $subscriptions.Count -eq 0) {
    Write-Host "No enabled subscriptions found for tenant '$effectiveTenantId'."
    exit 0
}

Write-Host "Found $($subscriptions.Count) enabled subscription(s) to update in tenant '$($subscriptions[0].tenantId)'."
Write-Host "Applying tag: $TagName=$TagValue"

$success = 0
$failed = 0

foreach ($sub in $subscriptions) {
    $scope = "/subscriptions/$($sub.id)"
    Write-Host "[$($sub.name)] $($sub.id)"

    if ($WhatIf) {
        Write-Host "  WhatIf: az tag update --resource-id $scope --operation Merge --tags $TagName=$TagValue"
        continue
    }

    try {
        az tag update --resource-id $scope --operation Merge --tags "$TagName=$TagValue" --only-show-errors -o none
        if ($LASTEXITCODE -ne 0) {
            throw "az tag update failed with exit code $LASTEXITCODE"
        }
        $success++
        Write-Host "  Updated"
    }
    catch {
        $failed++
        Write-Warning "  Failed: $($_.Exception.Message)"
    }
}

Write-Host "Done. Successful: $success, Failed: $failed"

if ($failed -gt 0) {
    exit 1
}
