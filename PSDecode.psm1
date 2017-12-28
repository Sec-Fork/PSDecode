<#
.SYNOPSIS
    Obfuscated PowerShell Script Decoder
.DESCRIPTION
    This is a PowerShell script for deobfuscating other encoded PowerShell scripts. Often, malicious PowerShell scripts have several layers of encodings (Replace, Base64Decode, etc...) that, once decoded, are executed via a call to Invoke-Expression (IEX, &, .), Invoke-Command, etc... This script employs a technique called method overriding that enables us to essentially intercept calls to functions that I have accounted for within this script and print out the arguments being passed to it (a.k.a what the script was trying to execute).

    ** Important Note: Only run this script within an isolated sandbox. If the encoded powershell attempts to execute a function which I have not accounted for, there is a chance it could execute.**
.NOTES
    File Name  : PSDecode.psm1
    Author     : @R3MRUM 
.LINK
    https://github.com/R3MRUM/PSDecode
.LINK
    https://twitter.com/R3MRUM
.LINK
    https://r3mrum.wordpress.com/
.EXAMPLE
    PSDecode .\encoded_ps.ps1

.EXAMPLE
    Get-Content .\encoded_ps.ps1 | PSDecode 
.COMPONENT
#>

function PSDecode {
    [CmdletBinding()]
    param(
        [Parameter( `
                Mandatory=$True, `
                Valuefrompipeline = $True)]
        [PSObject[]]$InputObject
       )

$Invoke_Expression_Override = @'
function Invoke-Expression()
    {
        param(
            [Parameter( `
                Mandatory=$True, `
                Valuefrompipeline = $True)]
            [String]$Command
        )
        Write-Host $Command
    }
'@

$Invoke_Command_Override = @'
function Invoke-Command ()
    {
        param(
            [Parameter( `
                Mandatory=$True, `
                Valuefrompipeline = $True)]
            [String]$Command
        )
        Write-Host "%#[Invoke-Command] Execute/Open: $($Command)"
    }
'@

$Invoke_Item_Override = @'
function Invoke-Item()
    {
        param(
            [Parameter( `
                Mandatory=$True, `
                Valuefrompipeline = $true)]
            [String]$Item
        )
        Write-Host "%#[Invoke-Item] Execute/Open: $($Item)"
    }
'@

$New_Object_Override = @'
function new-object {
        param(
            [Parameter( `
                Mandatory=$True, `
                Valuefrompipeline = $True)]
            [String]$Obj
        )

        if($Obj -eq 'System.Net.WebClient'){
            $webclient_obj = [PsCustomObject]
            Add-Member -memberType ScriptMethod -InputObject $webclient_obj -Name "DownloadFile" -Value {
                param([string]$url,[string]$destination)
                Write-Host "%#[System.Net.WebClient.DownloadFile] Download from: $($url)"
                Write-Host "%#[System.Net.WebClient.DownloadFile] Save downloaded file to: $($destination)"
                }
            Add-Member -memberType ScriptMethod -InputObject $webclient_obj -Name "DownloadString" -Value {
                param([string]$url)
                Write-Host "%#[System.Net.WebClient.DownloadString] Download from: $($url)"
                }
            return $webclient_obj
        }
        elseif($Obj -eq 'random'){
            $random_obj = [PsCustomObject]
            Add-Member -memberType ScriptMethod -InputObject $random_obj -Name "next" -Value {
                param([int]$min,[int]$max)
                $random_int = Get-Random -Minimum $min -Maximum $max
                Write-Host "%#[System.Random] Generate random integer between $($min) and $($max). Value returned: $($random_int)"
                return $random_int
                }
            return $random_obj
        }
        else{
            Write-Host "Unknown object type found: $($Obj)"
        }
    }
'@

    $override_functions = @()
    $encoded_script = ""

    if ($PSCmdlet.MyInvocation.ExpectingInput) {
        #from pipe
        $encoded_script = $InputObject
    }
    else {
        try {
                #from file
                $encoded_script = Get-Content $InputObject -ErrorAction Stop
            }
        catch {
                throw "Error reading: '$($InputObject)'"
            }
    }

    $override_functions += $Invoke_Expression_Override
    $override_functions += $Invoke_Command_Override
    $override_functions += $Invoke_Item_Override
    $override_functions += $New_Object_Override

    $decoder = ($override_functions -join "`r`n") + "`r`n`r`n" + $encoded_script

    $layers = @()
    $actions = @()
 
    while($layers -notcontains $encoded_script){

        $layers += $encoded_script
        $encoded_script = (powershell $decoder 2> $null)

        if ( $encoded_script.GetType().FullName -eq "System.Object[]"){
           $actions += $encoded_script.split('%#',[System.StringSplitOptions]::RemoveEmptyEntries).Trim()
           Break
        }

        ElseIf ($LastExitCode -ne 0 -Or $encoded_script.StartsWith("Exception")){
            Break
            }

        $decoder = ($override_functions -join "`r`n`r`n") + "`r`n`r`n" + $encoded_script
         }

    for ($i=0; $i -le $layers.length-1; $i++){
        $heading = "`r`n`r`n" + "#"*30 + " Layer " + ($i+1) + " " + "#"*30
        Write-Host $heading
        Write-Host $layers[$i]
        }

    $heading = "`r`n`r`n" + "#"*30 + " Actions " + "#"*30
    Write-Host $heading
    for ($i=0; $i -le $actions.length-1; $i++){
        Write-Host "$($i+1). $($actions[$i])"
        }
            
}