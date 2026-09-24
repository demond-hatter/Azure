#Requires -Modules Az.Accounts, Az.ResourceGraph

<#
.SYNOPSIS
    Triggers a SQL Server migration assessment for all connected Azure Arc-enabled SQL Server instances.

.DESCRIPTION
    SQL Server enabled by Azure Arc automatically produces a migration assessment (cloud
    readiness, risks/mitigations, target sizing, and price estimates) on a weekly schedule.
    This script lets you trigger that assessment on demand for every Arc-connected SQL Server
    Engine instance (Microsoft.AzureArcData/sqlServerInstances, properties.serviceType ==
    'Engine') that is currently reporting a "Connected" status, across one or more subscriptions.

    It works by:
      1. Using Azure Resource Graph to discover all sqlServerInstances resources whose
         properties.status is 'Connected' and properties.serviceType is 'Engine' (optionally
         filtered by subscription/resource group).
      2. Calling the ARM action:
           POST /{resourceId}/runMigrationAssessment?api-version=<api-version>
         for each discovered instance via Invoke-AzRestMethod.
      3. Reporting the resulting job status (e.g. InProgress) for each instance.

    Reference: https://learn.microsoft.com/sql/sql-server/azure-arc/migration-assessment
    ARM action: Microsoft.AzureArcData/sqlServerInstances/runMigrationAssessment (introduced in
    api-version 2024-05-01-preview, available as a stable API starting 2026-01-01).
.NOTES
	Contributor: Demond Hatter - Sr. Cloud Solution Architect - Microsoft Corporation

	This sample script is not supported under any Microsoft standard support program or service. 

	The sample script is provided AS IS without warranty of any kind. Microsoft further disclaims 
	all implied warranties including, without limitation, any implied warranties of merchantability 
	or of fitness for a particular purpose. The entire risk arising out of the use or performance of 
	the sample scripts and documentation remains with you. In no event shall Microsoft, its authors, 
	or anyone else involved in the creation, production, or delivery of the scripts be liable for any 
	damages whatsoever (including, without limitation, damages for loss of business profits, business 
	interruption, loss of business information, or other pecuniary loss) arising out of the use of or 
	inability to use the sample scripts or documentation, even if Microsoft has been advised of the 
	possibility of such damages
.PARAMETER SubscriptionId
    One or more subscription IDs to scan. Defaults to all subscriptions the signed-in
    principal can access.

.PARAMETER ResourceGroupName
    Optional resource group name filter. If omitted, all resource groups are scanned.

.PARAMETER ApiVersion
    The Microsoft.AzureArcData API version to use for the runMigrationAssessment action.
    Defaults to '2026-01-01' (stable). Use an api-version of 2024-05-01-preview or later if
    you need to target a specific preview.

.PARAMETER TenantId
    Optional Microsoft Entra ID tenant ID to sign in to (or to filter subscription discovery
    to) when the signed-in account has access to multiple tenants.

.PARAMETER WhatIf
    Show which Arc SQL Server instances would be assessed, without actually triggering the
    assessment.

.EXAMPLE
    .\Start-ArcSqlMigrationAssessment.ps1

    Triggers a migration assessment for every connected Arc SQL Server instance across all
    accessible subscriptions.

.EXAMPLE
    .\Start-ArcSqlMigrationAssessment.ps1 -SubscriptionId '00000000-0000-0000-0000-000000000000' -ResourceGroupName 'rg-sql-arc'

    Scopes discovery to a single subscription and resource group.

.EXAMPLE
    .\Start-ArcSqlMigrationAssessment.ps1 -WhatIf

    Lists the connected Arc SQL Server instances that would be assessed, without calling the API.

.NOTES
    Requires:
      - Az.Accounts and Az.ResourceGraph modules (Install-Module Az.Accounts, Az.ResourceGraph)
      - An authenticated Azure context (Connect-AzAccount)
      - 'Microsoft.AzureArcData/sqlServerInstances/runMigrationAssessment/action' permission on
        each target resource (for example, the Azure Hybrid Database Administrator role or
        Contributor).
      - Each SQL Server instance must meet the assessment prerequisites: Windows-based SQL
        Server connected via Arc, WindowsAgent.SqlServer extension 1.1.2594.118+, and
        connectivity to telemetry.{region}.arcdataservices.com.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [string[]] $SubscriptionId,

    [Parameter()]
    [string] $ResourceGroupName,

    [Parameter()]
    [string] $ApiVersion = '2026-01-01',

    [Parameter()]
    [string] $TenantId
)

$ErrorActionPreference = 'Stop'

function Assert-AzContext {
    param([string] $TenantId)

    $context = Get-AzContext
    if (-not $context -or ($TenantId -and $context.Tenant.Id -ne $TenantId)) {
        Write-Verbose 'No matching active Azure context found. Prompting for sign-in...'
        $connectParams = @{}
        if ($TenantId) {
            $connectParams['TenantId'] = $TenantId
        }
        Connect-AzAccount @connectParams | Out-Null
    }
}

function Get-TargetSubscriptions {
    param(
        [string[]] $RequestedSubscriptionIds,
        [string]   $TenantId
    )

    if ($RequestedSubscriptionIds) {
        return $RequestedSubscriptionIds
    }

    Write-Verbose 'No -SubscriptionId supplied; enumerating all accessible subscriptions.'
    $subscriptions = Get-AzSubscription
    if ($TenantId) {
        $subscriptions = $subscriptions | Where-Object { $_.TenantId -eq $TenantId }
    }
    return $subscriptions.Id
}

function Get-ConnectedArcSqlServerInstances {
    param(
        [string[]] $SubscriptionIds,
        [string]   $ResourceGroupFilter
    )

    $query = @"
Resources
| where type =~ 'microsoft.azurearcdata/sqlserverinstances'
| where tostring(properties.status) =~ 'Connected'
| where tostring(properties.serviceType) =~ 'Engine'
"@

    if ($ResourceGroupFilter) {
        $query += "`n| where resourceGroup =~ '$ResourceGroupFilter'"
    }

    $query += "`n| project id, name, resourceGroup, subscriptionId, location, instanceName = properties.instanceName, status = properties.status, serviceType = properties.serviceType"

    Write-Verbose "Running Azure Resource Graph query across $($SubscriptionIds.Count) subscription(s)."

    $results = @()
    $page = Search-AzGraph -Query $query -Subscription $SubscriptionIds -First 1000
    $results += $page
    $skip = $page.Count

    while ($page.Count -eq 1000) {
        $page = Search-AzGraph -Query $query -Subscription $SubscriptionIds -First 1000 -Skip $skip
        $results += $page
        $skip += $page.Count
    }

    return $results
}

# --- Main ---

Assert-AzContext -TenantId $TenantId

$subscriptions = Get-TargetSubscriptions -RequestedSubscriptionIds $SubscriptionId -TenantId $TenantId
if (-not $subscriptions -or $subscriptions.Count -eq 0) {
    Write-Warning 'No subscriptions found or accessible. Exiting.'
    return
}

Write-Host "Discovering connected Arc SQL Server Engine instances in $($subscriptions.Count) subscription(s)..." -ForegroundColor Cyan

$instances = Get-ConnectedArcSqlServerInstances -SubscriptionIds $subscriptions -ResourceGroupFilter $ResourceGroupName

if (-not $instances -or $instances.Count -eq 0) {
    Write-Warning 'No connected Arc-enabled SQL Server Engine instances were found in the given scope.'
    return
}

Write-Host "Found $($instances.Count) connected Arc SQL Server Engine instance(s)." -ForegroundColor Cyan

$results = foreach ($instance in $instances) {

    $resourceId = $instance.id
    $target = "$($instance.name) (resource group: $($instance.resourceGroup), subscription: $($instance.subscriptionId))"

    if (-not $PSCmdlet.ShouldProcess($target, 'Trigger SQL Server migration assessment')) {
        continue
    }

    Write-Host "Triggering migration assessment for $target..." -ForegroundColor Yellow

    try {
        $uri = "$resourceId/runMigrationAssessment?api-version=$ApiVersion"
        $response = Invoke-AzRestMethod -Path $uri -Method POST

        if ($response.StatusCode -in 200, 202) {
            $body = $null
            if ($response.Content) {
                $body = $response.Content | ConvertFrom-Json
            }

            [pscustomobject]@{
                InstanceName   = $instance.name
                ServiceType    = $instance.serviceType
                ResourceGroup  = $instance.resourceGroup
                SubscriptionId = $instance.subscriptionId
                StatusCode     = $response.StatusCode
                JobStatus      = $body.jobStatus
                Result         = 'Triggered'
                Error          = $null
            }
        }
        else {
            [pscustomobject]@{
                InstanceName   = $instance.name
                ServiceType    = $instance.serviceType
                ResourceGroup  = $instance.resourceGroup
                SubscriptionId = $instance.subscriptionId
                StatusCode     = $response.StatusCode
                JobStatus      = $null
                Result         = 'Failed'
                Error          = $response.Content
            }
        }
    }
    catch {
        [pscustomobject]@{
            InstanceName   = $instance.name
            ServiceType    = $instance.serviceType
            ResourceGroup  = $instance.resourceGroup
            SubscriptionId = $instance.subscriptionId
            StatusCode     = $null
            JobStatus      = $null
            Result         = 'Error'
            Error          = $_.Exception.Message
        }
    }
}

$results | Format-Table -AutoSize

$failedCount = ($results | Where-Object { $_.Result -ne 'Triggered' }).Count
if ($failedCount -gt 0) {
    Write-Warning "$failedCount of $($results.Count) assessment trigger(s) did not succeed. See the Error column above."
}
else {
    Write-Host "Successfully triggered migration assessments for all $($results.Count) instance(s)." -ForegroundColor Green
}
