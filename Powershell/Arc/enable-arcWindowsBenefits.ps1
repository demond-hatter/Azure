<#
.SYNOPSIS
    Enable Azure Arc Windows Benefits for all eligible servers in a subscription, resource group, or by machine name or tag.
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
function Enable-ArcWindowsBenefits {
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
        [string]$tagValue
    )

# Connect to Azure 
    write-verbose "Connecting to Azure with Tenant ID: $tenantId and Subscription ID: $subscriptionId"
        Connect-AzAccount -tenant $tenantId -Subscription $subscriptionId
        $context = get-azcontext
        $curprofile       = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile 
        $profileClient = [Microsoft.Azure.Commands.ResourceManager.Common.rmProfileClient]::new( $curprofile ) 
        write-verbose "Acquiring access token for Tenant ID: $($context.Subscription.TenantId)"
            $token         = $profileClient.AcquireAccessToken($context.Subscription.TenantId) 

# Generate Rest API headers
    $headers = @{
        'Content-Type'  = 'application/json'
        Authorization = "Bearer $($token.AccessToken)"
    }

# Get all Azure Arc-enabled servers in the requested scope
    $arcServers = get-hybridComputeMachines @PSBoundParameters

    # Set the Azure Arc Windows Benefits for the Arc-enabled servers    
    Set-ArcWindowsBenefits -Header $headers -Resources $arcServers
}

function get-hybridComputeMachines {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$tenantId,
        
        [Parameter(Mandatory = $false)]
        [string]$subscriptionId,

        [Parameter(Mandatory = $false)]
        [string]$resourceGroupName,

        [Parameter(Mandatory = $false)]
        [string]$machineName,

        [Parameter(Mandatory = $false)]
        [string]$tagName,
        
        [Parameter(Mandatory = $false)]
        [string]$tagValue
    )

    $resources = $null

    #Get the Azure Arc-enabled servers based on the provided parameters
    switch ($PSBoundParameters.keys) {
        'resourceGroupName' {
            $resources = Get-AzResource -ResourceType "Microsoft.HybridCompute/machines" -ResourceGroupName $resourceGroupName
        } 'machineName' {
            if ($PSBoundParameters.ContainsKey('resourceGroupName')) {
                $resources = Get-AzResource -ResourceType "Microsoft.HybridCompute/machines" -ResourceGroupName $resourceGroupName -Name $machineName
            } else {
                $resources = Get-AzResource -ResourceType "Microsoft.HybridCompute/machines" -Name $machineName
            }
      
        } 'tagName' {
            $resources = Get-AzResource -ResourceType "Microsoft.HybridCompute/machines" -TagName $tagName -TagValue $tagValue
        } default {
            $resources = Get-AzResource -ResourceType "Microsoft.HybridCompute/machines"
        }
    }

    if (-not $resources) {
        Write-Verbose "No Azure Arc-enabled servers found."
        return $null
    } else {
        return $resources
    }
}

function Set-ArcWindowsBenefits {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$header,

        [Parameter(Mandatory = $true)]
        [Microsoft.Azure.Commands.ResourceManager.Cmdlets.SdkModels.PSResource[]]$resources
    )

    foreach ($resource in $resources) {
        $resourceGroupName = $resource.ResourceGroupName
        $machineName = $resource.Name
        $location = $resource.Location
        $subscriptionId = $resource.SubscriptionId

        Write-Verbose "`nChecking Arc Server: $machineName (RG: $resourceGroupName, Location: $location)"

        $licenseProfileUri = [System.Uri]::new("https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.HybridCompute/machines/$machineName/licenseProfiles/default?api-version=2023-10-03-preview")

        try {
            # Check current license profile
            try {
                $currentLicenseProfile = Invoke-RestMethod -Method GET -Uri $licenseProfileUri.AbsoluteUri -Headers $headers -ErrorAction Stop
            } catch {
                Write-Host " - No license profile exist for $machineName"
            }

            if (-not $currentLicenseProfile.properties.softwareAssurance.softwareAssuranceCustomer -or $currentLicenseProfile.properties.softwareAssurance.softwareAssuranceCustomer -eq $false) {
                # Enable Azure Benefits
                write-host " - Attempting to Enable Azure Benefits for $machineName..."
                $body = @{
                    location = $location;
                    properties = @{
                        softwareAssurance = @{
                            softwareAssuranceCustomer = $true;
                        }
                    }
                } | ConvertTo-Json 

                Invoke-RestMethod -Method PUT -Uri $licenseProfileUri -ContentType "application/json" -Headers $headers -Body $body
                Write-Host " - Azure Benefits enabled successfully."
            } else {
                Write-Host " - Azure Benefits already enabled for $machineName."
            }
        } catch {
            Write-Error " - Could not enable Azure Windows Benefits: $_"
        }
    }
}