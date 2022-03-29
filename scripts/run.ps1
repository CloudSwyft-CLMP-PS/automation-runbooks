param (
    [Parameter(Mandatory=$false)][String]$ResourceGroupName,
    [Parameter(Mandatory=$false)][String]$ServicePrincipalName,
    [Parameter(Mandatory=$false)][String]$ServicePrincipalPass,
    [Parameter(Mandatory=$false)][String]$SubscriptionId,
    [Parameter(Mandatory=$false)][String]$TenantId,
    [Parameter(Mandatory=$false)][String]$RepoURL,
    [Parameter(Mandatory=$false)][String]$RepoAccessToken,
    [Parameter(Mandatory=$false)][String]$SourceControlType = "VsoGit",
    [Parameter(Mandatory=$false)][String]$SourceControlBranch = "main",
    [Parameter(Mandatory=$false)][Switch]$ConnectAzure,
    [Parameter(Mandatory=$false)][Switch]$DeployRunbooks,
    [Parameter(Mandatory=$false)][String]$AutomationAccountName
)

#Region - Test-SourceControlSyncJob
function Test-SourceControlSyncJob {
    param (
        $SourceControlName,
        $ResourceGroupName,
        $AutomationAccountName
    )
    
    $syncjob #= Start-AzAutomationSourceControlSyncJob -SourceControlName $SourceControlName -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName

    $syncJobs = Get-AzAutomationSourceControlSyncJob -SourceControlName $SourceControlName -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName
    while($true){
        $syncJobs = Get-AzAutomationSourceControlSyncJob -SourceControlName $SourceControlName -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName
        if($syncJobs[0].ProvisioningState -like "*Failed*"){
            Write-Verbose -Message "Failed Retrying sync job"
            $syncjob = Start-AzAutomationSourceControlSyncJob -SourceControlName $SourceControlName -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName
        }

        if($syncJobs[0].ProvisioningState -like "*Completed*"){
            Write-Verbose -Message $syncjob
            break;
        }
    }
}
#EndRegion

#Region - Connecting to Azure
if($ConnectAzure.IsPresent) {
    Write-Verbose -Message "Checking and Installing Azure Powershell Module"
    if (-not(Get-Module -Name Az.Accounts -ListAvailable)){
        Write-Warning "Module 'Az.Accounts' is missing or out of date. Installing module now."
        Install-Module -Name Az.Accounts, Az.Resources, Az.Automation -Scope CurrentUser -Force -AllowClobber
    }

    Write-Verbose -Message "Connecting to Azure"
    $ServicePrincipalPassword = ConvertTo-SecureString -AsPlainText -Force -String $ServicePrincipalPass
    $azureAppCred = New-Object System.Management.Automation.PSCredential ($ServicePrincipalName,$ServicePrincipalPassword)
    Connect-AzAccount -ServicePrincipal -Credential $azureAppCred -Tenant $tenantId -Subscription $SubscriptionId
}
#EndRegion


#Region - Deploying the Azure Runbooks
if($DeployRunbooks.IsPresent) {
    $Runbooks = (Get-ChildItem -Path ".\runbooks").Name
    $AutomationSourceControl = Get-AzAutomationSourceControl -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName
    # Adding the names of existing runbooks into an Array
    $AutomationSourceControlList = New-Object -TypeName System.Collections.ArrayList
    foreach($sourceControl in $AutomationSourceControl){ 
        $AutomationSourceControlList.Add($sourceControl.Name)
    }
    
    # foreach loop running through all the runbooks located in your repository
    foreach($Runbook in $Runbooks) {
        $Runbook = $Runbook.Replace(".ps1","")
        if($AutomationSourceControlList -contains $Runbook) {
            # If the runbook exists in Azure, then just run a sync on it
            try {
                Write-Verbose -Message "Runbook: $($Runbook) was found in Automation Source Control list. Updating source code now"
                Start-AzAutomationSourceControlSyncJob -SourceControlName $Runbook -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName
            }
            catch {
                Write-Error -Message "$($_)"
            }
        }
        else {
            # If the runbooks doesn't exist, the create a new source control job, and sync it to Azure
            Write-Verbose -Message "Runbook hasn't been connected with Azure Automation. Uploading source code for runbook"
            $FolderPath = "\runbooks"
            try {
                New-AzAutomationSourceControl -ResourceGroupName $ResourceGroupName `
                    -AutomationAccountName $AutomationAccountName `
                    -Name $Runbook `
                    -RepoUrl $RepoURL `
                    -SourceType $SourceControlType `
                    -Branch $SourceControlBranch `
                    -FolderPath $FolderPath `
                    -AccessToken (ConvertTo-SecureString $RepoAccessToken -AsPlainText -Force)
                
                Start-AzAutomationSourceControlSyncJob -SourceControlName $Runbook -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName
            }
            catch {
                Write-Error -Message "$($_)"
            }
        }
    }
    foreach($Runbook in $Runbooks) {
        $Runbook = $Runbook.Replace(".ps1","")
        Test-SourceControlSyncJob -SourceControlName $Runbook -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName
    }

}
#EndRegion