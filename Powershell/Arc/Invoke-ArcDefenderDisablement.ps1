<#
.SYNOPSIS
    Disable Azure Defender Plan
.DESCRIPTION
    This script will disable the Defender Plan for the specified VM.  This script can be modified to scan for all Arc Enabled servers in a specific subscription and 
    optionally a resource group and disable the plan for all
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
.PARAMETER subscriptionId
    The subscription to scan for Arc Enabled Servers
.PARAMETER resourceGroup
    The resource group to scan for Arc Enabled Servers 
.PARAMETER vmName
    The VM to disable the defender plan 
.PARAMETER tagValue
    (NOT IMPLEMENTED) The intent is this can be used to search for all resources with a specific tag
#>
[CmdletBinding()]
param (
    [Parameter (Mandatory=$true)]
    [string] $subscriptionId,
    [Parameter (Mandatory=$true)]
    [string] $resourceGroup,
    [Parameter (Mandatory=$false)]
    [string] $vmName,
    [Parameter (Mandatory=$false)]
    [string] $tagName,
    [Parameter (Mandatory=$false)]
    [string] $tagValue
)

## Define variables
    #$arcUrl = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.HybridCompute/machines?api-version=2022-12-27"
    $arcUrl = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.HybridCompute/machines/$vmName/providers/Microsoft.Security/pricings/virtualMachines?api-version=2024-01-01"

## Set access token for the API request
    Connect-AzAccount -Subscription $subscriptionId
    $accessToken = (Get-AzAccessToken).Token
    $expireson = (Get-AzAccessToken).ExpiresOn.LocalDateTime

    $headers = @{
        "Authorization" = "Bearer $accessToken"
        "Content-Type"  = "application/json"
    }

# Get all ARC machines in the resource group
    try {
        do{
            $arcResponse = Invoke-RestMethod -Method Get -Uri $arcUrl -Headers $headers
            ##$arcResponseMachines += $arcResponse.value ## for resourcegroup scanning
            $arcResponseMachines += $arcResponse ## when searching for a single VM
            $arcUrl = $arcResponse.nextLink
        } while (![string]::IsNullOrEmpty($arcUrl))
    }
    catch {
        Write-Host "Failed to Get resources!" -ForegroundColor Red
        Write-Host "Response StatusCode:" $_.Exception.Response.StatusCode.value__  -ForegroundColor Red
        Write-Host "Response StatusDescription:" $_.Exception.Response.StatusDescription -ForegroundColor Red
        Write-Host "Error from response:" $_.ErrorDetails -ForegroundColor Red    
    }

    Write-verbose "Number of Hybrid Machines Found: $($arcResponseMachines.value.count)"

    foreach($arcMachine in $arcResponseMachines)
    {
        $url = "https://management.azure.com$($arcMachine.id)/providers/Microsoft.Security/pricings/virtualMachines?api-version=2024-01-01"
        $resp = Invoke-RestMethod -Method Delete -Uri $url -Headers $headers 
        Write-Host "Arc enabled VM: $($arcMachine.name). Defender plan: $($resp.properties.subPlan), $($resp.properties.pricingTier)"
    }

<#
    ## This will remove the defender plan for the machine(s)
    foreach($arcMachine in $arcResponseMachines)
    {
        $url = "https://management.azure.com$($arcMachine.id)/providers/Microsoft.Security/pricings/virtualMachines?api-version=2024-01-01"
        Write-verbose "Disabling Defender plan: ($($resp.properties.subPlan), $($resp.properties.pricingTier)) for Arc enabled VM: $($arcMachine.name)"

        ## Invoke API request to disable the P1 plan on the VM
            Invoke-RestMethod -Method Delete -Uri $url -Headers $headers
    }
#>

<#

    ## The following can be used to set a specific plan for the machine(s)
    $body = @{
         properties = @{
            pricingTier = "Standard"
            subPlan = "P1"
        }
    } | ConvertTo-Json

    foreach($arcMachine in $arcResponseMachines)
    {
        $url = "https://management.azure.com$($arcMachine.id)/providers/Microsoft.Security/pricings/virtualMachines?api-version=2024-01-01"
        Write-verbose "Setting Defender plan: ($($body.properties.subPlan), $($body.properties.pricingTier)) for Arc enabled VM: $($arcMachine.name)"

            ## Invoke API request to enable the P1 plan on the VM
            Invoke-RestMethod -Method Put -Uri $url -Body $body -Headers $headers
    }

#>