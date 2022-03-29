[CmdletBinding()]
param (
	[Parameter(Mandatory=$false)]
    [object] $WebhookData
)


if ($WebhookData) {  
    # Collect properties of WebhookData  
    $WebhookName 					= $WebHookData.WebhookName  
    $WebhookHeaders 				= $WebHookData.RequestHeader  
    $WebhookBody 					= $WebHookData.RequestBody  
    $Payload 						= (ConvertFrom-Json -InputObject $WebhookBody) 
	#Write-Output $Input 

	
	[string]$VirtualMachineName 	= $Payload.VirtualMachineName
	[string]$ResourceGroupName 		= $Payload.ResourceGroupName
	[string]$GroupCode 				= $Payload.GroupCode
	[string]$Fqdn 					= $Payload.Fqdn
	[string]$subscriptionId 		= $Payload.subscriptionId
	[string]$tenantId 				= $Payload.tenantId
	[string]$ApplicationId 			= $Payload.ApplicationId
	[string]$ApplicationSecret 		= $Payload.ApplicationSecret

	.\Login-TenantServicePrincipal.ps1 `
	 		-SubscriptionId $subscriptionId `
	 		-TenantId $tenantId `
	 		-applicationId $ApplicationId `
	 		-ApplicationSecret $ApplicationSecret


	$templateParameterObjectVirtualMachineExension = @{
		"vmName"    =   $VirtualMachineName;
		"fileUris"  =   "https://raw.githubusercontent.com/onecliquezone/create-sysenv/main/create-environment-variables-windows.ps1";
		"arguments" =   "-ResourceGroupName $ResourceGroupName -VirtualMachineName $VirtualMachineName -ComputerName $VirtualMachineName -TenantId $tenantid -GroupCode $GroupCode -Fqdn $Fqdn";
	}
	
	.\Log-Info.ps1 -Message "INFORMATION | GETTING VIRTUAL MACHINE STATUS"
	
	$vm = Get-AzVm -ResourceGroupName $ResourceGroupName -Name $VirtualMachineName -Status
	
	# if($vm.Statuses[0].Code -notlike "*running"){
	# 	.\Log-Info.ps1 -Message "INFORMATION | VIRTUAL MACHINE POWER STATE IS NOT RUNNING"
	# 	$retry = 5
	# 	do{
	# 		.\Log-Info.ps1 -Message "INFORMATION | STARTING VIRTUAL MACHINE"
	# 		$isStarted = [bool](Start-AzVM -ResourceGroupName $ResourceGroupName -Name $VirtualMachineName)
	# 		$retry--
	# 		if($isStarted){ break; }
	# 	}
	# 	while($retry -ne 0)

	# 	if($retry -eq 0){
	# 		.\Log-Info.ps1 -Message "ERROR | FAILED TO START VIRTUAL MACHINE"
	# 		throw "ERROR | FAILED TO START VIRTUAL MACHINE"
	# 	}
	# 	else{
				
			$uniqueId = (New-Guid).ToString().Replace("-","")
				
			.\Log-Info.ps1 -Message "INFORMATION | CREATING SYSTEM ENVIRONMENT IN VIRTUAL MACHINE"

			New-AzResourceGroupDeployment `
				-Name "vm-extension-$uniqueId" `
				-ResourceGroupName $ResourceGroupName `
				-templateParameterObject  $templateParameterObjectVirtualMachineExension `
				-TemplateUri "https://raw.githubusercontent.com/onecliquezone/create-sysenv/main/windows.template.custom.extension.json"

			.\Log-Info.ps1 -Message "INFORMATION | DEALLOCATING VIRTUAL MACHINE"
			Stop-AzVM -ResourceGroupName $ResourceGroupName -Name $VirtualMachineName -Force
	# 		$retry = 5
	# 		do{
	# 			.\Log-Info.ps1 -Message "INFORMATION | DEALLOCATING VIRTUAL MACHINE"
	# 			$isStarted = [bool](Stop-AzVM -ResourceGroupName $ResourceGroupName -Name $VirtualMachineName -Force)
	# 			$retry--
	# 			if($isStarted){ break; }
	# 		}
	# 		while($retry -ne 0)

	# 		if($retry -eq 0){
	# 			.\Log-Info.ps1 -Message "ERROR | FAILED TO DEALLOCATE VIRTUAL MACHINE"
	# 			throw "ERROR | FAILED TO DEALLOCATE VIRTUAL MACHINE"
	# 		}
	# 		else{
	# 			.\Log-Info.ps1 -Message "INFORMATION | VIRTUAL MACHINE IS DEALLOCATED"
				
	# 		}
	# 	}
	# }
}
else  
{  
    Write-Error -Message 'Runbook was not started from Webhook' -ErrorAction stop  
	#throw "ERROR | RUNBOOK WAS NOT STARTED FROM WEBHOOK"
}  




