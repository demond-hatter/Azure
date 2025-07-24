<#
.SYNOPSIS
    Get Azure SQL Database size information and backup metrics over the last 30 days

.DESCRIPTION
    This script retrieves information about Azure SQL Databases including:
    - Database size metrics (current, max, average over 30 days)
    - Backup storage metrics from Azure platform metrics
    - Full backup, log backup, and differential backup storage metrics

.PARAMETER SubscriptionId
    Azure Subscription ID to query

.PARAMETER TenantId
    Optional: Azure Tenant ID to use for authentication

.PARAMETER ResourceGroupName
    Optional: Specific Resource Group to query (if not specified, all resource groups will be queried)

.PARAMETER ServerName
    Optional: Specific SQL Server to query (if not specified, all servers will be queried)

.PARAMETER DatabaseName
    Optional: Specific Database to query (if not specified, all databases will be queried)

.EXAMPLE
    .\Azure_SQL_DB_Info.ps1 -SubscriptionId "12345678-1234-1234-1234-123456789012"

.EXAMPLE
    .\Azure_SQL_DB_Info.ps1 -SubscriptionId "12345678-1234-1234-1234-123456789012" -TenantId "87654321-4321-4321-4321-210987654321"

.EXAMPLE
    .\Azure_SQL_DB_Info.ps1 -SubscriptionId "12345678-1234-1234-1234-123456789012" -ResourceGroupName "MyRG" -ServerName "MyServer"
#>


# Connect to Azure Key Vault, retrieve App ID and Secret, authenticate, and create HSM-backed key
function New-KeyVaultKey {
    [CmdletBinding()]
    param(
    [string]$tenantId,
    [string]$subscriptionId,
    [string]$ResourceGroupName,
    [string]$KeyVaultName,
    [string]$AppIdSecretName,
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

    Connect-AzAccount -Tenant $tenantId -Subscription $subscriptionId

    # Get secrets from Key Vault using your current context
        $AppId = (Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $AppIdSecretName).SecretValue
        $AppSecret = (Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $AppSecretSecretName).SecretValue

    # Authenticate to Azure using App Registration credentials
        $SecurePassword = ConvertTo-SecureString $AppSecret -AsPlainText -Force
        $Credential = New-Object System.Management.Automation.PSCredential($AppId, $SecurePassword)
        Connect-AzAccount -ServicePrincipal -Credential $Credential -Tenant $tenantId

    # Create HSM-backed encryption key
        $Expires = (Get-Date).ToUniversalTime()
        $KeyName = (New-KeyVaultKeyName -expirationDate $Expires)
        $parms = @{
            VaultName = $KeyVaultName
            Name = $KeyName
            KeyType = 'RSA'
            KeySize = 2048
            Destination = 'HSM'
            Expires = $Expires
            Enabled = $true
        }
        Add-AzKeyVaultKey @parms

    }
}

function New-KeyVaultKeyName {
    param (
        [string]$expirationDate
    )

    return $env:COMPUTERNAME + "_" + $expirationDate.ToString("yyyyMMdd-HHmmss") + "key"
}
