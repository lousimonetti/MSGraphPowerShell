
Import-Module Azure

# This is the ID of your Tenant. You may replace the value with your Tenant Domain
$Global:tenantId = "common"

# You can add or change filters here
$MSGraphURI = "https://graph.microsoft.com/";

# 
#### DO NOT MODIFY BELOW LINES ####
###################################
Function Get-Headers {
    param( $token )

    Return @{
        "Authorization" = ("Bearer {0}" -f $token);
        "Content-Type" = "application/json";
    }
}

#builds the token.
Function Get-AzureAccessToken
{
    $clientId = "1950a258-227b-4e31-a9cf-717495945fc2" # PowerShell clientId
    $redirectUri = "urn:ietf:wg:oauth:2.0:oob"
    $MSGraphURI = "https://graph.microsoft.com"
    
    $authority = "https://login.microsoftonline.com/$($Global:tenantId)"
    $authContext = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext" -ArgumentList $authority
    $authResult = $authContext.AcquireToken($MSGraphURI, $clientId, $redirectUri, "Always")
    $token = $authResult.AccessToken
    return $token;
}

Function Get-AllUsers{
    param(
        # Filter Enabled Users only
        [Parameter(Mandatory=$false,
                   Position=0,
                   ParameterSetName="Graph",
                   ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true,
                   HelpMessage="Filter Enabled Users only")]
        [bool]
        $EnabledOnly
    )

    # only get users whose accounts are currently enabled in Azure AD. 
    if($EnabledOnly) {
        $usersV1 = invoke-restmethod -Method get -Uri "$($MSGraphURI)/v1.0/users?`$filter=accountEnabled eq true" -Headers $headers
        #$usersBeta = invoke-restmethod -Method get -Uri "$($MSGraphURI)/beta/users" -Headers $headers  
    }
    else{
        $usersV1 = invoke-restmethod -Method get -Uri "$($MSGraphURI)/v1.0/users" -Headers $headers
    }

    $allUsers = @();
    $allUsers = $usersV1.value;
    Do{
        $curr = Invoke-RestMethod -Method get -Uri $usersV1.'@odata.nextLink' -Headers $headers
        $allUsers += $curr.value;
        $usersv1 = $curr;            

    }while($usersV1.'@odata.nextLink');
    return $allUsers;
}


Function Get-MyPrivilegedRoles{

    # playing with PIM - will do more later. 

    
    $a = Invoke-RestMethod -Method Get -Uri "$($MSGraphURI)/beta/privilegedRoleAssignments/my" -Headers $headers
    
    $rs= @();
    $rd  =@();
    $a.value | %{ 
        $value = $_;
        $b = Invoke-RestMethod -Method Get -Uri "$($MSGraphURI)/beta/privilegedRoleAssignments/$($value.id)" -Headers $headers
        $C = Invoke-RestMethod -Method Get -Uri "$($MSGraphURI)/beta/privilegedRoleAssignments/$($value.id)/roleInfo" -Headers $headers
        $rs +=$b
        $rd += $c
        
    }

}

function Get-MSGraphRecursion {
    <#
    .SYNOPSIS
    MS Graph Recursive call
    
    .DESCRIPTION
    Uses MS Graph Odata.nextLink when not null, and recursively gets all the items until there is no more nextLink

    .PARAMETER currUri
    The URI for the Graph Call I am making.
    
    .PARAMETER headers
    Authorization Headers for the call
    
    .PARAMETER ref
    Array of Objects being populated throughout the resursion. Start with $Null for a clean array.
    
    .EXAMPLE
    $group = "aad"
    $currURI = "https://graph.microsoft.com/v1.0/groups?`$filter=startsWith(displayName, '$($group)')"
    $curr =  Get-MSGraphRecursion  -headers $headers -ref $global:ref -currUri $currURI
    
    .NOTES
    Louis Simonetti III 
    5-18-2018
    #>
    [CmdletBinding()]
    param (
        # Parameter help description
        [Parameter(Mandatory=$true,
                   ParameterSetName="recursion")]
        [string]
        $currUri,
        [Parameter(Mandatory=$true,
                   ParameterSetName="recursion")]
        [System.Object] 
        $headers,
        $ref
    )
    
    $curr = invoke-restmethod -uri $currURI -headers $headers
    if (![string]::IsNullOrEmpty($curr.'@odata.nextLink')){
        write-host $curr.'@odata.nextLink'
        get-AzureADGroupsGraph -headers $headers -ref $curr.value -currUri $curr.'@odata.nextLink'
    }
    $ref += $curr.value
        
    return $ref;
}

function Get-AzureADGroupsMembershipsGraph {
    [CmdletBinding()]
    param (
        # Specifies a path to one or more locations. Unlike the Path parameter, the value of the LiteralPath parameter is
        # used exactly as it is typed. No characters are interpreted as wildcards. If the path includes escape characters,
        # enclose it in single quotation marks. Single quotation marks tell Windows PowerShell not to interpret any
        # characters as escape sequences.
        [Parameter(Mandatory=$true,
                   Position=0,
                   ParameterSetName="Graph",
                   ValueFromPipelineByPropertyName=$true,
                   HelpMessage="Groups to search for.")]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $Groups,
        # Parameter help description
        [Parameter(Mandatory=$false,
        Position=1,
        ParameterSetName="Graph")]
        $arrayofObjects
    )
    $groupsFound = @();
    
    # Call Microsoft Graph
    # $token = Get-AzureAccessToken;
    # $headers = Get-Headers($token)


    if ($token -eq $null) {
        Write-Output "ERROR: Failed to get an Access Token"
        exit
    }
    foreach($group in $groups){
        $curr = $null;
        $continue = $false;
        #### ----------------------------------------
        # gets the groups (limit 100)
        try{
            $currURI = "https://graph.microsoft.com/v1.0/groups?`$filter=startsWith(displayName, '$($group)')"
            $curr =  Get-MSGraphRecursion  -headers $headers -ref $global:ref -currUri $currURI
            
             #invoke-restmethod -uri $currURI -headers $headers
            $continue =$true;
        }
        catch {
            Write-Host "$group not found"
        }
        ####----------------------------------------
        foreach($g in $curr){
                    
            $guri = "$($MSGraphURI)v1.0/groups/$($g.id)/members"
            Write-Host "$guri"
            Write-host "----------------";
            $members = Get-MSGraphRecursion -currUri $guri -headers $headers -ref $null;
            $groupsFound += [pscustomobject]@{"GroupName"=$g.displayName; "GroupID"=$G.id; "Members"= $members;} 
        }
    }
           
    return $groupsFound;
}

#$users = Get-AllUsers -EnabledOnly $true

# Call Microsoft Graph
$Global:token = Get-AzureAccessToken;
$Global:headers = Get-Headers($token)
$pleasedontbreak =  Get-AzureADGroupsMembershipsGraph -Groups "virtualeus"

if ($token -eq $null) {
    Write-Output "ERROR: Failed to get an Access Token"
    exit
}

function Remove-AzureADGroupMembersGraph{
    param(
        # Array of Members
        [Parameter(Mandatory=$true,
        Position=0,
        ParameterSetName="Groups")]
        [System.Object[]]
        $FutureMembers,
        # Target Group ID
        [Parameter(Mandatory=$true,
        Position=1,
        ParameterSetName="Groups")]
        [string]
        $GroupID
        )
        $logs =@()
    
    $addURI = "https://graph.microsoft.com/v1.0/groups/$($groupId)/members/`$ref"
    $FutureMembers| ForEach-Object{
        $body = [pscustomobject]@{"@odata.id"="https://graph.microsoft.com/v1.0/directoryObjects/$($_.id)"}
        $json = ConvertTo-json  $body
        $logs += Invoke-RestMethod -uri  $adduri -method post -headers   $headers -body $json
        $body = $Null;
    }
    return $logs;
} 


function Add-AzureADGroupMembersGraph{
    param(
        # Array of Members
        [Parameter(Mandatory=$true,
        Position=0,
        ParameterSetName="Groups")]
        [System.Object[]]
        $FutureMembers,
        # Target Group ID
        [Parameter(Mandatory=$true,
        Position=1,
        ParameterSetName="Groups")]
        [string]
        $GroupID
        )
        $logs =@()
    
    $addURI = "https://graph.microsoft.com/v1.0/groups/$($groupId)/members/`$ref"
    $FutureMembers| ForEach-Object{
        $body = [pscustomobject]@{"@odata.id"="https://graph.microsoft.com/v1.0/directoryObjects/$($_.id)"}
        $json = ConvertTo-json  $body
        $logs += Invoke-RestMethod -uri  $adduri -method post -headers   $headers -body $json
        $body = $Null;
    }
    return $logs;
} 

# gets all users from Groups that Match a string
$AllUsersFromGroups =  Get-AzureADGroupsMembershipsGraph -Groups "AAD_"


function Get-FancyHeader {
    [CmdletBinding()]
    param (
        $accesToken,
        $encoding ='gzip, deflate, br',
        $contentType = 'applicaiton/json'
        
    )
    return @{
        'Authorization' = 'Bearer ' + $accesToken;
        'X-Requested-With'= 'XMLHttpRequest';
        'x-ms-client-request-id'= [guid]::NewGuid();
        'x-ms-correlation-id' = [guid]::NewGuid();
        'accept-encoding' = $encoding;
        'content-type' = $contentType
    };
}


Function Grant-OAuth2PermissionsToApp{
    Param(
        [Parameter(Mandatory=$true)]$Username, #global administrator username
        [Parameter(Mandatory=$true)]$Password, #global administrator password
        [Parameter(Mandatory=$true)]$azureAppId #application ID of the azure application you wish to admin-consent to
    )
    $azureAppId = "53679879-5bbf-4a31-9f7f-911e0e49a9a8"
    $secpasswd = ConvertTo-SecureString $Password -AsPlainText -Force
    $mycreds = New-Object System.Management.Automation.PSCredential ($Username, $secpasswd)
    $res = login-azurermaccount -Credential $mycreds
    #-Credential $mycreds
    $context = Get-AzureRmContext
    $tenantId = $context.Tenant.Id
    $refreshToken = $context.TokenCache.ReadItems()[-1].RefreshToken
    $body = "grant_type=refresh_token&resource=74658136-14ec-4630-ad9b-26e160ff0fc6&refresh_token=$($refreshToken)"
    $apiToken = Invoke-RestMethod "https://login.windows.net/$tenantId/oauth2/token" -Method POST -Body $body -ContentType 'application/x-www-form-urlencoded'
    
    $header = @{
    'Authorization' = 'Bearer ' + $apiToken.access_token;
    'X-Requested-With'= 'XMLHttpRequest';
    'x-ms-client-request-id'= [guid]::NewGuid();
    'x-ms-correlation-id' = [guid]::NewGuid()

    }
    $url = "https://main.iam.ad.ext.azure.com/api/RegisteredApplications/$($azureAppId)/Consent?onBehalfOfAll=true"
    invoke-RestMethod –Uri $url –Headers $header –Method POST -ErrorAction Stop
    # Invoke-RestMethod –Uri $url –Headers $header –Method GET -ErrorAction Stop
}


    $clientId = "53679879-5bbf-4a31-9f7f-911e0e49a9a8" # custom app
    [uri]$redirectUri = "urn:ietf:wg:oauth:2.0:oob"
    $MSGraphURI = "https://main.iam.ad.ext.azure.com" # "https://management.core.windows.net/"
    $prompt = [Microsoft.IdentityModel.Clients.ActiveDirectory.PromptBehavior]::Always;
    $authority = "https://login.microsoftonline.com/$($Global:tenantId)"
    $authContext = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext" -ArgumentList $authority
    $authResult = $authContext.AcquireToken($MSGraphURI, $clientId, $redirectUri, $prompt)
    $token = $authResult.AccessToken

    $endpoint = "https://main.iam.ad.ext.azure.com/api/Policies/Policies?top=10&nextLink=null&appId=&includeBaseline=true"

    $test =Invoke-RestMethod -Uri $endpoint -Headers $header

    $metadata = "https://main.iam.ad.ext.azure.com/api/Policies/Policies?top=100&appId=&includeBaseline=true&nextLink=null";
    $test2  =Invoke-RestMethod -Uri $metadata -Headers $header 
    $chooseApps = "https://main.iam.ad.ext.azure.com/api/ChooseApplications/ById"
    
    $header = @{
        'Authorization' = 'Bearer ' + $apiToken.access_token;
        'X-Requested-With'= 'XMLHttpRequest';
        'x-ms-client-request-id'= [guid]::NewGuid();
        'x-ms-correlation-id' = [guid]::NewGuid();
        'accept-encoding' = 'gzip, deflate, br';
        'content-type' = 'application/json'
        
    }
    $exchangePayload = '{"ids":["00000002-0000-0ff1-ce00-000000000000"]}';
    $payload = "{`"ids`":[`"$($appId)`"]}";
    $test3  =Invoke-RestMethod -Uri $chooseApps -Headers $header -Method post -Body $payload 
    