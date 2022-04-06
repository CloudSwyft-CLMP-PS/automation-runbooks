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
$contactEmail               = $requestBody.ContactEmail
$Region                     = $requestBody.Region
$applicationSubscriptionId  = $requestBody.applicationSubscriptionId
$applicationId              = $requestBody.applicationId
$applicationSecret          = $requestBody.applicationSecret
$applicationTenantId        = $requestBody.applicationTenantId

IF(($null -eq $Prefix) -or ($null -eq $environment)){
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
.\Log-Info.ps1 -Message "INFORMATION | ENVIRONMENT : $environment" 
.\Log-Info.ps1 -Message "INFORMATION | USE CLOUDSWYFT TENANT : $UseCloudSwyftTenant" 

$resourceGroupName                  =   "cs-$Prefix-$environment-rgrp".ToUpper()
$nsgName                            =   "cs-$Prefix-$environment-nsg".ToUpper()
$vNetName                           =   "cs-$Prefix-$environment-vnet".ToUpper()

$rgTags = @{ 
    "_business_name"        =   "cs";
    "_region"               =   $Region;
    "_contact_person"       =   $contactEmail;
    "_environment"          =   $environment.ToUpper()
}

.\Log-Info.ps1 -Message "INFORMATION | SETTING UP ADDITIONAL TAGS" 

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
$deploymentNsg
.\Log-Info.ps1 -Message "COMPLETED | CREATING NSG :: $nsgName"

.\Log-Info.ps1 -Message "INITIALIZED | CREATING VIRTUAL NETWORK :: $vNetName"
$deploymentVnet = New-AzResourceGroupDeployment `
    -Name (NEW-GUID).ToString().Replace("-","") `
    -ResourceGroupName $resourceGroupName `
    -templateParameterobject  $templateParameterobjectVnet `
    -TemplateUri "https://raw.githubusercontent.com/CloudSwyft-CLMP-PS/automation-runbooks/dev_env/templates/virtual-network/azuredeploy.network.json" | OUT-NULL
$deploymentVnet
.\Log-Info.ps1 -Message "COMPLETED | CREATING VIRTUAL NETWORK :: $vNetName"
