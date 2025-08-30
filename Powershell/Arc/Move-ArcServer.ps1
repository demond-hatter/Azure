<#
.SYNOPSIS
    Move Azure Arc Servers
.DESCRIPTION
    This script will move Azure Arc Servers that have SQL installed to a new resource group
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
.PARAMETER targetsubscriptionId
    The target subscription to move servers to
.PARAMETER targetResourceGroup
    The target resource group to move servers to
.PARAMETER tenantId
    The tenant to connect to
.PARAMETER batchSize
    The number of servers to act upon.  Regardless of the number of servers that match the search filter, it will only move servers based
    on this parameter.  The default is 10
#>
function Move-ArcServer {
    [CmdletBinding()]
    param (
        [Parameter (Mandatory=$true, ParameterSetName='full', position=0)]
        [string] $tenantId,
        [Parameter (Mandatory=$true, ParameterSetName='full', position=1)]
        [Parameter (Mandatory=$true, ParameterSetName='direct', position=1)]
        [string] $targetsubscriptionId,
        [Parameter (Mandatory=$true, ParameterSetName='full')]
        [Parameter (Mandatory=$true, ParameterSetName='direct')]
        [string] $targetResourceGroup,
        [Parameter (Mandatory=$false, ParameterSetName='full')]
        [Parameter (Mandatory=$false, ParameterSetName='direct')]
        [int] $batchSize = 10        
     )
    
        ## Connect to Azure
        write-verbose "Connecting to Azure"
        if ($PSBoundParameters.ContainsKey("tenantId")){
           $ctx = Connect-AzAccount -Subscription $targetsubscriptionId -Tenant $tenantId
         } else {
           $ctx = Connect-AzAccount -Subscription $targetsubscriptionId
         } 
    
                
        ## Define query for Arc Resources
        $ArcQuery = "resources
        | where type == 'microsoft.hybridcompute/machines'
        | where resourceGroup !~ '$targetResourceGroup'
        "
    
      <#  if ($PSBoundParameters.ContainsKey("targetsubscriptionId")){
            $ArcQuery += "| where subscriptionId == '$targetsubscriptionId'
            "
        }
      #>

    $ArcQuery += "| extend props = properties['detectedProperties'] 
    | extend hasSql = props.mssqldiscovered
    | extend status = properties['status']
    | where tostring(hasSql) =~ 'true'
    | where status !~ 'disconnected'
    | project machineName = name, id, resourceGroup, subscriptionId, hasSql, status
    | limit $batchSize"
    
        ## Execute query to retrieve Arc servers
        Write-Verbose "Executing resource graph query"
        Write-Debug "Executing KQL query: `n $ArcQuery"
            $resources = Search-AzGraph -Query "$($ArcQuery)"
           
        ## Iterate through results 
        Write-Verbose "Total query results of target Servers to move: $($resources.Count). Iterating through results..."
        foreach ($resource in $resources){
            write-verbose "Moving Server: $($resource.machineName)"
            Move-AzResource -ResourceId $resource.id -DestinationResourceGroupName $TargetResourceGroup -Force
        }
    }