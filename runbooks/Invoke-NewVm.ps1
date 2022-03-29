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
        $location                       = $requestBody.location
        $environment                    = $requestBody.environment 
        $clientCode                     = $requestBody.clientCode
        $imageName                      = $requestBody.imageName
        $vmSize                         = $requestBody.size
        $tenantId                       = $requestBody.tenantId
        $groupCode                      = $requestBody.groupCode
        $fqdn                           = $requestBody.fqdn
        $useCloudSwyftTenant            = $requestBody.useCloudSwyftTenant
        $computerName                   = $requestBody.computerName
        $defaultVhdLocationPath         = $requestBody.defaultVhdLocationPath
        $templateName                   = $requestBody.templateName
        $isCustomTemplate               = $requestBody.isCustomTemplate
        $diskSizeGB                     = $requestBody.TempStorageSizeInGb
        $isVirtualMachineReadyForUsage  = 0
        $imageUri                       = $requestBody.imageUri
        $contactPerson                  = $requestBody.contactPerson
        $storage                        = $requestBody.storage

        
        # $finalVMSize =  $vmSize 
        # if($vmSize -eq "Standard_B2s" -or $vmSize -eq "Standard_B2ms"){
        #     $vmSize  = "Standard_D2s_v3"
        #     .\Log-Info.ps1 -Message "INFORMATION | USING [$vmSize] AS TEMPORARY SIZE, AFTER PROVISIONING IS COMPLETE SIZE WILL BE RESIZE TO [$finalVMSize]"
        # }

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
            -ApplicationSubscriptionId $applicationSubscriptionId `
            -ApplicationId $applicationId `
            -ApplicationSecret $applicationSecret `
            -ApplicationTenantId $applicationTenantId
        
        
        .\Log-Info.ps1 -Message "INFORMATION | RETRIEVING TENANT DETAILS"
        $tenantRootResourceGroupName  =   "cs-$location-$clientCode-$environment-rgrp".ToUpper()
        $resourceGroup      =   Get-AzResourceGroup -Name $tenantRootResourceGroupName -ErrorVariable Rg -ErrorAction SilentlyContinue
        $nsgName            =   "cs-$location-$clientCode-$environment-nsg".ToUpper()
        $vNetName           =   "cs-$location-$clientCode-$environment-vnet".ToUpper()
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
    
        $uniqueId       = (New-Guid).ToString().Replace("-","")
        $resourceName   = "cs-$clientCode-$image-VM-$uniqueId".ToUpper()            
        $uniqueId       = (New-Guid).ToString().Replace("-","")
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
            -clientCode $clientCode `
            -codeLocation $codeLocation
    
            .\Log-Info.ps1 -Message "INFORMATION | Resource group to be used :: $labResourceGroupName"
            
        if($isCustomTemplate){
            $resourceName = $templateName
            .\Log-Info.ps1 -Message "INFORMATION | STARTED CREATION OF VIRTUAL MACHINE FOR CUSTOM TEMPLATE"
        }   
        else{
            .\Log-Info.ps1 -Message "INFORMATION | STARTED CREATION OF VIRTUAL MACHINE FOR END USER"
            $resourceName = "cs-$clientCode-$environment-VM-$uniqueId".ToLower()
        } 
        
        $password = Get-RandomCharacters -length 10 -characters 'abcdefghiklmnoprstuvwxyz'
        $password += Get-RandomCharacters -length 2 -characters 'ABCDEFGHKLMNOPRSTUVWXYZ'
        $password += Get-RandomCharacters -length 2 -characters '1234567890'
        $password += Get-RandomCharacters -length 2 -characters "@_^"
        $password = Scramble-String $password
    
        $username = Get-RandomCharacters -length 10 -characters 'abcdefghiklmnoprstuvwxyz'
        $username = "csonline$username"
        $virtualMachineName =  $resourceName.ToUpper();
        $templateParameterObjectVirtualMachine = @{
            "networkSecurityGroupId"    =   $nsgId;
            "subnetName"                =   "virtual-machines-labs-subnet";
            "virtualNetworkId"          =   $vnetId ;
            "virtualMachineName"        =   $virtualMachineName;
            "computerName"              =   $computerName;
            "adminUsername"             =   $username;
            "adminPassword"             =   $password;
            "storageAccountName"        =   $storage;
            "imageUri"                  =   "https://$storage.blob.core.windows.net/virtual-machine-image-templates/$imageName";
            "tags"                      =   $resourceTags;
            "virtualMachineSize"        =   $vmSize;
            "diskSizeGB"                =   $diskSizeGB;
            "defaultVhdLocationPath"    =   "$defaultVhdLocationPath";
            "newTemplateName"           =   $templateName;
            "publicIpAddressType"		=	$publicIpAddressType;
            "publicIpAddressSku"		=	$publicIpAddressSku;
        }
            
        $uniqueId = (New-Guid).ToString().Replace("-","")
        $vmTemplateName = "windows.template.json"
        $vmTemplateNameExtentionName = "windows.template.custom.extension.json"
    
        $OSTYPE = "WINDOWS"
        if($imageName.ToUpper() -match "LINUX" -or $imageName.ToUpper() -match "UBUNTU"){
            $vmTemplateName = "linux.template.json"
            $OSTYPE = "LINUX"
        }

        .\Log-Info.ps1 -Message "INFORMATION | STARTING VIRTUAL MACHINE CREATION"               
        .\Log-Info.ps1 -Message "INFORMATION | CALLING ARM DEPLOYMENT FOR VIRTUAL MACHINE"
        .\Log-Info.ps1 -Message "INFORMATION | DEPLOYMENT NAME $resourceName"      
        .\Log-Info.ps1 -Message "INFORMATION | RESOURCEGROUP NAME $labResourceGroupName"

        $defaultVhdLocationPath = $defaultVhdLocationPath.Replace("/","")
        $customerSubscriptionId =  (get-azcontext).Subscription.Id        
        $vmResourceId =  "/subscriptions/$customerSubscriptionId/resourceGroups/$labResourceGroupName/providers/Microsoft.Compute/virtualMachines/$virtualMachineName"
        $publicIpResourceId = "/subscriptions/$customerSubscriptionId/resourceGroups/$labResourceGroupName/providers/Microsoft.Network/publicIPAddresses/$virtualMachineName"
        $nicResourceId = "/subscriptions/$customerSubscriptionId/resourceGroups/$labResourceGroupName/providers/Microsoft.Network/networkInterfaces/$virtualMachineName"
        $osDiskUri =    [System.Web.HttpUtility]::UrlEncode("https://$storage.blob.core.windows.net/$defaultVhdLocationPath/$virtualMachineName.vhd")

        $virtualMachineBrokeredMessage = @{
            "Operation"                 = "UPDATE";
            "Status"                    = $virtual_machine_provisioning_started;
            "ClientCode"                = $clientCode;
            "RequestID"                 = $requestId;
            "Dns"                       = "NA";
            "PublicIpResourceId"        = $publicIpResourceId;
            "VirtualMachineResourceId"  = $vmResourceId;
            "NicId"                     = $nicResourceId;
            "OsType"                    = $OSTYPE;
            "OsDiskUri"                 = $osDiskUri;
            "VirtualMachineName"        = $virtualMachineName;
            "AdminUsername"             = $username;
            "AdminPassword"             = $password;
            "IsReadyForUsage"           = 0;
        }

        $vmMessage = ($virtualMachineBrokeredMessage | ConvertTo-Json -Compress -Depth 10) 

        $deploymentVm = New-AzResourceGroupDeployment `
            -Name "virtual-machine-$uniqueId".ToLower() `
            -ResourceGroupName $labResourceGroupName `
            -templateParameterObject  $templateParameterObjectVirtualMachine `
            -TemplateUri "https://$storageAccountName.blob.core.windows.net/labs-infrastructure/$($vmTemplateName)$sharedStorageAccountSasToken" `
            -ErrorVariable ErrorCreatingVm `
            -ErrorAction SilentlyContinue `
            -DeploymentDebugLogLevel All

        if($ErrorCreatingVm)
        {
            Write-Output $ErrorCreatingVm
    
            if($ErrorCreatingVm -match "The VM may still finish provisioning successfully" -or $ErrorCreatingVm -match "did not finish in the allotted time"){
                .\Log-Info.ps1 -Message "INFORMATION | TIMEOUT OCCURED WHILE PROVISIONING VM"
                .\Log-Info.ps1 -Message "INFORMATION | ATTEMPTING TO PROCEED TO CATCH CREATED RESOURCES"
            }
            else{
                .\Log-Info.ps1 -Message "INFORMATION | UNKNOWN ERROR OCCURED"
                throw $deploymentVm
            }
        }  
        
        .\Log-Info.ps1 -Message "INFORMATION | RETRIEVING VIRTUAL MACHINE DETAILS"
        $newPublicIp = (Get-AzPublicIpAddress -Name $virtualMachineName -ResourceGroupName $labResourceGroupName)
        $newNetworkInterfaceCard = (Get-AzNetworkInterface -Name $virtualMachineName -ResourceGroupName $labResourceGroupName)
        $newVM = Get-AzVM -ResourceGroupName $labResourceGroupName  -Name $virtualMachineName
            
        if($ErrorCreatingVm){
            $TABLE_ROW_STATUS = $virtual_machine_provisioning_failure
            $isVirtualMachineReadyForUsage = 0
            $virtualMachineDeploymentStatus = 0
        }
        else{
            $TABLE_ROW_STATUS = $virtual_machine_provisioning_success
            $isVirtualMachineReadyForUsage = 1
            $virtualMachineDeploymentStatus = 1
        }
    }
    catch{
        write-output $_
        throw $_
    }
}