<#
    .SYNOPSIS
    Runbook for authenticating service principal account to run automation.

    .NOTES
    Author: John Manglinong
    Created: 2020-10-19
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)][string]$subscriptionId,
    [Parameter(Mandatory=$false)][string]$tenantId,
    [Parameter(Mandatory=$false)][string]$ApplicationId,
    [Parameter(Mandatory=$false)][string]$ApplicationSecret
)

$maxFailures = 3
$attemptCount = 0
$sleepBetweenFailures = 10
$operationIncomplete = $true 

.\Log-Info.ps1 -Message "INFORMATION | LOGGIN IN USING CUSTOMER AZURE TENANT"

while ($operationIncomplete -and $attemptCount -lt $maxFailures) {

    $attemptCount = ($attemptCount + 1)

    if ($attemptCount -ge 2) {
        Start-Sleep -Seconds $sleepBetweenFailures
    }

    try {
        $passwd = convertto-securestring "$ApplicationSecret" -asplaintext -force
        $pscredential = new-object system.management.automation.pscredential("$ApplicationId",  $passwd)
            Add-AzAccount `
                -ServicePrincipal -credential $pscredential `
                -TenantId "$tenantId" `
                -Subscription  "$subscriptionId"

        Select-AzSubscription -SubscriptionId "$subscriptionId"       
        $operationIncomplete = $false
    } 
    catch {
        if ($attemptCount -lt ($maxFailures)) {
            .\Log-Info.ps1 -Message "WARNING | RETRYING $attemptCount/$maxFailures" 

        } else {

            .\Log-Info.ps1 -Message "ERROR | FAILED TO CREATE CREATE $azureConnectionName$($_.Exception.Message)" 
            throw
        }
    }
}