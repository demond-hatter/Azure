<#
.SYNOPSIS
    Add ESUs to eligible machines
.DESCRIPTION
    This script will Create ESUs for all eligible ARC enabled servers and link them
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
.PARAMETER subscription
    The subscription to scan for Arc Enabled Servers that are eligible for ESUs
.PARAMETER resourceGroup
    The resource group to scan for Arc Enabled Servers that are eligible for ESUs
.PARAMETER licenseState
    The initial state to set the license to.  Valid values are Active or Deactivated
#>
#Requires -Modules Az.ConnectedMachine, Az.Accounts, Az.ResourceGraph
function Add-WindowsESU {
[CmdletBinding()]
param (
    [Parameter (Mandatory=$false)]
    [string] $subscriptionId,
    [Parameter (Mandatory=$false)]
    [string] $resourceGroup,
    [Parameter (Mandatory=$true)]
    [ValidateSet("Activated","Deactivated")]
    [string] $licenseState,
    [Parameter (Mandatory=$false)]
    [string] $billingTagName

)

    ## Set access token for the API request
    write-verbose "Connecting to Azure"
    if ($PSBoundParameters.ContainsKey("subscriptionid")){
        Connect-AzAccount -Subscription $subscriptionid -devicecode
     } else {
        Connect-AzAccount
     } 

        $accessToken = (Get-AzAccessToken).Token
        $expireson = (Get-AzAccessToken).ExpiresOn.LocalDateTime

    ## Define query for Arc Resources
    $ArcQuery = "resources
    | where type == 'microsoft.hybridcompute/machines'
    "

    if ($PSBoundParameters.ContainsKey("subscriptionid")){
        $ArcQuery += "| where subscriptionId == '$subscriptionid'
        "
    }

    if ($PSBoundParameters.ContainsKey("resourceGroup")){
        $ArcQuery += "| where resourceGroup == '$resourceGroup'
        "
    }

 if ($PSBoundParameters.ContainsKey("billingTagName")){
        $ArcQuery += "| extend billingTag = tags.$billingTagName
        "
    }


$ArcQuery += "| extend p = parse_json(properties)
    | extend esuEligibility = p.licenseProfile.esuProfile.esuEligibility
    | extend esuAssignmentState = p.licenseProfile.esuProfile.licenseAssignmentState
    | where esuEligibility == 'Eligible' and esuAssignmentState == 'NotAssigned'
    | extend osSKU = p.osSku, physicalCores=p.detectedProperties.coreCount, model=p.detectedProperties.model
    | extend logicalCores = p.detectedProperties.logicalCoreCount
    | extend esuMinPhysicalCores = case(physicalCores<16, 16, physicalCores)
    | extend esuMinLogicalCores = case(logicalCores<8, 8, logicalCores)
    | extend targetEsuName = strcat(name, '-esu')
    | project machineName = name, subscriptionId, resourceGroup, status = p.status, esuAssignmentState, esuEligibility, type, location, osSKU, model, physicalCores,esuMinPhysicalCores, logicalCores, esuMinLogicalCores, targetEsuName
    | order by location, machineName"

    ## Execute query to retrieve Arc servers eligible for ESU
    Write-Verbose "Executing resource graph query"
        $resources = Search-AzGraph -Query "$($ArcQuery)"
       
    ## Iterate through results 
    Write-Verbose "Total query results of eligible Servers: $($resources.Count). Iterating through results..."
    foreach ($resource in $resources){
        write-verbose "Current Server: $($resource.machineName)"
        
        $EsuQuery = "resources
        | where type =~ 'microsoft.hybridcompute/licenses'
        | where name =~ '$($resource.targetEsuName)'
        | extend sku = properties.licenseDetails.edition
        | extend totalCores = properties.licenseDetails.processors
        | extend coreType = case(
            properties.licenseDetails.type =~ 'vCore','Virtual core',
            properties.licenseDetails.type =~ 'pCore','Physical core',
            'Unknown'
        )
        | extend statusIcon = case(
            properties.licenseDetails.state =~ 'Activated', '8',
            properties.licenseDetails.state =~ 'Deactivated', '7',
            '91'
        )
        | extend status = properties.licenseDetails.state
        | extend licenseId = tolower(tostring(id)) // Depending on what is stored in license profile, might have to get the immutableId instead
        | extend immutableLicenseId = properties.licenseDetails.immutableId
        | join kind=leftouter(
            resources
            | where type =~ 'microsoft.hybridcompute/machines/licenseProfiles'
            | extend machineId = tolower(tostring(trim_end(@'\/\w+\/(\w|\.)+', id)))
            | extend licenseId = tolower(tostring(properties.esuProfile.assignedLicense))
            | summarize resources = count() by licenseId
        ) on licenseId // Get count of license profile per license, a license profile is created for each machine that is assigned a license
        | extend resources = iff(isnull(resources), 0, resources)
        | project esuName = name,sku,totalCores,coreType,status,statusIcon,resources,id,immutableLicenseId,resourceGroup,type,kind,location,subscriptionId
        | sort by (tolower(tostring(esuName))) asc"

        Write-verbose "Checking if the target esu exists: $($resource.targetEsuName)"
        $serverEsu = Search-AzGraph -Query "$($EsuQuery)"

        if($serverEsu.count -eq 0){
            Write-verbose "Expected ESU does not exist.  Creating ESU and Linking to the server"
            $Licenseid = CreateLicense -token $accessToken -licenseTarget "Windows Server 2012" -licenseEdition "Standard" -licenseType "vCore" -region $resource.location -licenseState $licenseState -processors $resource.esuMinLogicalCores -licenseName $resource.targetEsuName -subscriptionId $resource.subscriptionId -resourceGroup $resource.resourceGroup
            
            Write-Verbose "Ensuring ESU is persisted..."
            $newEsu = Search-AzGraph -Query "$($EsuQuery)"
                while($true){
                    $newEsu = Search-AzGraph -Query "$($EsuQuery)"
                    if($newEsu.count -gt 0){
                        write-verbose "$($resource.targetEsuName) Esu created and registered.  Linking to Server: $($resource.machineName)"
                        break
                    }
                }
            LinkLicense -licenseResourceId $Licenseid -token $accessToken -machineName $resource.machineName -resourceGroup $resource.resourceGroup -region $resource.location        
        } else {
            write-host "Esu: $($resource.targetEsuName) already exists.  Linking the ESU..."
            LinkLicense -licenseResourceId $serverEsu[0].ResourceId -token $accessToken -machineName $resource.machineName -resourceGroup $resource.resourceGroup -region $resource.location       
        }
    }
}

#Function to create an ESU license
Function CreateLicense {
    param(
        [parameter(Mandatory=$true)]
        $token,

        [parameter(Mandatory=$true)]
        $licenseTarget,

        [parameter(Mandatory=$true)]
        $licenseEdition,

        [parameter(Mandatory=$true)]
        $licenseType,

        [parameter(Mandatory=$true)]
        $licenseState,

        [parameter(Mandatory=$true)]
        $processors,

        [parameter(Mandatory=$true)]
        $region,

        [parameter(Mandatory=$true)]
        $subscriptionId,

        [parameter(Mandatory=$true)]
        $resourceGroup,

        [parameter(Mandatory=$true)]
        $licenseName
    )

   $licenseResourceId = "/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.HybridCompute/licenses/{2}" -f $subscriptionId, $resourceGroup, $licenseName 

    $createLicenseUrl =  "https://management.azure.com{0}?api-version=2023-06-20-preview" -f $licenseResourceId 
    $createBody = @{
        'location' = $region 
        'properties' = @{ 
            'licenseDetails' = @{
                'state' = $licenseState 
                'target' = $licenseTarget 
                "Edition" = $licenseEdition 
                "Type" = $licenseType
                "Processors" = $processors
                }
            }
    }

    $bodyJson = $createBody | ConvertTo-Json -Depth 3

    $headers = @{
        Authorization = "Bearer $token"
    }

    Invoke-WebRequest -Uri $createLicenseUrl -Method Put -Body $bodyJson -Headers $headers -ContentType "application/json"

    Write-Output $licenseResourceId
}

Function UpdateLicense {
    param(
        [parameter(Mandatory=$true)]
        $licenseResourceId,

        [parameter(Mandatory=$true)]
        $token,

        [parameter(Mandatory=$true)]
        $licenseAction
    )
    $updateLicenseUrl =  "https://management.azure.com{0}?api-version=2023-06-20-preview" -f $licenseResourceId

    if($licenseAction -eq "Activate") {
        $licenseState = 'Activated'
    } elseif ($licenseAction -eq "Deactivate") {
        $licenseState = 'Deactivated'
    }
 
    $updateBody = @{
        'properties' = @{ 
            'licenseDetails' = @{ 
                'state' = $licenseState 
            } 
        } 
    }
    $bodyJson = $updateBody | ConvertTo-Json -Depth 3

    $headers = @{
        Authorization = "Bearer $token"
    }
    Invoke-WebRequest -Uri $updateLicenseUrl -Method Patch -Body $bodyJson -Headers $headers -ContentType "application/json"
}

Function LinkLicense {
    param(
        [parameter(Mandatory=$true)]
        $token,

        [parameter(Mandatory=$true)]
        $machineName,

        [parameter(Mandatory=$true)]
        $resourceGroup,

        [parameter(Mandatory=$true)]
        $licenseResourceId,

        [parameter(Mandatory=$true)]
        $region
    )
    $machineResourceId = (Get-AzConnectedMachine -Name $machineName -ResourceGroupName $resourceGroup).Id
    $linkLicenseUrl = "https://management.azure.com{0}/licenseProfiles/default?api-version=2023-06-20-preview " -f $machineResourceId
    $linkBody = @{
        location = $region
        properties = @{ 
            esuProfile = @{ 
                assignedLicense = $licenseResourceId
            } 
        } 
    }
    $bodyJson = $linkBody | ConvertTo-Json -Depth 3
    $headers = @{
        Authorization = "Bearer $token"
    }
    Invoke-WebRequest -Uri $linkLicenseUrl -Method PUT -Body $bodyJson -Headers $headers -ContentType "application/json"
    
}

Function DeleteLicenseLink {
    param(
        [parameter(Mandatory=$true)]
        $token,

        [parameter(Mandatory=$true)]
        $machineName,

        [parameter(Mandatory=$true)]
        $resourceGroup
    )
    $machineResourceId = (Get-AzConnectedMachine -Name $machineName -ResourceGroupName $resourceGroup).Id
    $linkLicenseUrl = "https://management.azure.com{0}/licenseProfiles/default?api-version=2023-06-20-preview " -f $machineResourceId
    $linkBody = @{
        location = $region
        properties = @{ 
            esuProfile = @{ 
                assignedLicense = $null
            } 
        } 
    }
    $bodyJson = $linkBody | ConvertTo-Json -Depth 3
    $headers = @{
        Authorization = "Bearer $token"
    }
    Invoke-WebRequest -Uri $linkLicenseUrl -Method PUT -Body $bodyJson -Headers $headers -ContentType "application/json"

}

Function DeleteLicense {
    param(
        [parameter(Mandatory=$true)]
        $token,

        [parameter(Mandatory=$true)]
        $licenseResourceId
    )
    $headers = @{
        Authorization = "Bearer $token"
    }
    $deleteLicenseUrl =  "https://management.azure.com{0}?api-version=2023-06-20-preview" -f $licenseResourceId
    Invoke-WebRequest -Uri $deleteLicenseUrl -Method DELETE -Headers $headers   
}
