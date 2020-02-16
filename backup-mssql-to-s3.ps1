##############################################
###   SQL BacPac Export script to S3       ###
##############################################
# Author: Doug Rathbone (dougrathbone.com)   
#                                            
# Pre-requisites:                           
# * AWS PowerShell Module ("Install-Module AWSPowerShell")
# * SQL Package from https://docs.microsoft.com/en-gb/sql/tools/sqlpackage-download?view=sql-server-ver15
# * An instance profile assigned to the executing host with write access to the S3 bucket
#

Import-Module AWSPowerShell

#####################
#   Configuration   #
#####################
$backupFileNamePrefix = "dbbackup"
$s3BucketName = "my-bucket-name"

$sqlDbName = "my-db-name"
$sqlServerHost = "" #if left empty this will be localhost
$sqlServerInstanceName = "" #if left empty this will be MSSQLSERVER
$sqlServerUsername = "" #not required for local backups
$sqlServerPassword = "" #not required for local backups

$backupTempDirectory = "C:\temp"

#####################

#define backup filename
$dateTimeString = Get-Date -Format "yyyyMMddHHmm"
$backupFileName = "$($backupFileNamePrefix)_$dateTimeString.bacpac"
$backupFilePath = "$backupTempDirectory\$backupFileName"
$sqlPackagePath = "C:\Program Files\Microsoft SQL Server\150\DAC\bin\sqlpackage.exe"

#backup database
Write-Output "Backing up database $sqlDbName"
if ($sqlServerHost.Length -eq 0){
    $sqlPackageCommand = ". `"$sqlPackagePath`" /a:Export /ssn:127.0.0.1 /sdn:$sqlDbName /tf:$backupFilePath"
    Invoke-Expression -Command $sqlPackageCommand
} else {
    #create SQL credential
    $dbPassword = ConvertTo-SecureString $sqlServerPassword -AsPlainText -Force
    $dbCredential = New-Object System.Management.Automation.PSCredential($sqlServerUsername, $dbPassword)

    #define sql connection instance
    $sqlInstanceConnection = "$sqlServerHost\$sqlServerInstanceName"
    if ($sqlServerInstanceName.Length -eq 0){ $sqlInstanceConnection = $sqlServerHost }

    #connect and backup sql
    Backup-SqlDatabase -ServerInstance $sqlInstanceConnection -Database $sqlDbName -Credential $dbCredential -BackupFile $backupFilePath
}


#Fetch instance profile credentials from the meta data service
$MetadataUri = "http://169.254.169.254/latest/meta-data/iam/security-credentials"
$CredentialsList = (Invoke-WebRequest -uri $MetadataUri -UseBasicParsing).Content.Split()
$CredentialsObject = (Invoke-WebRequest -uri "$MetadataUri/$($CredentialsList[0])" -UseBasicParsing).Content | ConvertFrom-Json
 
#Create a local aws cli profile with the returned credentials
Set-AWSCredential `
    -StoreAs InstanceProfile `
    -AccessKey $CredentialsObject.AccessKeyId `
    -SecretKey $CredentialsObject.SecretAccessKey `
    -SessionToken $CredentialsObject.Token
Try{
    #copy dababase file to S3
    Write-Output "Copying backup to S3"
    Write-S3Object -BucketName $s3BucketName -Key $backupFileName -File $backupFilePath -ProfileName InstanceProfile
}
Catch{
    Write-Output "Failed to upload backup"
    Exit
}

Write-Output "Deleting local backup file, as upload was successful"
Remove-Item $backupFilePath
