<# Authentication Bits using MSAL #>
[System.Reflection.Assembly]::LoadWithPartialName("System.Threading") | out-null
[System.Reflection.Assembly]::LoadWithPartialName("System.Linq") | out-null
[System.Reflection.Assembly]::LoadWithPartialName("System.Net") | out-null

$bytes  = [System.IO.File]::ReadAllBytes("C:\dev\MSGraphPowerShell\AccessReviews\Microsoft.Identity.Client.dll") 
[System.Reflection.Assembly]::Load($bytes) | out-null
$bytes  = [System.IO.File]::ReadAllBytes("C:\dev\MSGraphPowerShell\AccessReviews\Microsoft.Identity.Core.dll") 
[System.Reflection.Assembly]::Load($bytes) | out-null

$Global:ClientId = '15da4e6d-6246-4bcb-b7eb-35111a7bac1f';
$global:msalCache = $Null

function Get-MsalToken
{
    param(
        [Parameter(Mandatory=$true)][string]$User,
        [Paramater(Mandatory=$true)][string[]]$scopes
    )
    
    
    $authority = "https://login.microsoftonline.com/bsnconnect.onmicrosoft.com"
    
    $redirectUri = "https://localhost:44316/" #"urn:ietf:wg:oauth:2.0:oob"
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
    # }
    $global:maslcache = $authResult.Result;
    return $authResult.Result.AccessToken
}

$token = Get-MsalToken -user  'lsimonetti@dow.com' -scopes @("AccessReviewReadWrite.All". "ProgramControl.Readwrite.All")
$authHeaders = @{
    "authorization"="Bearer $($token)"; #$authResult.Result.AccessToken)"; 
}

$uri1 = "https://graph.microsoft.com/beta/programs"
Write-Host "GET $uri1"

$resp1 = Invoke-RestMethod -UseBasicParsing -headers $authHeaders -Uri $uri1 -Method Get
# $val1 = $resp1
$val1 = $resp1
