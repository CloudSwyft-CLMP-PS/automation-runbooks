[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [String]
    $ResourceGroupName,

    [Parameter(Mandatory=$true)]
    [String]
    $VirtualMachineName,

    [Parameter(Mandatory=$true)]
    [String]
    $ComputerName,

	[Parameter(Mandatory=$true)]
    [String]
    $TenantId,

	[Parameter(Mandatory=$true)]
    [String]
    $GroupCode,

	[Parameter(Mandatory=$true)]
    [String]
    $Fqdn
)
[System.Environment]::SetEnvironmentVariable('CS_RGN', $ResourceGroupName, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('CS_VMA', $VirtualMachineName, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('CS_NAM', $ComputerName, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('CS_TID', $TenantId, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('CS_GCD', $GroupCode, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('CS_FQD', $Fqdn, [System.EnvironmentVariableTarget]::Machine)