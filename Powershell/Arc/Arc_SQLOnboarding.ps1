<#
.SYNOPSIS
	Deploy the Azure Arc SQL Server Extension to onboard SQL Servers to Azure
.DESCRIPTION
	This script will deploy the Azure Arc SQL Server Extension to onboard SQL Servers to Azure in bulk.
	The servers should already be arc enabled and connected to azure.  The subscription should use the tag
	ArcSQLServerExtensionDeployment=disabled to prevent automatic deployment of the extension.

	The servers will be onboarded with the following settings:
	
		least privilege mode - enabled
		ClientConnections - disabled
		SQL Management - 
		license type - PAYG, Paid, or LicenseOnly (as specified by the user)
.NOTES
	Contributor: Demond Hatter - Sr. Cloud Solution Architect - Microsoft Corporation
	Contributor: Sunil Seth - Cloud Solution Architect - Microsoft Corporation


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
.PARAMETER subscriptionId
    The subscription name or ID where you want to create the Azure Arc-enabled server resource
.PARAMETER resourceGroup
    Name of the Azure resource group where you want to create the Azure Arc-enabled server resource
.PARAMETER tenantId
    The tenant ID for the subscription where you want to create the Azure Arc-enabled server resource. This flag is 
    required when authenticating with a service principal
.PARAMETER location
    The Azure region where you want to create the Azure Arc-enabled server resource

.PARAMETER licenseType
	The license type for SQL Server on the Arc-enabled server. Accepted values are 'PAYG', 'Paid', or 'LicenseOnly'
.PARAMETER csvFilePath
	The full path to a CSV file containing a list of Arc-enabled servers to onboard. The CSV file must contain a column named 'MachineName'
.PARAMETER logFilePath
	The full path to a log file where the script will write its output. If the file already exists, it will be overwritten. Default is 'AddSqlExtensionLog.txt' in the current directory.
.EXAMPLE
    This example illustrates using interactive login to authenticate and calling all required parameters

    add-sqlExtension -subscriptionId "797987" -resourceGroup "myRGroup" -tenantId "7097r598724e098" -location "eastus2" -licenseType "Paid" -csvFilePath "C:\Temp\ArcMachines.csv" -logFilePath "C:\Temp\ArcOnboardingLog.txt" -tags "DataCenter=DC1,Environment=Test"
.EXAMPLE
    This example illustrates using service principal to authenticate and calling all required parameters

    add-sqlExtension -servicePrincipalClientId "98080..." -servicePrincipalSecret "7707879867986" -subscriptionId "797987" -resourceGroup "myRGroup" -tenantId "7097r598724e098" -location "eastus2" -tags "APMID=999999,DataCenter=CCC"
#>
function add-sqlExtension {
	[CmdletBinding(DefaultParameterSetName = 'interactive')]
	Param(
		[Parameter(Mandatory=$True, ParameterSetName = "principal", Position=0)]
			[string]$servicePrincipalClientId,
		[Parameter(Mandatory=$True, ParameterSetName = "principal", Position=0)]
			[string]$servicePrincipalSecret,
		[Parameter(Mandatory=$True, ParameterSetName = "principal", Position=1)]
		[Parameter(Mandatory=$True, ParameterSetName = "interactive", Position=1)]
			[string]$subscritionId,
		[Parameter(Mandatory=$True,ParameterSetName = "principal", Position=0)]
		[Parameter(Mandatory=$True, ParameterSetName = "interactive", Position=1)]
			[string]$resourceGroup,
		[Parameter(Mandatory=$True, ParameterSetName = "principal", Position=0)]
		[Parameter(Mandatory=$True, ParameterSetName = "interactive", Position=1)]
			[string]$tenantId,
		[Parameter(Mandatory=$True,ParameterSetName = "principal", Position=0)]
		[Parameter(Mandatory=$True, ParameterSetName = "interactive", Position=1)]
		[ValidateSet('eastus','eastus2','centralus','westus')]
			[string]$location,
		[Parameter(Mandatory=$True,ParameterSetName = "principal", Position=0)]
		[Parameter(Mandatory=$True, ParameterSetName = "interactive", Position=1)]
		[ValidateSet('PAYG','Paid', 'LicenseOnly')]
			[string]$licenseType,
		[Parameter(Mandatory=$True,ParameterSetName = "principal", Position=0)]
		[Parameter(Mandatory=$True, ParameterSetName = "interactive", Position=1)]
			[string]$csvFilePath,
		[Parameter(Mandatory=$false,ParameterSetName = "principal", Position=0)]
		[Parameter(Mandatory=$false, ParameterSetName = "interactive", Position=1)]
			[string]$logFilePath = "AddSqlExtensionLog.txt"
	)

	$extensionName="WindowsAgent.SqlServer"

	write-verbose "Checking for CSV file at path: $CsvFilePath"
		if (-not (Test-Path $CsvFilePath)) {
			Write-Error "CSV file path '$CsvFilePath' does not exist. Please provide a valid path and CSV file."
			exit
		}

	write-verbose "Checking for log file at path: $LogFilePath"
		if (Test-Path $LogFilePath) {
			Remove-Item -Path $LogFilePath -Force
		}
		New-Item -ItemType File -Path $LogFilePath -Force | Out-Null

	Write-Verbose "Authenticating to Azure..."
		if ($PSCmdlet.ParameterSetName -eq 'interactive') {
			$ctx = connect-toAzure -tenantId $tenantId -subscriptionId $subscritionId
		} elseif ($PSCmdlet.ParameterSetName -eq 'principal') {
			$ctx = connect-toAzure -tenantId $tenantId -subscriptionId $subscritionId -servicePrincipalClientId $servicePrincipalClientId -servicePrincipalSecret $servicePrincipalSecret
		} else {
			Write-Error "Invalid parameter set. Please use either 'interactive' or 'principal' parameter sets."
			exit
		}

		$ctx | Out-File -FilePath $LogFilePath -Append

	Write-verbose "Getting list of machines from CSV file..."
		$MachineList = Import-Csv -Path $CsvFilePath

	foreach ($Machine in $MachineList) {
		$MachineName = $Machine.MachineName

		if (-not $MachineName) {
			Write-Warning "MachineName is missing in one of the rows. Skipping."
			"MachineName is missing in one of the rows. Skipping." | Out-File -FilePath $LogFilePath -Append
			continue
		}

		Write-Host "Processing machine: $MachineName"
		"Processing machine: $MachineName" | Out-File -FilePath $LogFilePath -Append
		
		$Settings = @{
			SqlManagement = @{
				IsEnabled = $true
			}
			FeatureFlags = @(
				@{
					Name = "LeastPrivilege"
					Enable = $true
				}
				@{
					Name = "clientconnections"
					Enable = $false
				}       
			)
			LicenseType = $licenseType
		}

		try {
			New-AzConnectedMachineExtension -Name $extensionName `
											-ResourceGroupName $ResourceGroup `
											-MachineName $MachineName `
											-Location $Location `
											-Publisher "Microsoft.AzureData" `
											-Setting $Settings `
											-ExtensionType "$extensionName"
								
			Write-Host "Extension successfully applied to machine: $MachineName"
			"Extension successfully applied to machine: $MachineName" | Out-File -FilePath $LogFilePath -Append
		} catch {
			Write-Error "Failed to apply extension to machine: $MachineName. Error: $_"
			"Failed to apply extension to machine: $MachineName. Error: $_" | Out-File -FilePath $LogFilePath -Append
		}
	}
}

function disable-sqlArcFeatures{
	[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'interactive')]	
	param (
		[Parameter(Mandatory=$True, ParameterSetName = "principal", Position=0)]
			[string]$servicePrincipalClientId,
		[Parameter(Mandatory=$True, ParameterSetName = "principal", Position=0)]
			[string]$servicePrincipalSecret,
		[Parameter(Mandatory=$True, ParameterSetName = "principal", Position=1)]
		[Parameter(Mandatory=$True, ParameterSetName = "interactive", Position=1)]
			[string]$subscritionId,
		[Parameter(Mandatory=$True,ParameterSetName = "principal", Position=0)]
		[Parameter(Mandatory=$True, ParameterSetName = "interactive", Position=1)]
			[string]$resourceGroup,
		[Parameter(Mandatory=$True, ParameterSetName = "principal", Position=0)]
		[Parameter(Mandatory=$True, ParameterSetName = "interactive", Position=1)]
			[string]$tenantId,
		[Parameter(Mandatory=$True,ParameterSetName = "principal", Position=0)]
		[Parameter(Mandatory=$True, ParameterSetName = "interactive", Position=1)]
			[string]$csvFilePath,
		[Parameter(Mandatory=$false,ParameterSetName = "principal", Position=0)]
		[Parameter(Mandatory=$false, ParameterSetName = "interactive", Position=1)]
			[string]$logFilePath = "ScriptExecutionLog.txt"
	)

	[string]$propertiesJSON = @"
	{
		"backupPolicy": null,
		"monitoring": {
			"enabled": false
		},
		"migration": {
			"assessment": {
				"enabled": false
			}
		}
	}
"@

	Write-Verbose "Resource Group Name: $resourceGroup"
	Write-Verbose "Subscription ID: $subscriptionId"
	Write-Verbose "Tenant ID: $tenantId"

	$properties = $propertiesJSON | ConvertFrom-Json

	try {
		Write-Verbose "Connecting to Azure with subscription ID: $subscriptionId"
		if ($PSCmdlet.ParameterSetName -eq 'interactive') {
			$defaultProfile = connect-toAzure -tenantId $tenantId -subscriptionId $subscritionId
		} else {
			$defaultProfile = connect-toAzure -tenantId $tenantId -subscriptionId $subscritionId -servicePrincipalClientId $servicePrincipalClientId -servicePrincipalSecret $servicePrincipalSecret
		}
	} catch {
		Write-Error "An error occurred: $_"
	}

	$MachineList = Import-Csv -Path $CsvFilePath

		foreach ($Machine in $MachineList) {
			$MachineName = $Machine.MachineName

			if (-not $MachineName) {
				Write-Warning "MachineName is missing in one of the rows. Skipping."
				continue
			}

			Write-Host "Processing machine: $MachineName"
			Write-Verbose "Fetching Sql Instances on machine: $MachineName in resource group: $resourceGroup"
			$resources = Get-AzResource -ResourceGroupName $resourceGroup -ResourceType "Microsoft.AzureArcData/SqlServerInstances" -Name $MachineName -ErrorAction Stop -Pre -ExpandProperties

			foreach ($resource in ($resources | Where-Object { $_.Properties.serviceType -eq "Engine"})) {

				try {
					if ($PSCmdlet.ShouldProcess($resource.name, "Performing dry-run patch for resource: $($resource.Id)")) {
						Write-Verbose "Patching resource: $($resource.Id)"
						$resource | Set-AzResource -Properties $properties -UsePatchSemantics -Pre -Force -DefaultProfile $defaultProfile -ErrorAction Stop
						Write-Host("Resource patched: $($resource.Id)") 
					} else {
						$resource | Set-AzResource -Properties $properties -UsePatchSemantics -Pre -Force -DefaultProfile $defaultProfile -ErrorAction Stop -WhatIf
					}
				} catch {
					Write-Error "Failed to patch resource: $($resource.Id). Error: $_"
				}
			}

		}
}

function remove-arcSqlExtension {
	[CmdletBinding(DefaultParameterSetName = 'interactive')]	
	param (
		[Parameter(Mandatory=$True, ParameterSetName = "principal", Position=0)]
			[string]$servicePrincipalClientId,
		[Parameter(Mandatory=$True, ParameterSetName = "principal", Position=0)]
			[string]$servicePrincipalSecret,
		[Parameter(Mandatory=$True, ParameterSetName = "principal", Position=1)]
		[Parameter(Mandatory=$True, ParameterSetName = "interactive", Position=1)]
			[string]$subscritionId,
		[Parameter(Mandatory=$True,ParameterSetName = "principal", Position=0)]
		[Parameter(Mandatory=$True, ParameterSetName = "interactive", Position=1)]
			[string]$resourceGroup,
		[Parameter(Mandatory=$True, ParameterSetName = "principal", Position=0)]
		[Parameter(Mandatory=$True, ParameterSetName = "interactive", Position=1)]
			[string]$tenantId,
		[Parameter(Mandatory=$True,ParameterSetName = "principal", Position=0)]
		[Parameter(Mandatory=$True, ParameterSetName = "interactive", Position=1)]
			[string]$csvFilePath,
		[Parameter(Mandatory=$false,ParameterSetName = "principal", Position=0)]
		[Parameter(Mandatory=$false, ParameterSetName = "interactive", Position=1)]
			[string]$logFilePath = "ScriptExecutionLog.txt"
	)

	try {
		Write-Verbose "Connecting to Azure with subscription ID: $subscriptionId"
		if ($PSCmdlet.ParameterSetName -eq 'interactive') {
			$ctx = connect-toAzure -tenantId $tenantId -subscriptionId $subscritionId
		} else {
			$ctx = connect-toAzure -tenantId $tenantId -subscriptionId $subscritionId -servicePrincipalClientId $servicePrincipalClientId -servicePrincipalSecret $servicePrincipalSecret
		}
	} catch {
		Write-Error "An error occurred: $_"
	}

	write-verbose "checking for the recommended resource tag on resource group: $resourceGroup"
	$existingTags = (Get-AzResourceGroup -Name $ResourceGroup).Tags

	if ($existingTags.ContainsKey("ArcSQLServerExtensionDeployment")) {
    	if ($existingTags["ArcSQLServerExtensionDeployment"] -eq "Disabled") {
         	Write-Host "Tag 'ArcSQLServerExtensionDeployment' already exists with value 'Disabled'."
    	} else {
        	$UpdateTag = $true
    	}
	} else {
    	Write-Host "Tag 'ArcSQLServerExtensionDeployment' is missing."
    	$CreateTag = $true
	}
	
	if ($CreateTag -eq $true) {
    	$existingTags.Add("ArcSQLServerExtensionDeployment", "Disabled")
    	Set-AzResourceGroup -Name $ResourceGroup -Tag $existingTags
	} elseif ($UpdateTag -eq $true) {
		$existingTags["ArcSQLServerExtensionDeployment"] = "Disabled"
		Set-AzResourceGroup -Name $ResourceGroup -Tag $existingTags
	}

	if (-Not (Test-Path $CsvFilePath)) {
		Write-Host "CSV file path not found: $CsvFilePath"
		exit
	}
	$machineList = Import-Csv -Path $CsvFilePath

	foreach ($machine in $machineList) {
		$machineName = $machine.MachineName
		Write-Host "Checking if Arc SQL Extension is installed on machine: $machineName"

		try {
			# Check if the SQL Server extension is installed
			$extension = Get-AzConnectedMachineExtension -MachineName $machineName -ResourceGroupName $ResourceGroup -ErrorAction Stop | Where-Object { $_.Name -eq "WindowsAgent.SqlServer" }

			if ($extension) {
				Write-Host "Arc SQL Extension is installed on machine: $machineName. Attempting to uninstall..."
				$extension | Remove-AzConnectedMachineExtension -NoWait -ErrorAction Stop
				Write-Host "Successfully removed the Arc SQL Extension from machine: $machineName"
				$resources = Get-AzResource -ResourceGroupName $resourceGroup -ResourceType "Microsoft.AzureArcData/SqlServerInstances" -Name $MachineName -ErrorAction Stop -Pre -ExpandProperties
				foreach ($resource in $resources) {
					try {
						Remove-AzResource -ResourceId $resource.ResourceId -Force -ErrorAction Stop
						Write-Host "Successfully removed the Arc SQL Instance resource: $($resource.Name)"
					} catch {
						Write-Error "Failed to remove Arc SQL Instance resource: $($resource.Name). Error: $_"
					}
				}
			} else {
				Write-Host "Arc SQL Extension is not installed on machine: $machineName. Skipping..."
			}
		} catch {
			Write-Host "Error occurred while processing machine: $machineName. Details: $_"
		}
	}
}

function connect-toAzure {
	[CmdletBinding(DefaultParameterSetName = 'InteractiveUserSet')]
	Param(
		[Parameter(Mandatory=$True, ParameterSetName = 'InteractiveUserSet', Position = 0)]
		[Parameter(Mandatory=$True, ParameterSetName = 'PrincipalSet', Position = 0)]
			[string]$tenantId,	
		[Parameter(Mandatory=$True, ParameterSetName = 'InteractiveUserSet', Position = 1)]
		[Parameter(Mandatory=$True, ParameterSetName = 'PrincipalSet', Position = 1)]
			[string]$subscriptionId,
		[Parameter(Mandatory=$true, ParameterSetName = 'PrincipalSet', Position = 2)]
			[string]$servicePrincipalClientId,
		[Parameter(Mandatory=$true, ParameterSetName = 'PrincipalSet', Position = 3)]
			[string]$servicePrincipalSecret
	)
		$Context = Get-AzContext;
		$curContext= $null

		########################################################
		## Check if an Azure context already exist for the
		## specified subscription. If not then authenticate or
		## set the existing context to the subscription
		########################################################
		if ($PSCmdlet.ParameterSetName -eq 'PrincipalSet') {
			# Connect using Service Principal
			Write-Verbose "Connecting to Azure using Service Principal for Subscription: $subscriptionId in Tenant: $tenantId";
			$secureSecret = ConvertTo-SecureString $servicePrincipalSecret -AsPlainText -Force
			$Credential = New-Object System.Management.Automation.PSCredential ($servicePrincipalClientId, $secureSecret)
			$curContext = Connect-AzAccount -ServicePrincipal -TenantId $tenantId -Credential $Credential;
		} elseif (-not $Context) {
			# Not connected to Azure, so let's connect...
			Write-Verbose 'Azure Context not found. Prompting for authentication...';
			$curContext = Connect-AzAccount -Subscription $subscriptionId -Tenant $tenantId;
		} elseif ($Context.Subscription.Id -ne $subscriptionId ) {
			# There could be a valid context, but it might be the wrong tenant
			if (Get-AzSubscription -SubscriptionId $subscriptionId -ErrorAction SilentlyContinue) {
				# Right environment, wrong subscription. Just switch context...
				Write-Verbose "Azure Context found. Setting Context to subscription: $subscriptionId";
				$curContext = Set-AzContext -Subscription $subscriptionId;
			} else {
				# Probably wrong tenant... reconnect...
				$curContext = Connect-AzAccount -Subscription $subscriptionId -Tenant $tenantId;
			}
		} else {
			# Nothing to do. Already in the right environment and right subscription...
			$curContext = $Context
			Write-Verbose "Azure Context was already found and set set for subscription: $subscriptionId ($($Context.Subscription.Name))";
		}

		return $curContext;
}