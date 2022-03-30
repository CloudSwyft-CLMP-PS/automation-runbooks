[CMDLETBINDING()]
PARAM (
    [Parameter (Mandatory = $true)]
    [object] $WebhookData
)

function Authenticate-Principal (
    [Parameter(Mandatory=$true)][string]$applicationSubscriptionId,
    [Parameter(Mandatory=$true)][string]$applicationId,
    [Parameter(Mandatory=$true)][string]$applicationTenantId,
    [Parameter(Mandatory=$true)][string]$applicationSecret
    ) {
    
    .\Log-Info.ps1 -Message "INFORMATION | CONNECTING TO CUSTOMER AZURE SUBSCRIPTION"
    .\Login-TenantServicePrincipal.ps1 -SubscriptionId $applicationSubscriptionId -ApplicationId $applicationId -TenantID $applicationTenantId -ApplicationSecret "$applicationSecret"
}



$requestBody                = (ConvertFrom-Json -Inputobject $WebhookData.RequestBody)
$Prefix                     = $requestBody.Prefix
$environment                = $requestBody.Environment 
$clientCode                 = $requestBody.ClientCode
$contactEmail               = $requestBody.ContactEmail
$Region                     = $requestBody.Region
$applicationSubscriptionId  = $requestBody.applicationSubscriptionId
$applicationId              = $requestBody.applicationId
$applicationSecret          = $requestBody.applicationSecret
$applicationTenantId        = $requestBody.applicationTenantId

IF(($null -eq $Prefix) -or ($null -eq $environment) -or ($null -eq $clientCode)){
    WRITE-OUTPUT $WebhookData
    THROW "Incorrect request body."
} 


Authenticate-Principal `
    -ApplicationSubscriptionId $applicationSubscriptionId `
    -ApplicationId $applicationId `
    -ApplicationSecret $applicationSecret `
    -ApplicationTenantId $applicationTenantId

.\Log-Info.ps1 -Message "INFORMATION | Prefix : $Prefix" 
.\Log-Info.ps1 -Message "INFORMATION | CLOUD REGION : $Region" 
.\Log-Info.ps1 -Message "INFORMATION | CLIENT CODE : $clientCode"
.\Log-Info.ps1 -Message "INFORMATION | ENVIRONMENT : $environment" 
.\Log-Info.ps1 -Message "INFORMATION | USE CLOUDSWYFT TENANT : $UseCloudSwyftTenant" 

$resourceGroupName                  =   "cs-$Prefix-$environment-$clientCode-rgrp".ToUpper()
$nsgName                            =   "cs-$Prefix-$environment-$clientCode-nsg".ToUpper()
$vNetName                           =   "cs-$Prefix-$environment-$clientCode-vnet".ToUpper()
$storage                            =   -join("cs", $Prefix,$environment,$clientCode, "stg").ToLower() 
$storageDiag                        =   -join("cs", $Prefix,$environment,$clientCode, "diag").ToLower() 

$rgTags = @{ 
    "_business_name"        =   "cs";
    "_region"               =   $Region;
    "_contact_person"       =   $contactEmail;
    "_client_code"          =   $clientCode.ToUpper(); 
    "_environment"          =   $environment.ToUpper()
}

$tenantRootResourceGroupName = $resourceGroupName

.\Log-Info.ps1 -Message "INFORMATION | SETTING UP ADDITIONAL TAGS" 

$resourceTags =  $rgTags + @{
    "_lab_type"     = "labs";
    "_created"      = (get-date).ToShortDateString();
}

$uniqueId                       = (NEW-GUID).ToString().Replace("-","")

$templateParameterobjectNsg     = @{
    "nsgName"                   = $nsgName.ToUpper();
    "tags"                      = $rgTags;
}

$templateParameterobjectVnet    = @{
    "virtualNetworkName"        =   $vNetName.ToUpper();
    "virtualMachineSubnetName"  =   "virtual-machines-labs-subnet";
    "nsgName"                   =   $nsgName.ToUpper()
    "tags"                      =   $rgTags;
}

$templateParameterobjectStorage = @{
    "storageAccountName"        =   $storage;
    "tags"                      =   $rgTags;
}

$templateParameterobjectStorageDiag = @{
    "storageAccountName"            =   $storageDiag;
    "storageSkuName"                =   "Standard_LRS";
    "tags"                          =   $rgTags;
}

$uniqueId = (NEW-GUID).ToString().Replace("-","")

$templateUrl = "https://raw.githubusercontent.com/CloudSwyft-CLMP-PS/automation-runbooks/dev_env/templates/virtual-network/nsg-web-app.network.json"

$resourceGroup =   Get-AzResourceGroup -Name $resourceGroupName -ErrorVariable Rg -ErrorAction SilentlyContinue  | OUT-NULL

IF ($null -eq $resourceGroup){
    TRY{
        .\Log-Info.ps1 -Message "INFORMATION | Create new resource group [$resourceGroupName]"  | OUT-NULL
        New-AzResourceGroup -Name $resourceGroupName -Location $Region -Tag $rgTags | OUT-NULL
    }
    CATCH{
        WRITE-OUTPUT $_.Exception.Message
    }
}
ELSE{
    .\Log-Info.ps1 -Message "INFORMATION | Resource group [$resourceGroupName] already exist" 
}

.\Log-Info.ps1 -Message "INFORMATION | RESOURCE GROUP NAME : $resourceGroupName" 

.\Log-Info.ps1 -Message "INITIALIZED | CREATING NSG :: $nsgName"
$deploymentNsg = New-AzResourceGroupDeployment `
    -Name (NEW-GUID).ToString().Replace("-","") `
    -ResourceGroupName $resourceGroupName `
    -templateParameterobject  $templateParameterobjectNsg `
    -TemplateUri "https://raw.githubusercontent.com/CloudSwyft-CLMP-PS/automation-runbooks/dev_env/templates/virtual-network/nsg-web-app.network.json" | OUT-NULL
.\Log-Info.ps1 -Message "COMPLETED | CREATING NSG :: $nsgName"

.\Log-Info.ps1 -Message "INITIALIZED | CREATING VIRTUAL NETWORK :: $vNetName"
$deploymentVnet = New-AzResourceGroupDeployment `
    -Name (NEW-GUID).ToString().Replace("-","") `
    -ResourceGroupName $resourceGroupName `
    -templateParameterobject  $templateParameterobjectVnet `
    -TemplateUri "https://raw.githubusercontent.com/CloudSwyft-CLMP-PS/automation-runbooks/dev_env/templates/virtual-network/azuredeploy.network.json" | OUT-NULL
.\Log-Info.ps1 -Message "COMPLETED | CREATING VIRTUAL NETWORK :: $vNetName"

.\Log-Info.ps1 -Message "INITIALIZED | CREATING STORAGE ACCOUNT :: $storage"
New-AzResourceGroupDeployment `
    -Name "$storage-$uniqueId" `
    -ResourceGroupName $resourceGroupName `
    -templateParameterobject  $templateParameterobjectStorage `
    -TemplateUri "https://raw.githubusercontent.com/CloudSwyft-CLMP-PS/automation-runbooks/dev_env/templates/storage-account/azuredeploy.json" | OUT-NULL
.\Log-Info.ps1 -Message "COMPLETED | CREATING STORAGE ACCOUNT :: $storage"

.\Log-Info.ps1 -Message "INITIALIZED | CREATING STORAGE ACCOUNT DIAG :: $storage"
New-AzResourceGroupDeployment `
    -Name "$storage-$uniqueId" `
    -ResourceGroupName $resourceGroupName `
    -templateParameterobject  $templateParameterobjectStorageDiag `
    -TemplateUri "https://raw.githubusercontent.com/CloudSwyft-CLMP-PS/automation-runbooks/dev_env/templates/storage-account/diagnostics.json" | OUT-NULL
.\Log-Info.ps1 -Message "COMPLETED | CREATING STORAGE ACCOUNT  DIAG :: $storage"
