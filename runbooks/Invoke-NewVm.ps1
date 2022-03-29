[CmdletBinding()]
PARAM (
    [Parameter (Mandatory = $true)]
    [object] $WebhookData
)


$ErrorActionPreference = "Stop"

function Authenticate-Principal (
    [Parameter(Mandatory=$true)][bool]$LoginAsCloudSwyft,
    [Parameter(Mandatory=$true)][string]$applicationSubscriptionId,
    [Parameter(Mandatory=$true)][string]$applicationId,
    [Parameter(Mandatory=$true)][string]$applicationTenantId,
    [Parameter(Mandatory=$true)][string]$applicationSecret
    ) {

    if($LoginAsCloudSwyft){
        .\Login-ServicePrincipalPs.ps1     
    }
    else{            
        .\Log-Info.ps1 -Message "INFORMATION | CONNECTING TO CUSTOMER AZURE SUBSCRIPTION"
        .\Login-TenantServicePrincipal.ps1 -SubscriptionId $applicationSubscriptionId -ApplicationId $applicationId -TenantID $applicationTenantId -ApplicationSecret "$applicationSecret"
    }
}

function Get-RandomCharacters(
    [Parameter(Mandatory=$true)][int]$length, 
    [Parameter(Mandatory=$true)][string]$characters
    ) {
    
        $random = 1..$length | ForEach-Object { Get-Random -Maximum $characters.length }
        $private:ofs=""
        return [String]$characters[$random]
}

function Scramble-String(
    [Parameter(Mandatory=$true)][string]$inputString
    ) {     
        
        $characterArray = $inputString.ToCharArray()   
        $scrambledStringArray = $characterArray | Get-Random -Count $characterArray.Length     
        $outputString = -join $scrambledStringArray
        
        return $outputString 
}

function New-VirtualMachine {
    try{
        $requestBody                        = (ConvertFrom-Json -InputObject $WebhookData.RequestBody)
        $location                           = $requestBody.location
        $environment                        = $requestBody.environment 
        $clientCode                         = $requestBody.clientCode
        $imageName                          = $requestBody.imageName
        $vmSize                             = $requestBody.size
        $tenantId                           = $requestBody.tenantId
        $groupCode                          = $requestBody.groupCode
        $fqdn                               = $requestBody.fqdn
        $useCloudSwyftTenant                = $requestBody.useCloudSwyftTenant
        $computerName                       = $requestBody.computerName
        $defaultVhdLocationPath             = $requestBody.defaultVhdLocationPath
        $templateName                       = $requestBody.templateName
        $isCustomTemplate                   = $requestBody.isCustomTemplate
        $diskSizeGB                         = $requestBody.TempStorageSizeInGb
        $isVirtualMachineReadyForUsage      = 0

        
        $finalVMSize =  $vmSize 
        if($vmSize -eq "Standard_B2s" -or $vmSize -eq "Standard_B2ms"){
            $vmSize  = "Standard_D2s_v3"
            .\Log-Info.ps1 -Message "INFORMATION | USING [$vmSize] AS TEMPORARY SIZE, AFTER PROVISIONING IS COMPLETE SIZE WILL BE RESIZE TO [$finalVMSize]"
        }

        $applicationSubscriptionId              = $requestBody.ApplicationSubscriptionId
        $applicationId                          = $requestBody.ApplicationId
        $applicationTenantId                    = $requestBody.ApplicationTenantId       
        $requestId                              = $requestBody.RequestId
        $codeLocation                           = $requestBody.Region
        $virtual_machine_provisioning_started   = 10001
        $virtual_machine_provisioning_success   = 10002
        $virtual_machine_provisioning_failure   = 10003
        $virtualMachineDeploymentStatus         = 1 ### 1 Determines Success, 0 Failure

        if(($null -eq $location) -or ($null -eq $environment) -or ($null -eq $clientCode) -or $($null -eq $imageName)){
            write-output $WebhookData
            throw "Incorrect request body."
        }

        Authenticate-Principal `
            -LoginAsCloudSwyft $useCloudSwyftTenant `
            -ApplicationSubscriptionId $applicationSubscriptionId `
            -ApplicationId $applicationId `
            -ApplicationSecret $applicationSecret `
            -ApplicationTenantId $applicationTenantId
        
        
        .\Log-Info.ps1 -Message "INFORMATION | DEVOPS DETAILS"
        $storageAccountName             = (Get-AutomationVariable -Name 'aa-storage-account-name')
        #$serviceBUS                     = (Get-AutomationVariable -Name 'aa-devops-service-bus-name')
        #$topicName                      = 'virtualmachine_request'
        #$resourceUri                    = "https://$serviceBUS.servicebus.windows.net/$topicName"
        #$RestApiUri                     = "$resourceUri/messages?timeout=60"
        $sharedStorageAccountSasToken   = (Get-AutomationVariable -Name 'aa-shared-storage-sas-token') 
        #$senderSasToken                 = (Get-AutomationVariable -Name 'aa-servce-bus-shared-sas-token')


        .\Log-Info.ps1 -Message "INFORMATION | RETRIEVING TENANT DETAILS"
        $tenantRootResourceGroupName  =   "cs-$location-$clientCode-$environment-rgrp".ToUpper()
        $resourceGroup      =   Get-AzResourceGroup -Name $tenantRootResourceGroupName -ErrorVariable Rg -ErrorAction SilentlyContinue
        $nsgName            =   "cs-$location-$clientCode-$environment-nsg".ToUpper()
        $vNetName           =   "cs-$location-$clientCode-$environment-vnet".ToUpper()
        $storage            =   -join("cs", $location,$clientCode,$environment, "stg").ToLower() 
        

        $rgTags = @{ 
            "_business_name"        =   "cs";
            "_azure_region"         =   $location;
            "_contact_person"       =   "johnm@cloudswyft.com";
            "_client_code"          =   $clientCode.ToUpper(); 
            "_environment"          =   $environment.ToUpper()
        }

        $templateParameterObjectVirtualMachineExension = @{
            "vmName"    =   $virtualMachineName;
            "fileUris"  =   ".\runbooks\create-environment-variables-windows.ps1";
            "arguments" =   "-ResourceGroupName $labResourceGroupName -VirtualMachineName $virtualMachineName -ComputerName $computerName -TenantId $tenantId -GroupCode $groupCode -Fqdn $fqdn";
        }

        if($imageName -match "LINUX" -or $imageName.ToUpper() -match "UBUNTU"){
            .\Log-Info.ps1 -Message "INFORMATION | POWERSHELL EXTENSION HAS BEEN IGNORED ON LINUX VIRTUAL MACHINE"
        }
        else{
            if($ErrorCreatingVm){
                .\Log-Info.ps1 -Message "INFORMATION | IGNORING INSTALLATION OF VIRTUAL MACHINE EXTENSION AS DEPLOYMENT FAILED"
            }
            else{
                .\Log-Info.ps1 -Message "INFORMATION | START INSTALLING VM EXTENSION FOR ENVIRONMENTVARIABLES"
                New-AzResourceGroupDeployment `
                    -Name "vm-extension-$uniqueId" `
                    -ResourceGroupName $labResourceGroupName `
                    -templateParameterObject  $templateParameterObjectVirtualMachineExension `
                    -TemplateUri "https://$storageAccountName.blob.core.windows.net/labs-infrastructure/$vmTemplateNameExtentionName$sharedStorageAccountSasToken"
                
                .\Log-Info.ps1 -Message "INFORMATION | COMPLETED INSTALLING VM EXTENSION FOR ENVIRONMENT VARIABLES"
            }
        }
        
    }
    catch{
        write-output $_
        throw $_
    }
}