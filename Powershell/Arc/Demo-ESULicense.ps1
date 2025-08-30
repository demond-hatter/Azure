[CmdletBinding()]
<#
.SYNOPSIS
    This script will create, activate, deactivate, link, unlink, or delete an ESU license for a Windows 2012 machine.

.DESCRIPTION
    This script will create, activate, deactivate, link, unlink, or delete an ESU license for a Windows 2012 machine.

.PARAMETER licenseOperation
    The operation to perform on the ESU license. Valid values are Create, Activate, Deactivate, Link, Unlink, and Delete.

.PARAMETER TenantId
    The tenant ID of the Azure subscription.

.PARAMETER ApplicationId
    The application ID of the service principal. Do not specify if using your own login. The script will prompt for password if using ApplicationId.

.PARAMETER region
    The Azure region to create licenses in. The Azure region of the VM in all other operations.

.PARAMETER subscriptionId
    The subscription ID of the Azure subscription.

.PARAMETER resourceGroup
    The Resource Group of License files when performing License Operations.  The Resource Group of the Machine(s) when performing Machine Operations.

.PARAMETER machineName
    The name of the machine to perform the operation on.

.PARAMETER machines
    A Comma-separated array of machine names to perform the operation on.

.PARAMETER machineCSVfile
    A CSV file containing a column named MachineName with the names of the machines to perform the operation on.

.PARAMETER AllMachinesInRG
    Perform the operation on all machines in the resource group. The script will automatically exclude non-Windows 2012 machines.

.PARAMETER licenseResourceId
    The resource ID of the ESU license when performing Link, Unlink, Activate, Deactivate, or Delete operations.

.PARAMETER licenseName
    An optional name parameter for the license when performing Create operations. If not specified, the license will be named Datacenter-pCore or Standard-vCore, etc. depending on the license type.
.NOTES
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
.EXAMPLE
    .\Demo-ESULicense.ps1 -licenseOperation Create -TenantId "00000000-0000-0000-0000-000000000000" -ApplicationId "00000000-0000-0000-0000-000000000000" `
    -SecurePassword "00000000-0000-0000-0000-000000000000" -region "eastus" -subscriptionId "00000000-0000-0000-0000-000000000000" `
    -resourceGroup "ESU-Licenses"
    
    This example will create a new ESU license in the East US region with a Service Principal login and will prompt you for license details.

.EXAMPLE
    .\Demo-ESULicense.ps1 -licenseOperation Link -TenantId "00000000-0000-0000-0000-000000000000" -region "eastus" `
    -subscriptionId "00000000-0000-0000-0000-000000000000" -resourceGroup "ESU-Licenses" -machineName "machine1" `
    -licenseResourceId "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/ESU-Licenses/providers/Microsoft.HybridCompute/licenses/Datacenter-vCore"
    
    This example will link the license to the machine named machine1 using the current logged in user's credentials.

.EXAMPLE
    .\Demo-ESULicense.ps1 -licenseOperation Unlink -TenantId "00000000-0000-0000-0000-000000000000" -region "eastus" `
    -subscriptionId "00000000-0000-0000-0000-000000000000" -resourceGroup "ESU-Licenses" -allMachinesInRG `
    -licenseResourceId "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/ESU-Licenses/providers/Microsoft.HybridCompute/licenses/Datacenter-vCore"
    
    This example will unlink the license from all machines in the resource group using the current logged in user's credentials.

.OUTPUTS
    The REST API response for the operation or in the case of the Create operation, the resource ID of the created license.
#>

param(
    [parameter(Mandatory=$true)]
    [ValidateSet("Create","Deactivate","Activate","Link","Unlink","Delete")]
    $licenseOperation,

    [parameter(Mandatory=$true)]
    $TenantId,

    $ApplicationId,

    [parameter(Mandatory=$true)]
    $region,

    [parameter(Mandatory=$true)]
    $subscriptionId,

    [parameter(Mandatory=$true)]
    $resourceGroup,

    $machineName,

    [array]$machines,

    $machineCSVfile,

    [switch]$AllMachinesInRG,

    $licenseResourceId,

    $licenseName
)


#If ServicePrincipal is used, connect to Azure with Service Principal and retrieve bearer token
if ($ApplicationId) {
    [securestring]$SecurePassword = $(Read-Host -Prompt "Enter password" -AsSecureString)
    #$SecurePassword = ConvertTo-SecureString -String $SecurePassword -AsPlainText -Force
    $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $ApplicationId, $SecurePassword
    try {
        Connect-AzAccount -ServicePrincipal -TenantId $TenantId -Credential $Credential
        $token = (Get-AzAccessToken -ResourceUrl 'https://management.azure.com').Token
    }
    catch {
        Write-Output "Failed to connect to Azure with Service Principal - Check your credentials or try as the current user"
        exit
    }
}
else {
    try {
       $context = Get-AzContext -ea 0
       if ($context.Subscription -ne $subscriptionId) {
        Set-AzContext -Subscription $subscriptionId
        $token = (Get-AzAccessToken -ResourceUrl 'https://management.azure.com').Token
       }
    }
    catch{
        Write-Output "No context found, logging in and setting context"
        try{
            Connect-AzAccount -Tenant $TenantId
            Set-AzContext -Subscription $subscriptionId
            $token = (Get-AzAccessToken -ResourceUrl 'https://management.azure.com').Token
        }
        catch{
            Write-Output "Failed to connect to Azure - Check your credentials"
            exit
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

        $licenseName
    )

   $licenseResourceId = "/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.HybridCompute/licenses/{2}" -f $subscriptionId, $resourceGroup, $($licenseName+$licenseEdition+"-"+$licenseType) 

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

if ($machineName) {
    $machines = @($machineName)
}
elseif ($machineCSVfile) {
    $machines = Import-Csv $machineCSVfile | Select-Object -ExpandProperty MachineName
}
elseif ($AllMachinesInRG) {
    $machines = Get-AzConnectedMachine -ResourceGroupName $resourceGroup | Where-Object {$_.OSSku -match "2012"} | Select-Object -ExpandProperty Name
}

if ($licenseOperation -eq "Create") {
    $prompt = Read-Host -Prompt "Is this a Windows 2012 License? (y/n)"
    if ($prompt -eq "y") {
        $licenseTarget = 'Windows Server 2012'
    }
    $licenseState = Read-Host -Prompt "What state should the license be created in? (Deactivated/Activated)"
    if ($licenseState -eq "Activated") {
        $licenseState = 'Activated'
    } else {
        $licenseState = 'Deactivated'
    }
    $licenseEdition = Read-Host -Prompt "What is the license edition? (Datacenter/Standard)"
    if ($licenseEdition -eq "Datacenter") {
        $licenseEdition = 'Datacenter'
    } else {
        $licenseEdition = 'Standard'
    }
    $licenseType = Read-Host -Prompt "What is the license type? (vCore/pCore)"
    if ($licenseType -eq "vCore") {
        $licenseType = 'vCore'
    } else {
        $licenseType = 'pCore'
    }
    $processors = Read-Host "Please enter the core count, vCore must be at least 8, pCore must be at least 16. (8/16)"

    CreateLicense $token $licenseTarget $licenseEdition $licenseType $licenseState $processors $region $subscriptionId $resourceGroup $licenseName
}
elseif ($licenseOperation -eq "Activate" -or $licenseOperation -eq "Deactivate") {
    UpdateLicense $licenseResourceId $token $licenseOperation
}
elseif ($licenseOperation -eq "Link") {
    foreach ($machineName in $machines) {
        LinkLicense $token $machineName $resourceGroup $licenseResourceId $region
    }
}
elseif ($licenseOperation -eq "Unlink") {
    foreach ($machineName in $machines) {
        DeleteLicenseLink $token $machineName $resourceGroup
    }
}
elseif ($licenseOperation -eq "Delete") {
    DeleteLicense $token $licenseResourceId
}

