[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]
    $location,

    [Parameter(Mandatory=$true)]
    [string]
    $codeLocation,

    [Parameter(Mandatory=$true)]
    [string]
    $environment,

    [Parameter(Mandatory=$true)]
    [string]
    $clientCode,

    [Parameter(Mandatory=$false)]
    [string]
    $maxRGLimit = 50,

    [Parameter(Mandatory=$false)]
    [string]
    $maxResources = 600
)
                 
    $rgTags = @{ 
        "_business_name"        =   "cs";
        "_azure_region"         =   $location;
        "_contact_person"       =   "johnm@cloudswyft.com";
        "_client_code"          =   $clientCode.ToUpper(); 
        "_environment"          =   $environment.ToUpper()
    }

    for ($i = 1; $i -le $maxRGLimit; $i++) {
        $resourceGroupName = "cs-$location-$clientCode$i-$environment-rgrp".ToUpper()                
        $resourceGroup = Get-AzResourceGroup -Name $resourceGroupName -ErrorVariable NonExistingRG -ErrorAction SilentlyContinue
        
        if($null -eq $resourceGroup){
            New-AzResourceGroup -Name $resourceGroupName -Location $codeLocation -Tags $rgTags -Force | Out-Null
        }

        $resourcesCount =  (Get-AzResource -ResourceGroupName $resourceGroupName).Count

        if($resourcesCount -le $maxResources){
            break
        }
    }

return  $resourceGroupName