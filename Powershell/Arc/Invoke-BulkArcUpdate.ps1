<#
.SYNOPSIS
    Peforms a bulk update of the license type and optional ESU status, for Arc Connected Sql Server
    machines
.DESCRIPTION
    This wrapper script will set the Sql Server license license type for a list of machines or for all of 
    the machines in a specified subscription.  
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
.PARAMETER pathToCsv
    The path to the CSV file that contains the servers to update and the license value to update them to.
    The valid values to include in the CSV are the parameter names supported by the modify-license-type.ps1
    script (SubId, ResourceGroup (Optional), MachineName (Optional), LicenseType, EnableESU (Optional)).  To 
    update all servers in a subscription to the same license value then only SubId and LicensType need to be specified
.EXAMPLE
    .\Invoke-BulkArcUpdate.ps1 -pathToCsv "c:\temp\serverlist.csv"
#>
[CmdletBinding()]
param (
    [Parameter (Mandatory=$true)]
    [string] $pathToCsv
)

#########################################
## Create a Hashtable
#########################################
    $arcTargets = import-csv $pathToCsv

#########################################
## Create a Hashtable
#########################################
    $splatParms = @{}
    Connect-AzAccount

#########################################
## Process each item from the CSV
#########################################
foreach ($arcTarget in $arcTargets){
    $arcTarget.psobject.properties | foreach {$splatParms[$_.Name] = $_.value }
    .\modify-license-type.ps1 @splatParms -force -verbose
}

