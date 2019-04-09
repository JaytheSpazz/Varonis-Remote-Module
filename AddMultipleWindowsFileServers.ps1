<#
    Updated 2/28/2019

    Bulk adds file servers to the Management Console.
    
    Currently Windows only


    Instructions:
    1. Update the '$filerList' and '$statusList' variables below
        - filerList: csv containing list of filers and associated collector. The 
            collector must be added to the Management Console before running this script
        - statusList: general commit log showing success/failure messages per filer
    2. Run script as Administrator/Elevated account (r-account)
        - Account must already be allowed access to use Varonis by the Management Console
    3. It will prompt for:
        a) Permission to add the Varonis Service account to 
            i.) Administrators Group for Windows 2016 servers 
            ii.)Backup Operators & Power Users Group for all other Windows servers
        b) Varonis Service account credentials for
            i.)Filewalk
            ii.)Agent install
            iii.)SQL host
            iv.)Database
            v.) Collector
    4. View Management Console for filer add status
    5. Management Console add error logs are located in ..\IDU Server\Logs\Deployment

#>
$dateStamp = get-date -Format yyyyMMdd

$filerList = "C:\Varonis\example.csv"
$statusList = "C:\Varonis\BulkAddWindowsFilers\$dateStamp-BulkAddFilersStatusList.txt"
$filerInfo = import-csv $FilerList

# Common variables
$filerType = "windows"
$probeID = "1"
#$skipInstallFwAgent = $true
#$skipInstallEventAgent = $true
$skipInstallFwAgent = $false
$skipInstallEventAgent = $false
$collectLocalAcct = $true

Write-Host -ForegroundColor Yellow "Before installing Varonis Agents on the file server(s), the Varonis Service Account must be added to the correct Groups. Would you like to proceed? [y/n]"
$check=Read-Host 
if($check -eq "y"){
   $filerInfo |ForEach-Object{

        $computername = $_.hostname

        $os=(Get-WmiObject Win32_OperatingSystem -ComputerName $Computername).caption; #gets OS
        if($os -eq "Microsoft Windows Server 2016 Standard"){
            $GroupName = "Administrators";
            $Group = [ADSI]"WinNT://$ComputerName/$GroupName,group"
            $User = [ADSI]"WinNT://$DomainName/$Username,user"
            $access=Invoke-Command $ComputerName -scriptblock{param($GroupName) net localgroup $GroupName } -arg $GroupName | 
            Where-Object {$_ -AND $_ -notmatch "command completed successfully"} | select -skip 4 
            if($access -contains "$DomainName\$Username"){
                Write-Host "$Username exists in $Groupname on $Computername `n" -ForegroundColor Red
            }#service account is already in group
            else{
                Write-Host -ForegroundColor Yellow "Adding $username to $GroupName on $Computername `n"
                $Group.Add($User.Path)
            }#adds service account to group
        }#checks for 2016 OS to apply Admin access to service account
        else{
            $GroupNames = @("Backup Operators","Power Users");
            foreach($GroupName in $GroupNames){
                $Group = [ADSI]"WinNT://$ComputerName/$GroupName,group"
                $User = [ADSI]"WinNT://$DomainName/$Username,user"
                $access=Invoke-Command $ComputerName -scriptblock{param($GroupName) net localgroup $GroupName } -arg $GroupName | 
                Where-Object {$_ -AND $_ -notmatch "command completed successfully"} | select -skip 4 
                if($access -contains "$DomainName\$Username"){
                    Write-Host "$Username exists in $Groupname on $Computername" -ForegroundColor Red
                }#service account is already in group
                else{
                    Write-Host -ForegroundColor Yellow "Adding $username to $GroupName on $Computername"
                    $Group.Add($User.Path)
                }#adds service account to group
            }
            write-host "`n"
        }#for all other Windos OS
    }
}#end of adding service account to permissions/checking permissions

else{
    Write-Host -ForegroundColor Yellow "Exiting operation."
    exit
    
}#end entire script


Connect-Varonis -ServerName #set server idu

# Prompt for credentials
#Write-Host -ForegroundColor Yellow "Enter Varonis Service Account Credentials"

$session = Get-PSSession;
Invoke-Command -Session $session -ScriptBlock { param($statusfile) `
$creds = Get-Credential -message "Enter Varonis Service Account Credentials"
$vrnCred = New-Varoniscredential -Credential $creds -type Windows

# Common variables
$filerType = "windows"
$probeID = "1"
#$skipInstallFwAgent = $true
#$skipInstallEventAgent = $true
$skipInstallFwAgent = $false
$skipInstallEventAgent = $false
$collectLocalAcct = $true


#counter to display progress
$counter = 0
$totalFilers = $Using:filerInfo | Measure-Object | Select-Object -expand count


    #for loop to add the servers in the list.
    $Using:filerInfo | foreach-object {
   
        # clear existing variables at the beginning of each run
        Clear-Variable -ErrorAction SilentlyContinue hostname,
                collectorID,
                collector,
                filer,
                newFilerError,
                addFilerError

        #general variables from csv
        $hostname = $_.hostname
        $collectorID = Get-Collector -name $_.collector
        $collector = $_.collector
    
        $counter++
        echo "[$counter/$totalFilers] - Adding $hostname to $collector"

        # Test machine is up
        if (Test-Connection $hostname -quiet -count 1){
            Write-Host -ForegroundColor Green " - $hostname is up"

            # try adding the server to the MC
        
            # Here we are building out cases (ie..if the filer is windows, do these steps)
            switch ($filerType) 
            { 
                "windows" {                   
                    $filer = New-WindowsFileServer -name $hostname -AddToFilteredUsers $true -FileWalkCredentials $vrnCred -AgentCredentials $vrnCred -ShadowSqlCredential $vrnCred -DBInstallCredential $vrnCred -ProbeID $probeID -collector $collectorID –DiscoverShares TopLevelOnly -ErrorVariable newFilerError
                 
                    if ($newFilerError) {
                        $errorMessage = $newFilerError.Exception.Message -split [environment]::NewLine
                        $errorMessage2 = $errorMessage[1]
                        Write-Host -ForegroundColor Red " - Error adding $hostname"
                        Add-Content -Path $statusfile "$hostname,$collector,$errorMessage2"
                        Write-Host -ForegroundColor Red "$hostname,$collector,$errorMessage2"
                    }
                    else {
                        #Specify we do not want driver to be installed
                        $filer.Config.SkipFileWalkChange = $skipInstallFwAgent
                        $filer.Config.IgnoreDriverChanges = $skipInstallEventAgent
                        $filer.Config.All.CollectLocalAccountsInfo = $collectLocalAcct
                        #possible values:
                        # 1 = unchecked
                        # 32774 - checked 
                        $filer.Config.All.OpenReadEvents = 32774
                        Write-Host " - Adding $hostname to Management Console queue"
                        Add-fileserver $filer -CollectorCredential $vrnCred -AutoFillVolumes -Force -ErrorVariable addFilerError | Out-Null
                    
                        if ($addFilerError) {
                            $errorMessage = $addFilerError.Exception.Message -split [environment]::NewLine
                            $errorMessage2 = $errorMessage[1]
                            Write-Host -ForegroundColor Red " - Error adding $hostname"
                            Add-Content -Path $statusfile "$hostname,$collector,$errorMessage2"
                        }
                        else {
                            Add-Content -Path $statusfile "$hostname,$collector,Success"
                            Write-Host -ForegroundColor Green " - $hostname has been added to Management Console. View it to see its add status."
                        }
                    }#else newfilererror
                }
            }#end of switch
        }
        else {

            Write-Host -ForegroundColor Red " - ERROR: $hostname is down"
            $connectError = "$hostname,$collector,Error: Server down"
            Add-Content -Path $statusfile "$hostname,$collector,Server down"
        }
    }#end of foreach

} -ArgumentList $statusList #end of scriptblock
Disconnect-Varonis
Remove-PSSession -Session $session
