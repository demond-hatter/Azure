<#
.SYNOPSIS
    Disable Azure Arc Windows Benefits for all eligible servers in a subscription, resource group, or by machine name or tag.
.DESCRIPTION
    This script will enable Azure Arc Windows Benefits for all eligible ARC enabled servers within a specified subscription, resource group, or by machine name or tag.
.NOTES
	Author: Demond Hatter - Sr. Cloud Solution Architect - Microsoft

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
.PARAMETER $tenantId
    The tenant ID to scan for Arc Enabled Servers that are eligible for Azure Arc Windows Benefits
.PARAMETER $subscriptionId 
    The subscription to scan for Arc Enabled Servers that are eligible for Azure Arc Windows Benefits
.PARAMETER resourceGroupName
    The name of the resource group to scan for Arc Enabled Servers that are eligible for Azure Arc Windows Benefits
.PARAMETER machinename
    The name of the Arc Enabled Server to set the Azure Arc Windows Benefits
.PARAMETER tagName
    The name of the tag to filter Arc Enabled Servers that are eligible for Azure Arc Windows Benefits
.PARAMETER tagValue
    The value of the tag to filter Arc Enabled Servers that are eligible for Azure Arc Windows Benefits
#>
function Update-FeatureFlag {
    [CmdletBinding(DefaultParameterSetName = 'SubscriptionSet')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'SubscriptionSet', Position = 0)]
        [Parameter(Mandatory = $true, ParameterSetName = 'ResourceGroupSet', Position = 0)]
        [Parameter(Mandatory = $true, ParameterSetName = 'MachineSet', Position = 0)]
        [Parameter(Mandatory = $true, ParameterSetName = 'TagSet', Position = 0)]
        [string]$tenantId,

        [Parameter(Mandatory = $true, ParameterSetName = 'SubscriptionSet', Position = 1)]
        [Parameter(Mandatory = $true, ParameterSetName = 'ResourceGroupSet', Position = 1)]
        [Parameter(Mandatory = $true, ParameterSetName = 'MachineSet', Position = 1)]
        [Parameter(Mandatory = $true, ParameterSetName = 'TagSet', Position = 0)]
        [string]$subscriptionId,

        [Parameter(Mandatory = $false, ParameterSetName = 'SubscriptionSet', Position = 2)]
        [Parameter(Mandatory = $true, ParameterSetName = 'ResourceGroupSet', Position = 2)]
        [Parameter(Mandatory = $false, ParameterSetName = 'MachineSet', Position = 2)]
        [string]$resourceGroupName,

        [Parameter(Mandatory = $false, ParameterSetName = 'SubscriptionSet', Position = 3)]
        [Parameter(Mandatory = $false, ParameterSetName = 'ResourceGroupSet', Position = 3)]
        [Parameter(Mandatory = $true, ParameterSetName = 'MachineSet', Position = 3)]
        [string]$machineName,
        
        [Parameter(Mandatory = $false, ParameterSetName = 'SubscriptionSet', Position = 4)]
        [Parameter(Mandatory = $true, ParameterSetName = 'TagSet', Position = 2)]
        [string]$tagName,
        
        [Parameter(Mandatory = $false, ParameterSetName = 'SubscriptionSet', Position = 5)]
        [Parameter(Mandatory = $true, ParameterSetName = 'TagSet', Position = 3)]
        [string]$tagValue,
    
        [Parameter(Mandatory = $true, Position = 6)]
        [ValidateSet('LeastPrivilege', 'ClientConnections')]
        [string]$featureFlagName
    )

# update-featureflag.ps1
# Enables the 'LeastPrivilege' feature flag for all Arc-enabled SQL instances in the current subscription.

# Requires: Az.ConnectedKubernetes, Az.SqlVirtualMachine modules

# Connect to Azure if not already connected
if (-not (Get-AzContext)) {
    Connect-AzAccount
}

# Get all Arc-enabled SQL instances
$sqlInstances = Get-AzResource -ResourceType "Microsoft.AzureArcData/sqlServerInstances"

foreach ($instance in $sqlInstances) {
    Write-Host "Enabling LeastPrivilege feature flag for instance: $($instance.Name)"
    
    # Update the feature flag (assuming it's a property in the resource)
    $properties = $instance.Properties
    $properties.featureFlags.LeastPrivilege = $true

    Set-AzResource -ResourceId $instance.ResourceId -Properties $properties -Force

    Write-Host "LeastPrivilege feature flag enabled for $($instance.Name)"
}
}