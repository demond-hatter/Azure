<#
.SYNOPSIS
	Arc Enables a Windows Server
.DESCRIPTION
	This script will onboard a windows server to Azure by Arc Enabling the server, which involes
    deploying the Azure Arc Connected Machine Agent.
.NOTES
	Author: Demond Hatter - Sr. Cloud Solution Architect - Microsoft Corporation

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
.PARAMETER servicePrincipalClientId
    Specifies the application ID of the service principal used to create the Azure Arc-enabled server resource in Azure
.PARAMETER servicePrincipalSecret
    Specifies the service principal secret
.PARAMETER SUBSCRIPTION_ID
    The subscription name or ID where you want to create the Azure Arc-enabled server resource
.PARAMETER RESOURCE_GROUP
    Name of the Azure resource group where you want to create the Azure Arc-enabled server resource
.PARAMETER TENANT_ID
    The tenant ID for the subscription where you want to create the Azure Arc-enabled server resource. This flag is 
    required when authenticating with a service principal
.PARAMETER AUTH_TYPE
    
.PARAMETER CLOUD
    Specifies the Azure cloud instance. Must be used with the --location flag. If the machine is already connected 
    to Azure Arc, the default value is the cloud to which the agent is already connected. Otherwise, the default value 
    is "AzureCloud"
.PARAMETER CORRELATION_ID
    Identifies the mechanism being used to connect the server to Azure Arc. For example, scripts generated in the Azure 
    portal include a GUID that helps Microsoft track usage of that experience. This flag is optional and only used for 
    telemetry purposes to improve your experience
.PARAMETER TAGS
    Comma-delimited list of tags to apply to the Azure Arc-enabled server resource. Each tag should be specified in the format: 
    TagName=TagValue
.EXAMPLE
    This example illustrates calling all required parameters

    .\Arc_WindowsOnboarding.ps1 -servicePrincipalClientId "98080..." -servicePrincipalSecret "7707879867986" -SUBSCRIPTION_ID "797987" -RESOURCE_GROUP "myRGroup" -TENANT_ID "7097r598724e098" -LOCATION "eastus2"
.EXAMPLE
    This example illustrates calling all required parameters and passing tags

    .\Arc_WindowsOnboarding.ps1 -servicePrincipalClientId "98080..." -servicePrincipalSecret "7707879867986" -SUBSCRIPTION_ID "797987" -RESOURCE_GROUP "myRGroup" -TENANT_ID "7097r598724e098" -LOCATION "eastus2" -TAGS "APMID=999999,DataCenter=CCC"
#>
[CmdletBinding()]
Param(
   	[Parameter(Mandatory=$true, Position=0,ParameterSetName = "principal")]
 		[string]$servicePrincipalClientId,
	[Parameter(Mandatory=$true, Position=1, ParameterSetName = "principal")]
		[string]$servicePrincipalSecret,
	[Parameter(Mandatory=$True, ParameterSetName = "interactive")]
    [Parameter(Mandatory=$True, ParameterSetName = "principal")]
		[string]$SubscriptionId,
	[Parameter(Mandatory=$True, ParameterSetName = "interactive")]
    [Parameter(Mandatory=$True, ParameterSetName = "principal")]
		[string]$resourceGroup,
	[Parameter(Mandatory=$True ,ParameterSetName = "interactive")]
    [Parameter(Mandatory=$True, ParameterSetName = "principal")]	
	    [string]$tenantId,
	[Parameter(Mandatory=$True ,ParameterSetName = "interactive")]
    [Parameter(Mandatory=$True, ParameterSetName = "principal")]
	[ValidateSet('eastus2','eastus','centralus','westus','westus2','westus3')]
		[string]$location,
	[Parameter(Mandatory=$True ,ParameterSetName = "interactive")]
    [Parameter(Mandatory=$True, ParameterSetName = "principal")]
    [ValidateSet('principal', 'token')]
		[string]$authType = "token",
	[Parameter(Mandatory=$True ,ParameterSetName = "interactive")]
    [Parameter(Mandatory=$True, ParameterSetName = "principal")]
	[ValidateSet('AzureCloud','AzureUSGovernment')]
		[string]$cloud= "AzureCloud",
	[Parameter(Mandatory=$false ,ParameterSetName = "principal")]
    [Parameter(Mandatory=$false, ParameterSetName = "interactive")]
		[string]$correlationId = "99999999-9999-9999-9999-999999999999",
    [Parameter(Mandatory=$False ,ParameterSetName = "interactive")]
    [Parameter(Mandatory=$False, ParameterSetName = "principal")]
		[string]$tags
)
$global:scriptPath = $myinvocation.mycommand.definition

function Restart-AsAdmin {
    $pwshCommand = "powershell"
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        $pwshCommand = "pwsh"
    }

    try {
        Write-Host "This script requires administrator permissions to install the Azure Connected Machine Agent. Attempting to restart script with elevated permissions..."
        $arguments = "-NoExit -Command `"& '$scriptPath'`""
        Start-Process $pwshCommand -Verb runAs -ArgumentList $arguments
        exit 0
    } catch {
        throw "Failed to elevate permissions. Please run this script as Administrator."
    }
}

try {
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        if ([System.Environment]::UserInteractive) {
            Restart-AsAdmin
        } else {
            throw "This script requires administrator permissions to install the Azure Connected Machine Agent. Please run this script as Administrator."
        }
}

    $env:SUBSCRIPTION_ID = $SubscriptionId;
    $env:RESOURCE_GROUP = $resourceGroup;
    $env:TENANT_ID = $tenantId;
    $env:LOCATION = $location;
    $env:AUTH_TYPE = $authType;
    $env:CORRELATION_ID = $correlationId;
    $env:CLOUD = $cloud;
    $tagparm = $null

    if($PSBoundParameters.ContainsKey("tags")){
        $tagparm = "--tags $tags"
    }

    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072;
    Invoke-WebRequest -UseBasicParsing -Uri "https://gbl.his.arc.azure.com/azcmagent-windows" -TimeoutSec 30 -OutFile "$env:TEMP\install_windows_azcmagent.ps1";
    
    & "$env:TEMP\install_windows_azcmagent.ps1";
    if ($LASTEXITCODE -ne 0) { exit 1; }

    if ($PSBoundParameters.ContainsKey("ServicePrincipalId")){
        & "$env:ProgramW6432\AzureConnectedMachineAgent\azcmagent.exe" connect --service-principal-id "$ServicePrincipalId" --service-principal-secret "$ServicePrincipalClientSecret" --resource-group "$env:RESOURCE_GROUP" --tenant-id "$env:TENANT_ID" --location "$env:LOCATION" --subscription-id "$env:SUBSCRIPTION_ID" --cloud "$env:CLOUD" --correlation-id "$env:CORRELATION_ID" $tagparm;
    } else {
        & "$env:ProgramW6432\AzureConnectedMachineAgent\azcmagent.exe" connect --resource-group "$env:RESOURCE_GROUP" --tenant-id "$env:TENANT_ID" --location "$env:LOCATION" --subscription-id "$env:SUBSCRIPTION_ID" --cloud "$env:CLOUD" --correlation-id "$env:CORRELATION_ID" $tagparm;
    }
    
}
catch {
    $logBody = @{subscriptionId="$env:SUBSCRIPTION_ID";resourceGroup="$env:RESOURCE_GROUP";tenantId="$env:TENANT_ID";location="$env:LOCATION";correlationId="$env:CORRELATION_ID";authType="$env:AUTH_TYPE";operation="onboarding";messageType=$_.FullyQualifiedErrorId;message="$_";};
    Invoke-WebRequest -UseBasicParsing -Uri "https://gbl.his.arc.azure.com/log" -Method "PUT" -Body ($logBody | ConvertTo-Json) | out-null;
    Write-Host  -ForegroundColor red $_.Exception;
}
