# Example for using Azure AD access reviews in Microsoft Graph
#
# This material is provided "AS-IS" and has no warranty.
# 
# Last updated August 20, 2018
#
# This example is adapted from the documentation example located at 
# https://docs.microsoft.com/en-us/intune/intune-graph-apis
#
#

$user =  Read-Host 'enter your logon name'
$clientid = Read-Host 'enter your client id'
$tenant= Read-host 'enter the tenant name or id'
$Global:redirectUri = Read-host 'enter your redirect URL from the application registration'
#"https://localhost:44316/" #"urn:ietf:wg:oauth:2.0:oob"

function Get-AzureADv2Token {
    [cmdletbinding()]
    Param(
        [Parameter(Mandatory=$true)][string]$User,
    
        [Parameter(Mandatory=$true)][string]$ClientId,
        [Parameter(Mandatory=$true)][string]$Tenant
        
    )

    <# current location #>
    $path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath('.\')
    <# Authentication Bits using MSAL #>
    [System.Reflection.Assembly]::LoadWithPartialName("System.Threading") | Out-Null
    [System.Reflection.Assembly]::LoadWithPartialName("System.Linq") | Out-Null
    [System.Reflection.Assembly]::LoadWithPartialName("System.Net") | Out-Null
    
    $bytes  = [System.IO.File]::ReadAllBytes("$($path)\Microsoft.Identity.Client.dll") 
    [System.Reflection.Assembly]::Load($bytes) | Out-Null
    $bytes  = [System.IO.File]::ReadAllBytes("$($path)\Microsoft.Identity.Core.dll") 
    [System.Reflection.Assembly]::Load($bytes) | Out-Null
    
    $authority = "https://login.microsoftonline.com/$($tenant)"
    
    $redirectUri = $global:redirectUri;
    $resourceAppIdURI = "https://graph.microsoft.com/"
    $authResult = $null;
    try {
        $publicClientApplication  =  [Microsoft.Identity.Client.PublicClientApplication]::new($clientId, $authority);
        $scopes = [activator]::createinstance([System.Collections.Generic.List``1].makegenerictype([System.String]));
        $scopes.Add("AccessReview.ReadWrite.All");
        $scopes.Add("ProgramControl.ReadWrite.All");
    
        # $publicClientApplication.RedirectUri = $reply
        
        $authResult = $publicClientApplication.AcquireTokenAsync($scopes);
        return $authResult
    }
    catch{
        Write-Host $Error
    }

}

function Get-TenantInformation
{
    [cmdletbinding()]
    param(
        # Parameter help description
        [Parameter(Mandatory = $true)]
        [string]
        $userName
    )
    $userUpn = New-Object "System.Net.Mail.MailAddress" -ArgumentList $userName
    return $userUpn.Host 
}
function Get-GraphExampleAuthToken {
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        $User,

        [Parameter(Mandatory = $true)]
        $ClientId,

        [Parameter()]
        $TenantDomain
    )

    $tenant = Get-TenantInformation -userName $user

    if ($TenantDomain -ne $null) {
        $tenant = $TenantDomain
    }

    Write-Verbose "Checking for AzureAD module..."

    $AadModule = Get-Module -Name "AzureAD" -ListAvailable
    if ($AadModule -eq $null) {
        Write-Host "AzureAD PowerShell module not found, looking for AzureADPreview"
        $AadModule = Get-Module -Name "AzureADPreview" -ListAvailable
    }

    if ($AadModule -eq $null) {
        write-host
        write-host "AzureAD Powershell module not installed..." -f Red
        write-host "Install by running 'Install-Module AzureAD' or 'Install-Module AzureADPreview' from an elevated PowerShell prompt" -f Yellow
        write-host "Script can't continue..." -f Red
        write-host
        exit
    }

    # Getting path to ActiveDirectory Assemblies
    # If the module count is greater than 1 find the latest version

    if ($AadModule.count -gt 1) {
        $Latest_Version = ($AadModule | select version | Sort-Object)[-1]
        $aadModule = $AadModule | ? { $_.version -eq $Latest_Version.version }
        $adal = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.dll"
        $adalforms = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.Platform.dll"
    }

    else {
        $adal = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.dll"
        $adalforms = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.Platform.dll"
    }

    [System.Reflection.Assembly]::LoadFrom($adal) | Out-Null
    [System.Reflection.Assembly]::LoadFrom($adalforms) | Out-Null
       
    
    $redirectUri = "https://localhost:44316/" #"urn:ietf:wg:oauth:2.0:oob"
    $resourceAppIdURI = "https://graph.microsoft.com/"

    $authority = "https://login.microsoftonline.com/$Tenant"

    try {
        $authContext = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext" -ArgumentList $authority
        # https://msdn.microsoft.com/library/azure/microsoft.identitymodel.clients.activedirectory.promptbehavior.aspx
        # Change the prompt behaviour to force credentials each time: Auto, Always, Never, RefreshSession
        $platformParameters = [Microsoft.IdentityModel.Clients.ActiveDirectory.PlatformParameters]::new('Auto')

        $userId = [Microsoft.IdentityModel.Clients.ActiveDirectory.UserIdentifier]::new($user, [Microsoft.IdentityModel.Clients.ActiveDirectory.UserIdentifierType]::OptionalDisplayableId)
        # New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.UserIdentifier" -ArgumentList ($User)
        
        $authResult = $authContext.AcquireTokenAsync($resourceAppIdURI, $ClientId, $redirectUri, $platformParameters, $userId) #.Result
        # If the accesstoken is valid then create the authentication header
        if ($authResult.AccessToken) {
            # Creating header for Authorization token
            $authHeader = @{
                'Content-Type' = 'application/json'
                'Authorization' = "Bearer " + $authResult.AccessToken
                'ExpiresOn' = $authResult.ExpiresOn
            }
            return $authHeader
        }
        else {
            Write-Host
            Write-Host "Authorization Access Token is null, please re-run authentication..." -ForegroundColor Red
            Write-Host
            break
        }
    }
    catch {
        write-host $_.Exception.Message -f Red
        write-host $_.Exception.ItemName -f Red
        write-host
        break
    }   
}

# start of access review specific example

function Get-GraphExampleProgramControls($authHeaders,$programId)
{
    $uri1 = "https://graph.microsoft.com/beta/programs('" + $programId + "')/controls"
    Write-Host "GET $uri1"

    $resp1 = Invoke-RestMethod -UseBasicParsing -headers $authHeaders -Uri $uri1 -Method Get
    #$val1 = $resp1
    $val1 = $resp1;
   
    foreach ($c in $val1.Value) {
        $cid = $c.controlId
        $displayname = '"' + $c.displayName + '"'
        Write-Host "control $cid $displayname"
    }

}

function Get-GraphExamplePrograms($authHeaders) {
    $uri1 = "https://graph.microsoft.com/beta/programs"
    Write-Host "GET $uri1"

    $resp1 = Invoke-RestMethod -UseBasicParsing -headers $authHeaders -Uri $uri1 -Method Get
    # $val1 = $resp1
    $val1 = $resp1

   
    foreach ($program in $val1.Value) {
        $id = $program.id
        $displayname = '"' + $program.displayName + '"'
        Write-Host "program $id $displayName"

        Get-GraphExampleProgramControls $authHeaders $id
        Write-Host ""
    }

}

function Get-GraphExampleAccessReviewDecisions($authHeaders,$arid)
{
    $uri1 = 'https://graph.microsoft.com/beta/accessReviews(' + "'" + $arid  + "')/decisions"
    Write-Host "GET $uri1"
    $resp1 = Invoke-RestMethod -UseBasicParsing -headers $authHeaders -Uri $uri1 -Method Get
    $val1 = $resp1

    foreach ($ard in $val1.Value) {
        $rr = $ard.reviewResult
        $upn = $ard.userPrincipalName

        Write-Host "access review decision $upn $rr"
    }
    Write-Host ""
}

function Get-GraphExampleAccessReviewInstances($authHeaders,$arid)
{
    $uri1 = 'https://graph.microsoft.com/beta/accessReviews(' + "'" + $arid  + "')/instances"
    Write-Host "GET $uri1"
    $resp1 = Invoke-RestMethod -UseBasicParsing -headers $authHeaders -Uri $uri1 -Method Get
    $val1 = $resp1

    foreach ($ard in $val1.Value) {
        $iid = $ard.id
        $start = $ard.startDateTime
        $end = $ard.endDateTime
        $status = $ard.status

        Write-Host "access review instance $start $end $status"
        if ($status -ne "NotStarted") {
            Get-GraphExampleAccessReviewDecisions $authHeaders $iid
        }
    }
    Write-Host ""
}


function Get-GraphExampleAccessReviews($authHeaders,$bftid)
{
    $uri1 = "https://graph.microsoft.com/beta/accessReviews?`$filter=businessFlowTemplateId eq '$($bftid)'";
    Write-Host "GET $uri1"
    $resp1 = Invoke-RestMethod -UseBasicParsing -headers $authHeaders -Uri $uri1 -Method Get
    $val1 = $resp1

    foreach ($ar in $val1.Value) {
        $id = $ar.id
        $displayname = '"' + $ar.displayName + '"'
        $startDateTime = $ar.startDateTime
        $status = $ar.status

        Write-Host "access review $id $displayName $startDateTime $status"

        Get-GraphExampleAccessReviewDecisions $authHeaders $id

        Get-GraphExampleAccessReviewInstances $authHeaders $id
    }

}

function Get-GraphExampleBusinessFlowTemplates($authHeaders) {
    $uri1 = "https://graph.microsoft.com/beta/businessFlowTemplates"
    Write-Host "GET $uri1"
    $resp1 = Invoke-RestMethod -UseBasicParsing -headers $authHeaders -Uri $uri1 -Method Get
    $val1 = $resp1

    foreach ($bft in $val1.Value) {
        $id = $bft.id
        Write-Host "business flow template $id"

        Get-GraphExampleAccessReviews $authHeaders $id
        Write-Host ""

    }
}

#Region Authentication
$path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath('.\')

# If the MSAL libraries are present, use the V2 endpoint for the Access token
if((test-path "$($path)\Microsoft.Identity.client.dll") -and (test-path "$($path)\Microsoft.Identity.Core.dll"))
{
    $authResult = Get-AzureADv2Token -User $user -ClientId $clientid -Tenant $tenant
    $token = $authResult.Result.AccessToken;

}
# Else use the V1 endpoint for the Access Token
else{
    
    $authHeaders = Get-GraphExampleAuthToken -User $User -ClientId $ClientId
}
$authHeaders = @{
    "authorization"="Bearer $($token)"; #$authResult.Result.AccessToken)"; 
}
#endregion

#region run commands
 Get-GraphExamplePrograms $authHeaders
 Get-GraphExampleBusinessFlowTemplates $authHeaders
#endregion  