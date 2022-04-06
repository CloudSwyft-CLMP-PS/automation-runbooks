[CmdletBinding()]
PARAM (
    [Parameter (Mandatory = $true)]
    [object] $WebhookData
)


$ErrorActionPreference = "Stop"

function Authenticate-Principal (
    [Parameter(Mandatory=$true)][string]$applicationSubscriptionId,
    [Parameter(Mandatory=$true)][string]$applicationId,
    [Parameter(Mandatory=$true)][string]$applicationTenantId,
    [Parameter(Mandatory=$true)][string]$applicationSecret
    ) {

    .\Log-Info.ps1 -Message "INFORMATION | CONNECTING TO CUSTOMER AZURE SUBSCRIPTION"
    .\Login-TenantServicePrincipal.ps1 -SubscriptionId $applicationSubscriptionId -ApplicationId $applicationId -TenantID $applicationTenantId -ApplicationSecret "$applicationSecret"
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
        $requestBody                    = (ConvertFrom-Json -InputObject $WebhookData.RequestBody)
        $location                       = $requestBody.location # azure region
        $environment                    = $requestBody.environment # Emvironment
        $clientCode                     = $requestBody.clientCode # Prefix
        $imageName                      = $requestBody.imageName
        $vmName                         = $requestBody.vmName # Virtual machine name
        $vmSize                         = $requestBody.size
        $tenantId                       = $requestBody.tenantId
        $groupCode                      = $clientCode
        $fqdn                           = $requestBody.fqdn
        $templateName                   = $requestBody.templateName
        $isCustomTemplate               = $requestBody.isCustomTemplate
        $diskSizeGB                     = $requestBody.TempStorageSizeInGb
        $imageUri                       = $requestBody.imageUri
        $contactPerson                  = $requestBody.contactPerson
        $storage                        = $requestBody.storage

        
        $applicationSubscriptionId      = $requestBody.ApplicationSubscriptionId
        $applicationId                  = $requestBody.ApplicationId
        $applicationTenantId            = $requestBody.ApplicationTenantId    
        $applicationSecret              = $requestBody.ApplicationSecret   

        if(($null -eq $location) -or ($null -eq $environment) -or ($null -eq $clientCode) -or $($null -eq $imageName)){
            write-output $WebhookData
            throw "Incorrect request body."
        }

        Authenticate-Principal `
            -ApplicationSubscriptionId $applicationSubscriptionId `
            -ApplicationId $applicationId `
            -ApplicationSecret $applicationSecret `
            -ApplicationTenantId $applicationTenantId
        
        
        .\Log-Info.ps1 -Message "INFORMATION | RETRIEVING TENANT DETAILS"
        $tenantRootResourceGroupName    =  "cs-$clientCode-$environment-rgrp".ToUpper()
        #$resourceGroup      =   Get-AzResourceGroup -Name $tenantRootResourceGroupName -ErrorVariable Rg -ErrorAction SilentlyContinue
        $nsgName                        =   "cs-$clientCode-$environment-nsg".ToUpper()
        $vNetName                       =   "cs-$clientCode-$environment-vnet".ToUpper()
        #$storage            =   -join("cs", $location,$clientCode,$environment, "stg").ToLower() 
        

        $rgTags = @{ 
            "_business_name"        =   "cs";
            "_azure_region"         =   $location;
            "_contact_person"       =   $contactPerson;
            "_client_code"          =   $clientCode.ToUpper(); 
            "_environment"          =   $environment.ToUpper()
        }

        .\Log-Info.ps1 -Message "INFORMATION | SETTING UP ADDITIONAL TAGS FOR RESOURCES" 
        
        $resourceTags =  $rgTags + @{
            "_lab_type"     = "virtualmachine";
            "_created"      = (get-date).ToShortDateString();
        }

        $resourceName   = $vmName.ToUpper()            
        $vnetId         = (Get-AzVirtualNetwork -Name $vNetName -ResourceGroupName $tenantRootResourceGroupName).Id
        $nsgId          = (Get-AzNetworkSecurityGroup -Name $nsgName -ResourceGroupName $tenantRootResourceGroupName).Id 
        $vnet 			= Get-AzVirtualNetwork -Name  $vNetName -ResourceGroupName $tenantRootResourceGroupName
        $vnetId         = $vnet.Id
        
        if($null -eq $vnet.Subnets.NatGateway){
            $publicIpAddressType = "Dynamic"
            $publicIpAddressSku = "Basic"
        }else{
            $publicIpAddressType = "Static"
            $publicIpAddressSku = "Standard"
        }
    
        $labResourceGroupName =.\Set-ResourceGroup.ps1 `
            -Location $location `
            -Environment $environment `
            -clientCode $clientCode
    
            .\Log-Info.ps1 -Message "INFORMATION | Resource group to be used :: $labResourceGroupName"
            
        if($isCustomTemplate){
            $resourceName = $templateName # If no vm name pass custom template
            .\Log-Info.ps1 -Message "INFORMATION | STARTED CREATION OF VIRTUAL MACHINE FOR CUSTOM TEMPLATE"
        }   
        else{
            .\Log-Info.ps1 -Message "INFORMATION | STARTED CREATION OF VIRTUAL MACHINE FOR END USER" # With VM name
            $resourceName = $vmName.ToUpper()  #CS-BINUS-P-VM-09240dec-43e6-4def-b6a5-2a113242f796
        } 
        
        $password = Get-RandomCharacters -length 10 -characters 'abcdefghiklmnoprstuvwxyz'
        $password += Get-RandomCharacters -length 2 -characters 'ABCDEFGHKLMNOPRSTUVWXYZ'
        $password += Get-RandomCharacters -length 2 -characters '1234567890'
        $password += Get-RandomCharacters -length 2 -characters "@_^"
        $password = Scramble-String $password
    
        $username = Get-RandomCharacters -length 10 -characters 'abcdefghiklmnoprstuvwxyz'
        $username = "csonline$username"
        $virtualMachineName =  $resourceName.ToUpper();
        
        $computerName = Get-RandomCharacters -length 5 -characters 'ABCDEFGHKLMNOPRSTUVWXYZ'
        $computerName += Get-RandomCharacters -length 5 -characters '1234567890'
        $computerName = "CS"+(Scramble-String $computerName)
        $computerName = $computerName.ToUpper()
        
        #$virtualMachineName = $resourceName

        $templateParameterObjectVirtualMachine = @{
            "networkSecurityGroupId"    =   $nsgId;
            "subnetName"                =   "virtual-machines-labs-subnet";
            "virtualNetworkId"          =   $vnetId ;
            "virtualMachineName"        =   $virtualMachineName;
            "computerName"              =   $computerName;
            "adminUsername"             =   $username;
            "adminPassword"             =   $password;
            "storageAccountName"        =   $storage;
            "imageUri"                  =   $imageUri
            "tags"                      =   $resourceTags;
            "virtualMachineSize"        =   $vmSize;
            "diskSizeGB"                =   $diskSizeGB;
            "newTemplateName"           =   $resourceName;
            "publicIpAddressType"		=	$publicIpAddressType;
            "publicIpAddressSku"		=	$publicIpAddressSku;
        }
            
        $uniqueId = (New-Guid).ToString().Replace("-","")
        $vmTemplateName = "https://raw.githubusercontent.com/CloudSwyft-CLMP-PS/automation-runbooks/dev_env/templates/windows.template.json"
    
        $OSTYPE = "WINDOWS"
        if($imageName.ToUpper() -match "LINUX" -or $imageName.ToUpper() -match "UBUNTU"){
            $vmTemplateName = "https://raw.githubusercontent.com/CloudSwyft-CLMP-PS/automation-runbooks/dev_env/templates/linux.template.json"
            $OSTYPE = "LINUX"
        }

        .\Log-Info.ps1 -Message "INFORMATION | STARTING VIRTUAL MACHINE CREATION"               
        .\Log-Info.ps1 -Message "INFORMATION | CALLING ARM DEPLOYMENT FOR VIRTUAL MACHINE"
        .\Log-Info.ps1 -Message "INFORMATION | DEPLOYMENT NAME $resourceName"      
        .\Log-Info.ps1 -Message "INFORMATION | RESOURCEGROUP NAME $labResourceGroupName"
        
        $deploymentVm = New-AzResourceGroupDeployment `
            -Name "virtual-machine-$uniqueId".ToLower() `
            -ResourceGroupName $labResourceGroupName `
            -templateParameterObject  $templateParameterObjectVirtualMachine `
            -TemplateUri $vmTemplateName `
            -ErrorVariable ErrorCreatingVm `
            -ErrorAction SilentlyContinue `
            -DeploymentDebugLogLevel All
        $deploymentVm
        $ErrorCreatingVm
        # if($errorcreatingvm)
        # {
        #     write-output $errorcreatingvm
    
        #     if($errorcreatingvm -match "the vm may still finish provisioning successfully" -or $errorcreatingvm -match "did not finish in the allotted time"){
        #         .\log-info.ps1 -message "information | timeout occured while provisioning vm"
        #         .\log-info.ps1 -message "information | attempting to proceed to catch created resources"
        #     }
        #     else{
        #         .\log-info.ps1 -message "information | unknown error occured"
        #         throw $deploymentvm
        #     }
        # }  

        $templateParameterObjectVirtualMachineExension = @{
            "vmName"    =   $virtualMachineName;
            "fileUris"  =   "https://raw.githubusercontent.com/CloudSwyft-CLMP-PS/automation-runbooks/dev_env/templates/create-environment-variables-windows.ps1";
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
                    -TemplateUri "https://raw.githubusercontent.com/CloudSwyft-CLMP-PS/automation-runbooks/dev_env/templates/windows.template.custom.extension.json"

                .\Log-Info.ps1 -Message "INFORMATION | COMPLETED INSTALLING VM EXTENSION FOR ENVIRONMENT VARIABLES"

                
			    .\Log-Info.ps1 -Message "INFORMATION | DEALLOCATING VIRTUAL MACHINE"
			    Stop-AzVM -ResourceGroupName $labResourceGroupName -Name $virtualMachineName -Force
                
			    .\Log-Info.ps1 -Message "INFORMATION | DEALLOCATING VIRTUAL MACHINE IS DONE"
            }
        }

    }
    catch{
        write-output $_
        throw $_
    }
}
New-VirtualMachine


