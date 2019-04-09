function Connect-Varonis{
        <#
            .SYNOPSIS

            Imports the Varonis Management Module from the Varonis IDU and connects to the IDU
 

            .DESCRIPTION

            Creates a PowerShell Session with the Varonis IDU and then Imports the Varonis Management Module
            into the current PowerShell session for the cmdlets to be used while being connected to the IDU 
 

            .EXAMPLE

            Connect-Varonis -ServerName VaronisIDU
    #>

    PARAM(
        [parameter(Mandatory=$True,ParameterSetName="ServerName",Position=0)]
        [ValidateSet('','','')] #This will need to be set with the servers for the IDU
           [STRING]$ServerName
       )

       $session = New-PSSession -ComputerName $ServerName;
       Import-Module (Import-PSSession -Session $session -Module VaronisManagement -AllowClobber) -Prefix "Varonis" -Global

        Set-Alias -Name 'Disconnect-Varonis' -Value 'Disconnect-RDPVaronis' -Scope Global
        Set-Alias -Name 'Disable-VaronisJob' -Value 'Disable-RDPVaronisJob' -Scope Global
        Set-Alias -Name 'Get-VaronisJobState' -Value 'Get-RDPVaronisJobState' -Scope Global
        Set-Alias -Name 'Get-VaronisJob' -Value 'Get-RDPVaronisJob' -Scope Global
        Set-Alias -Name 'Enable-VaronisJob' -Value 'Enable-RDPVaronisJob' -Scope Global
        Set-Alias -Name 'Test-VaronisJobCompleted' -Value 'Test-RDPIsVaronisJobCompleted' -Scope Global
        Set-Alias -Name 'Test-VaronisJobRunning' -Value 'Test-RDPIsVaronisJobRunning' -Scope Global
        Set-Alias -Name 'Test-VaronisJobSuccessful' -Value 'Test-RDPIsVaronisJobSuccessful' -Scope Global
      
       $creds = Get-Credential -message "Credentials are required for access to the Varonis servers. Please enter your credentials that have the necessary rights."
       $vcreds = New-Varoniscredential -Credential $creds | Out-Null #
       Connect-VaronisIDU -Server $ServerName -UserCredential $vcreds
}

function Disconnect-RDPVaronis{
    <#
        .SYNOPSIS

        Disconnects from the Varonis IDU

        .DESCRIPTION

        Disconnects from the Varonis IDU and also closes out the remote session it had on the
        IDU. The temporary Varonis module file is also removed.

        .EXAMPLE

        Disconnect-Varonis
#>
        $session = Get-PSSession 
        Invoke-Command -Session $session -ScriptBlock {Disconnect-Idu} #end of scriptblock
        Remove-PSSession -Session $session           
}

function Disable-RDPVaronisJob{
    <#
            .SYNOPSIS

            Disables a job for a given Job ID (Guid) or Name.
 
            .DESCRIPTION

            Disables a job for a given Job Name or Job ID (Guid). You can retrieve the ID with the Get-JobID command. 
 
            .EXAMPLE

            $jid = Get-JobID -Name ADWalk; Disable-Job -ID $jid


            Disables ADWalk job using its Job ID.


            .EXAMPLE

            Disable-Job -Name ADWalk


            Disables ADWalk job by name.

    #>

    [CmdletBinding(SupportsShouldProcess=$False,
    ConfirmImpact='Low')]

    PARAM(
     [parameter(Mandatory=$True,ParameterSetName="Name",Position=0)]
        [STRING]$Name,
     [parameter(Mandatory=$True,ParameterSetName="ID",Position=0)]
        [GUID]$ID
    )
    $session = Get-PSSession

    if (!$name){
        Invoke-Command -Session $session -ScriptBlock {Disable-Job -ID $Using:ID}
    }#end of if

    elseif(!$id){
        Invoke-Command -Session $session -ScriptBlock {$jid=get-jobid -name $Using:Name; Disable-Job -ID $jid} #end of scriptblock
    }
    
}

function Get-VaronisHealthCheck{
    CLEAR-HOST
    #
    #
    #
    #
    
    $session = Get-PSSession
    
    if($session.Name -ne "Varonis"){
        Connect-Varonis    
    }
    
    $Probes = Get-VaronisProbe;
    $shares = Get-VaronisFileserver;
    $DB = "Varonis"
    $Collectors = Get-VaronisCollector;
    
    
    foreach ($Probe in $Probes){
        $vrnsProbe = $Probe.ServerName
        Write-Host "`n$vrnsProbe"; Write-Host "----------"
        if (Test-Connection -Count 1  -computername $vrnsProbe -Verbose){
           $services = Get-Service -ComputerName $vrnsProbe -DisplayName Varonis*
           Write-Host "Online" -ForegroundColor Green
           foreach ($service in $services){
            if ($service.status -ne 'Running'){
               Write-Host $Service.DisplayName'is not running on'$vrnsProbe -ForegroundColor Yellow
               $count++;
            }#end of status check
           }#end of foreach
           if($count -eq 0){
             Write-Host "All Varonis Services are running" -ForegroundColor Green
           }
        }
        else{
             Write-Warning -Message "$vrnsProbe not online"
        }
    }
    
    Foreach ($Collector in $Collectors){
       $col = $Collector.servername
        Write-Host "`n$Col";
        if (Test-Connection -Count 1  -computername $Col -Verbose){
            Write-Host "Online" -ForegroundColor Green
            $services = Get-Service -ComputerName $Col -DisplayName Varonis*
            $count=0;
            foreach ($service in $services){
                if ($service.status -ne 'Running'){
                    Write-Host $Service.DisplayName'is not running on'$Col -ForegroundColor Yellow
                    $count++;
                }#end of status check
            }#end of foreach
            if($count -eq 0){
                Write-Host "All Varonis Services are running" -ForegroundColor Green
            }
            Write-Host "------------------"
            $filers = $shares | Where-Object {$_.collectorname -match $col -and $_.IsDecommissioned -eq $false}
            foreach ($filer in $filers){
                $fileshare = $filer.servername
                Write-Host "Checking $fileshare"
                if(Test-Connection -Count 1 -ComputerName $fileshare){
                    Write-Host "$fileshare is online" -ForegroundColor Green
                   if($filer.FilerType -eq "SharePoint"){
                    Write-Host "This is a SharePoint site so there are no services to check." -ForegroundColor Yellow
                   }
                   else{
                        $services = Get-Service -ComputerName $fileshare -DisplayName Varonis*
                        $counts=0;
                        foreach ($service in $services){
                            if ($service.status -ne 'Running'){
                                Write-Host $Service.DisplayName'is not running on'$fileshare -ForegroundColor Yellow
                                $counts++;
                            }#end of status check
                        }#end of foreach
                        if($counts -eq 0){
                            Write-Host "All Varonis Services are running" -ForegroundColor Green
                        }
                   }#end of else if share is a windows server
                }
                else{
                    Write-Warning -Message "$fileshare not online"
                }
            }
        }
        else{
         Write-Warning -Message "$Col not online"
         Write-Host "------------------"
        }
    }
    
    $cred = Get-Credential -Message "Enter Credentials to be used to test connection with the Varonis SQL Database(s)."
    foreach ($Probe in $Probes){
        $vrnsDB = $Probe.DatabaseHost
        Write-Host "`n$vrnsDB";Write-Host "----------"
        if (Test-Connection -Count 1 -computername $vrnsDB -Verbose){
           Write-Host "$vrnsDB is online" -ForegroundColor Green
           $datasource = Get-VaronisSqlDataSource -AdminCredentials (New-VaronisVaronisCredential -credential $cred) -MachineName $vrnsDB
           $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
           $SqlConnection.ConnectionString = "Server = $datasource; Database = $DB; Integrated Security = True;"
           try {
                $connectionTime = measure-command {$SqlConnection.Open()}
                $Result = @{
                    Connection = "Successful"
                    }
            }
            # exceptions will be raised if the database connection failed.
            catch {
                    $Result = @{
                    Connection = "Failed"
                    }
            }
            Finally{
                # close the database connection
                $SqlConnection.Close()
                #return the results as an object
                $outputObject = New-Object -Property $Result -TypeName psobject
                write-output $outputObject 
            }
        }
        else{
             Write-Warning -Message "$vrnsDB not online"
        }
    }
   # Disconnect-Varonis

}

function Get-RDPVaronisJob{
    <#
            .SYNOPSIS

             Retrieves job prototype structure and the last job execution parameters.
 

            .DESCRIPTION

            Retrieves job prototype structure and the last job execution parameters for a given job (name).
 

            .EXAMPLE

            Get-VaronisJob -name ADWalk


            Retrieves Job(JobPrototype) and the last job execution (JobExecution) for ADWalk

    #>

    [CmdletBinding(SupportsShouldProcess=$False,
    ConfirmImpact='Low')]

     PARAM(
     [parameter(Mandatory=$True,ParameterSetName="Name",Position=0)][SupportsWildcards()]
        [STRING]$Name,
     [parameter(Mandatory=$True,ParameterSetName="ID",Position=0)]
        [GUID]$ID,
    [ValidateSet('Deployment',"Advanced Maintenance",'Data-Driven Subscription','Data Transport Engine','DataPrivilege','Maintenance',
    'DatAlerts','Synchronization','DCF and DW Advanced Maintenance','DCF and DW Maintenance','Automation Engine Advanced',
    'DataPrivelege Entitlement Review','DatAlerts Analytics')]
        [parameter(Mandatory=$True,ParameterSetName="Ty",Position=0)]
        [STRING]$Type
    )

    $session = Get-PSSession -Name "Varonis"; 
   
    Invoke-Command -Session $session -ScriptBlock {connect-idu | Out-Null}
   
    if(!$id -and !$type -and ($name -eq '*')){
        Invoke-Command -Session $session -ScriptBlock {get-varonisjob -name $Using:name}
    }
    elseif(!$id -and !$type -and $name){
        Invoke-Command -Session $session -ScriptBlock {get-varonisjob -name $Using:name} -HideComputerName|select * -exclude RunspaceID
    }

    elseif($id -and !$name -and !$type){
        Invoke-Command -Session $session -ScriptBlock {get-varonisjob -id $Using:id} -HideComputerName|select * -exclude RunspaceID
    }
    elseif(!(!$type)){
        $alljobs = Invoke-Command -Session $session -ScriptBlock {get-varonisjob -name *}
        $info = $alljobs | select description, ExecutingComponentTypeID
        switch ($Type){
            'Deployment' {$cid = 530}
            'Advanced Maintenance' {$cid = 511,512,513,514,515,516,518,519,521,522}
            'Data-Driven Subscription'{$cid = 529}
            'Data Transport Engine'{$cid= 520}
            'DataPrivilege'{$cid= 550}
            'Maintenance'{$cid = 4,10,510,517,551}
            'DatAlerts'{$cid= 532}
            'Synchronization'{$cid= 540}
            'DCF and DW Advanced Maintenance'{$cid = 560,561,563,565}
            'DCF and DW Maintenance'{$cid= 562,564}
            'Automation Engine Advanced'{$cid= 580}
            'DataPrivelege Entitlement Review'{$cid = 575}
            'DatAlerts Analytics'{$cid = 585}
        }#end of switch
        $Jobs=@();
        for($i=0; $i -lt $info.Count;$i++){
            for($x=0;$x -lt $cid.count;$x++ ){
                if($info[$i].ExecutingComponentTypeID -eq $cid[$x]){
                    $Jobs += $alljobs[$i]
                }
            }#end of for    
        }#end of for
        return $Jobs
    }

}

function Get-RDPVaronisJobState{
    <#
            .SYNOPSIS

             Provides an interface for querying database jobs' state

            .DESCRIPTION


            .EXAMPLE
           
            $jid = Get-JobId -Name 'Pull AD'
            Get-VaronisJobState -PrototypeID $jid

            .EXAMPLE
            Get-VaronisJobState -Name ADWalk
         
#>

    [CmdletBinding(SupportsShouldProcess=$False,
    ConfirmImpact='Low')]

    PARAM(
     [parameter(Mandatory=$True,ParameterSetName="PID",Position=0)]
        [GUID]$PrototypeID,
     [parameter(Mandatory=$True,ParameterSetName="CID",Position=0)]
        [GUID]$CommandID,
     [parameter(Mandatory=$True,ParameterSetName="JN",Position=0)]
        [String]$Name
    )
     
    $session = Get-PSSession

    if($PrototypeID -and !($CommandID) -and !($Name)){
        Invoke-Command -Session $session -ScriptBlock {Get-JobState -PrototypeID $Using:PrototypeID} #end of scriptblock
    }
    elseif($CommandID -and !($PrototypeID) -and !($Name)){
         Invoke-Command -Session $session -ScriptBlock {Get-JobState -CommandID $Using:CommandID} #end of scriptblock
    }
    elseif($Name -and !($PrototypeID) -and !($CommandID)){
         Invoke-Command -Session $session -ScriptBlock {$jid=Get-JobID -name $Using:Name;Get-JobState -PrototypeID $jid} -HideComputerName| select * -exclude RunspaceID #end of scriptblock
    }
}

function Enable-RDPVaronisJob{
    <#
            .SYNOPSIS

            Enables a job for a given Job ID (Guid) or Name.
 

            .DESCRIPTION

            Enables a job for a given Job Name or Job ID (Guid). You can retrieve the ID with the Get-JobID command. 
 

            .EXAMPLE

            $jid = Get-JobID -Name ADWalk; Enable-Job -ID $jid


            Enables ADWalk job using its Job ID.


            .EXAMPLE

            Enable-Job -Name ADWalk


            Enables ADWalk job by name.

    #>

    [CmdletBinding(SupportsShouldProcess=$False,
    ConfirmImpact='Low')]

    PARAM(
     [parameter(Mandatory=$True,ParameterSetName="Name",Position=0)]
        [STRING]$Name,
     [parameter(Mandatory=$True,ParameterSetName="ID",Position=0)]
        [GUID]$ID
    )
    
    $session = Get-PSSession 
   
    if (!$name){
        Invoke-Command -Session $session -ScriptBlock {Enable-Job -ID $Using:ID}
    }#end of if

    elseif(!$id){
        Invoke-Command -Session $session -ScriptBlock {$jid=get-jobid -name $Using:Name; Enable-Job -ID $jid} #end of scriptblock
    }
    
}
function Start-VaronisService{
    [CmdletBinding(SupportsShouldProcess=$False,
   ConfirmImpact='Low')]

   PARAM(
    [parameter(Mandatory=$True,ParameterSetName="Serv",Position=0)]
       [STRING]$Computer,
    [parameter(Mandatory=$True,ParameterSetName="Serv",Position=1)]
        [STRING]$ServiceName
   )

   $service = Get-Service -ComputerName $Computer -DisplayName $ServiceName
   if($service.Status -eq 'Running'){
        Write-Host "Service $ServiceName is already running" -ForegroundColor Yellow
    }
    else{
        Write-Host "Starting $ServiceName" -ForegroundColor Yellow
        $service | Set-Service -Status Running
    }
}

function Stop-VaronisService{
    [CmdletBinding(SupportsShouldProcess=$False,
   ConfirmImpact='Low')]

   PARAM(
    [parameter(Mandatory=$True,ParameterSetName="Serv",Position=0)]
       [STRING]$Computer,
    [parameter(Mandatory=$True,ParameterSetName="Serv",Position=1)]
        [STRING]$ServiceName
   )

   $service = Get-Service -ComputerName $Computer -DisplayName $ServiceName
   if($service.Status -eq 'Stopped'){
        Write-Host "Service $ServiceName already is not running" -ForegroundColor Yellow
    }
    else{
        Write-Host "Stopping $ServiceName" -ForegroundColor Yellow
        $service | Set-Service -Status Stopped
    }
}

function Test-RDPIsVaronisJobCompleted{
    <#
            .SYNOPSIS

            Tests whether the job has been completed.
 

            .DESCRIPTION

            Tests whether the job has been completed by using a deployment job execution command like add-fileserver.
 

            .EXAMPLE

            $jid = Get-JobID -Name ADWalk; $jid = Start-Job -ID $jid; Test-JobCompleted -ID $jid


            Uses the ID to check whether the job has been completed.


            .EXAMPLE

            Test-JobCompleted -Name ADWalk


            Uses the job Name to check whether the job has been completed.

#>

    [CmdletBinding(SupportsShouldProcess=$False,
    ConfirmImpact='Low')]

    PARAM(
     [parameter(Mandatory=$True,ParameterSetName="Name",Position=0)]
        [STRING]$Name,
     [parameter(Mandatory=$True,ParameterSetName="ID",Position=0)]
        [GUID]$ID
    )
    
    $session = Get-Pssession
    if (!$name){
       Invoke-Command -Session $session -Scriptblock {Test-JobCompleted -PrototypeID $Using:ID}
    }#end of if

    elseif(!$id){
        Invoke-Command -Session $session -Scriptblock {$jid=get-jobid -name $Using:Name; Test-JobCompleted -PrototypeID $jid}
    }
}

function Test-RDPIsVaronisJobRunning{
    <#
            .SYNOPSIS

            Tests whether the job is running.
 

            .DESCRIPTION

            Tests whether the job is runng by using a deployment job execution command like add-fileserver.
 

            .EXAMPLE

            $jid = Get-VaronisJobID -Name ADWalk; Test-IsVaronisJobRunning -ID $jid


            Uses the ID to check whether the job is running.


            .EXAMPLE

            Test-IsVaronisJobRunning -Name ADWalk


            Uses the job Name to check whether the job is running.

#>

    [CmdletBinding(SupportsShouldProcess=$False,
    ConfirmImpact='Low')]

    PARAM(
     [parameter(Mandatory=$True,ParameterSetName="Name",Position=0)]
        [STRING]$Name,
     [parameter(Mandatory=$True,ParameterSetName="ID",Position=0)]
        [GUID]$ID
    )
     
    $session = Get-Pssession;

    if (!$name){
        Invoke-Command -Session $session -ScriptBlock {Test-JobRunning -ID $Using:ID}
    }#end of if

    elseif(!$id){
        Invoke-Command -Session $session -ScriptBlock {Test-JobRunning -Name $Using:name} #end of scriptblock
    }
    
}

function Test-RDPIsVaronisJobSuccessful{
    <#
            .SYNOPSIS

            Tests whether a job was successful.
 

            .DESCRIPTION

            Tests whether the job was successful by using a deployment job execution command like add-fileserver.
 

            .EXAMPLE

            $jid = Get-VaronisJobID -Name ADWalk; Test-IsVaronisJobSuccessful -ID $jid


            Uses the ID to check whether the job was successful.


            .EXAMPLE

            Test-IsVaronisJobSuccessful -Name ADWalk


            Uses the job Name to check whether the job was successful.

#>

    [CmdletBinding(SupportsShouldProcess=$False,
    ConfirmImpact='Low')]

    PARAM(
     [parameter(Mandatory=$True,ParameterSetName="Name",Position=0)]
        [STRING]$Name,
     [parameter(Mandatory=$True,ParameterSetName="ID",Position=0)]
        [GUID]$ID
    )
     
    $session = Get-PSSession 
    
    if (!$name){
        Invoke-Command -Session $session -ScriptBlock {Test-JobSuccessful -PrototypeID $Using:ID}
    }#end of if

    elseif(!$id){
        Invoke-Command -Session $session -ScriptBlock {$jid=get-jobid -name $Using:Name; Test-JobSuccessful -PrototypeID $jid} #end of scriptblock
    }
 
}


function Test-VaronisServices{
    [CmdletBinding(SupportsShouldProcess=$False,
   ConfirmImpact='Low')]

   PARAM(
    [parameter(Mandatory=$True,ParameterSetName="Name",Position=0)]
       [STRING]$Computer
   )

   $services = Get-Service -ComputerName $Computer -DisplayName Varonis*
   foreach ($service in $services){
       if ($service.status -ne 'Running'){
           Write-Host $Service.DisplayName'is not running' -ForegroundColor Yellow               
       }#end of status check
       else{
            Write-Host $Service.DisplayName'is running' -ForegroundColor Green      
       }
   }#end of foreach
          
}
