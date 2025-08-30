<#
.SYNOPSIS
    Sample wrapper to call the underlying script "uninstall-azure-extension-for-sql-server.ps1" using
    a service principal credentials stored in Azure Key Vault
.DESCRIPTION
    This script will remove all extensions from an existing arc enabled server and then finally remove
    the server from Azure.  This wrapper script is designed to utilize a service principal and requires
    that the service principal Application Id and Secret are stored in a Key Vault.  The underlying script
    "uninstall-azure-extension-for-sql-server.ps1" can also be called directly since it does all the work
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
.PARAMETER tenantId
    The Entra ID tenant id.  This can be retrieved from the Entra id blade from the Azure portal
.PARAMETER keyVaultSubId
    The subscription Id of the keyvault.  This needs to be the internal ID and not the subscription name
.PARAMETER OffBoardMachineSubId
    The subscription Id of the machine to offboard.  This needs to be the internal ID and not the subscription name
.PARAMETER KeyVault
    The name of the keyvault that contains the credentials to use to perform the offboarding process.  The user
    running this script must have rights to access the keyvault and retrieve the secrets
.PARAMETER appIdKey
    The name of the entry in the key vault that contains the Service Principal Application Id. The user
    running this script must have rights to access the keyvault and retrieve the secrets
.PARAMETER appPwdKey
    The name of the entry in the key vault that contains the Service Principal secret. The user
    running this script must have rights to access the keyvault and retrieve the secrets
.PARAMETER machineToOffboard
    The name of the machine to offboard
.EXAMPLE
    .\Invoke-ArcMachineOffBoard.ps1 -tenantId "15b3f013-t300-468r-jh64-7tya0921b6d3" -keyVaultSubId "5d48a9fe-3qq7-47b1-b68n-d34p2b24290i" -OffBoardMachineSubId "5d48a9fe-3qq7-47b1-b68n-d34p2b24290i" -keyVault "mysecureKeyvault" -appIdKey "ArcSPAppID" -appPwdKey "ArcSPSecret" -machineToOffBoard "machinename"
#>
[CmdletBinding()]
param (
    [Parameter (Mandatory=$true)]
    [string] $tenantId,
    [Parameter (Mandatory=$true)]
    [string] $keyVaultSubId,
    [Parameter (Mandatory=$true)]
    [string] $OffBoardMachineSubId,
    [Parameter (Mandatory=$true)]
    [string] $keyVault,
    [Parameter (Mandatory=$true)]
    [string] $appIdKey,
    [Parameter (Mandatory=$true)]
    [string] $appPwdKey,
    [Parameter (Mandatory=$true)]
    [string] $machineToOffboard

)

#########################################################
## Retrieve the current service principal details
## from the key vault
#########################################################
    Connect-AzAccount -Tenant $tenantID -Subscription $keyVaultSubId

    write-verbose "Retrieving credentials from keyvault: $keyVault"
        $appId = Get-AzKeyVaultSecret -VaultName $KeyVault -Name $appIdKey -AsPlainText
        $appPwd = Get-AzKeyVaultSecret -VaultName $keyVault -Name $appPwdKey

        $servicePrincipalCred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $appId, $($appPwd.SecretValue)

############################################################
## Connect as the Service Principal to perform off Boarding
############################################################
    write-verbose "Authenticating as service principal"
        Connect-AzAccount -Tenant $tenantId -ServicePrincipal -Credential $servicePrincipalCred

############################################################
## Offboard the specified machine
############################################################
    write-verbose "Invoking Offboarding of machine: $machineToOffboard"
        .\uninstall-azure-extension-for-sql-server.ps1 -SubId $OffBoardMachineSubId -MachineName $machineToOffboard