[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]
    $Message
)

WRITE-OUTPUT "[$(([DateTime]::UtcNow.AddHours(8)).ToString("HH:mm:ss"))] | $Message"