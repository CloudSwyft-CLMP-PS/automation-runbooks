param (
    [Parameter(Mandatory=$false)][String]$ResourceGroupName,
    [Parameter(Mandatory=$false)][String]$ServicePrincipalName,
    [Parameter(Mandatory=$false)][String]$ServicePrincipalPass,
    [Parameter(Mandatory=$false)][String]$SubscriptionId,
    [Parameter(Mandatory=$false)][String]$TenantId,
    [Parameter(Mandatory=$false)][String]$StorageAccount
)

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
$sourceFileRootDirectory = "$(Get-Location)\templates\";

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