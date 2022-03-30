param (
    [Parameter(Mandatory=$false)][String]$ResourceGroupName,
    [Parameter(Mandatory=$false)][String]$ServicePrincipalName,
    [Parameter(Mandatory=$false)][String]$ServicePrincipalPass,
    [Parameter(Mandatory=$false)][String]$SubscriptionId,
    [Parameter(Mandatory=$false)][String]$TenantId,
    [Parameter(Mandatory=$false)][Switch]$ConnectAzure,
    [Parameter(Mandatory=$false)][String]$StorageAccount
)

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


#Region - Upload Files To Storage
Write-Verbose -Message "Getting Azure Storage Account Key"
$StorageAccountKey = Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -AccountName $StorageAccount


Write-Verbose -Message "Creating Azure Storage Account Context"
$StorageContext = New-AzStorageContext -StorageAccountName $StorageAccount -StorageAccountKey $StorageAccountKey[0].Value

Write-Verbose -Message "Checking Azure Storage Account Container"
if(-not [bool](Get-AzStorageContainer -Name "cloudswyft-runbook" -Context $StorageContext -ErrorAction SilentlyContinue)){
    Write-Verbose -Message "Creating Azure Storage Account Container"
    $newContainer = New-AzStorageContainer -Name "cloudswyft-runbook" -Context $StorageContext -ErrorAction SilentlyContinue
    Write-Output $newContainer
}
$sourceFileRootDirectory = ".\";

$container = Get-AzStorageContainer -Name "cloudswyft-runbook" -Context $StorageContext
$container.CloudBlobContainer.Uri.AbsoluteUri
if ($container) {
    $filesToUpload = Get-ChildItem $sourceFileRootDirectory -Recurse -File
    foreach($file in $filesToUpload){
        $targetPath = ($file.fullname.Substring($sourceFileRootDirectory.Length + 1)).Replace("\", "/")
        Write-Verbose "Uploading $("\" + $file.fullname.Substring($sourceFileRootDirectory.Length + 1)) to $($container.CloudBlobContainer.Uri.AbsoluteUri + "/" + $targetPath)"
        Set-AzStorageBlobContent -File $file.fullname -Container $container.Name -Blob $targetPath -Context $StorageContext -Force:$Force | Out-Null
    }
}
#EndRegion

#$newContainer = New-AzStorageContainer -Name "cloudswyft-runbook" -Context $StorageContext -ErrorAction SilentlyContinue
#Write-Output $newContainer


#$StorageAccountKey = "StorageAccountKey"
#$ContainerName = "ContainerName"
#$sourceFileRootDirectory = "AbsolutePathToStartingDirectory" # i.e. D:\Docs

# function Upload-FileToAzureStorageContainer {
#     [cmdletbinding()]
#     param(
#         $StorageAccountName,
#         $StorageAccountKey,
#         $ContainerName,
#         $sourceFileRootDirectory,
#         $Force
#     )

#     $ctx = New-AzureStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey
#     $container = Get-AzureStorageContainer -Name $ContainerName -Context $ctx

#     $container.CloudBlobContainer.Uri.AbsoluteUri
#     if ($container) {
#         $filesToUpload = Get-ChildItem $sourceFileRootDirectory -Recurse -File

#         foreach ($x in $filesToUpload) {
#             $targetPath = ($x.fullname.Substring($sourceFileRootDirectory.Length + 1)).Replace("\", "/")

#             Write-Verbose "Uploading $("\" + $x.fullname.Substring($sourceFileRootDirectory.Length + 1)) to $($container.CloudBlobContainer.Uri.AbsoluteUri + "/" + $targetPath)"
#             Set-AzureStorageBlobContent -File $x.fullname -Container $container.Name -Blob $targetPath -Context $ctx -Force:$Force | Out-Null
#         }
#     }
# }