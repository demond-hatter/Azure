<#
.SYNOPSIS
    Creates a new KeyVault Key 

.DESCRIPTION
    This script will create a new keyvault 

.PARAMETER SubscriptionId
    Azure Subscription ID to query

.PARAMETER TenantId
    Azure Tenant ID to use for authentication

.PARAMETER subscriptionId
    the Azure Subscription ID to use for authentication. If not specified, the current subscription will be used.

.PARAMETER ResourceGroupName
    The name of the Azure Resource Group where the Key Vault is located. This is required to create the key.

.PARAMETER KeyVaultName
    The name of the Azure Key Vault where the key will be created.

.PARAMETER AppIdSecretName
    The name of the key vault secret that contains the App ID.
 
.PARAMETER AppSecretSecretName
    The name of the key vault secret that contains the App Secret.

.EXAMPLE
    New-KeyVaultKey -TenantId "your-tenant-id" -SubscriptionId "your-subscription-id" -ResourceGroupName "your-resource-group" -KeyVaultName "your-key-vault-name" -AppIdSecretName "your-app-id-secret-name" -AppSecretSecretName "your-app-secret-secret-name"
    
    This example creates a new key in the specified Key Vault using the provided App ID and App Secret from the Key Vault secrets.
#>
function New-KeyVaultKey {
    [CmdletBinding()]
    param(
    [Parameter(Mandatory = $true)]
        [string]$tenantId,
    [Parameter(Mandatory = $true)]
        [string]$subscriptionId,
    [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,
    [Parameter(Mandatory = $true)]
        [string]$KeyVaultName,
    [Parameter(Mandatory = $true)]
        [string]$AppIdSecretName,
    [Parameter(Mandatory = $true)]
        [string]$AppSecretSecretName
    )
PROCESS {
    # Install required modules if not present
    if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
        Install-Module -Name Az.Accounts -Force -Scope CurrentUser
    }
    if (-not (Get-Module -ListAvailable -Name Az.KeyVault)) {
        Install-Module -Name Az.KeyVault -Force -Scope CurrentUser
    }

    Import-Module Az.Accounts
    Import-Module Az.KeyVault

    # Authenticate to Azure using the specified tenant and subscription as the current user
        Connect-AzAccount -Tenant $tenantId -Subscription $subscriptionId

    # Get secrets from Key Vault using your current context
        $AppId = (Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $AppIdSecretName).SecretValue
        $AppSecret = (Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $AppSecretSecretName).SecretValue
        $appId = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($AppId))


    # Authenticate to Azure using App Registration credentials
        $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $AppId, $AppSecret
        Connect-AzAccount -ServicePrincipal -Credential $Credential -Tenant $tenantId -Subscription $subscriptionId

    # Create HSM-backed encryption key
        $Created = (Get-Date).ToUniversalTime()
        $Expires = $Created.addyears(2)
        $KeyName = (New-KeyVaultKeyName -expirationDate $Expires)
        $parms = @{
            VaultName = $KeyVaultName
            Name = $KeyName
            KeyType = 'RSA'
            Size = 2048
            Destination = 'HSM'
            Expires = $Expires
            Exportable = $true
        }
        Add-AzKeyVaultKey @parms

    }
}

function New-KeyVaultKeyName {
    param (
        [datetime]$expirationDate
    )

    return "$($env:COMPUTERNAME.Replace('-',''))-$($expirationDate.ToString("yyyyMMddHHmmss"))-key"
}
