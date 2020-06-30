# Backup-Bitlocker.ps1
#
# Version 1.2
#
# Check whether BitLocker is Enabled and store recovery info in AAD.
#
# Based on https://blogs.technet.microsoft.com/showmewindows/2018/01/18/how-to-enable-bitlocker-and-escrow-the-keys-to-azure-ad-when-using-autopilot-for-standard-users/
#
# Steve Prentice, 2020

[string] $OSDrive = $env:SystemDrive
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$cmdName = "BackupToAAD-BitLockerKeyProtector"

# Transcript for logging/troubleshooting
$stampDate = Get-Date
$bitlockerTempDir = "$env:ProgramData\Intune-PowerShell-Logs"
$scriptName = ([System.IO.Path]::GetFileNameWithoutExtension($(Split-Path $script:MyInvocation.MyCommand.Path -Leaf)))
$logFile = "$env:ProgramData\Intune-PowerShell-Logs\$scriptName-" + $stampDate.ToFileTimeUtc() + ".log"
Start-Transcript -Path $logFile -NoClobber

try {
    # Running as SYSTEM BitLocker module may not implicitly load so check if it's loaded and load it if not
    if (!(Get-Command $cmdName -ErrorAction SilentlyContinue)) {
        Write-Host "Importing BitLocker Module"
        Import-Module -Name "$env:SystemRoot\SysWOW64\WindowsPowerShell\v1.0\Modules\BitLocker" -DisableNameChecking
    }

    Write-Host "START"

    # Evaluate the Volume Status to see what we need to do...
    $bdeProtect = Get-BitLockerVolume $OSDrive | Select-Object -Property VolumeStatus,KeyProtector
    # Account for an uncrypted drive
    if ($bdeProtect.KeyProtector.Count -ge 2) {
            Write-Host "Volume Status is encrypted, with TPM and RecoveryPasswordProtector"

            # Check if we can use BackupToAAD-BitLockerKeyProtector commandlet
            if (Get-Command $cmdName -ErrorAction SilentlyContinue) {
                Write-Host "Saving Key to AAD using BackupToAAD-BitLockerKeyProtector commandlet"
                $AllProtectors = $bdeProtect.KeyProtector
                $RecoveryProtector = ($AllProtectors | where-object { $_.KeyProtectorType -eq "RecoveryPassword" })
                While (($counter++ -lt 6) -and (!$exitWhile)) {
                    # Try 6 times because AAD often returns errors...
                    $Result = BackupToAAD-BitLockerKeyProtector -MountPoint $OSDrive -KeyProtectorId $RecoveryProtector.KeyProtectorID -EA SilentlyContinue
                    if ($Result) { Write-Host "COMMAND BackupToAAD-BitLockerKeyProtector completed!"; $exitWhile = "True" }
                    else { Start-Sleep -Seconds 2 }
                }
            }

            if (!$Result) {
                # BackupToAAD-BitLockerKeyProtector commandlet not available, using other mechanisme
                # Get the AAD Machine Certificate
                $cert = Get-ChildItem Cert:\LocalMachine\My\ | Where-Object { $_.Issuer -match "CN=MS-Organization-Access" }
        
                # Obtain the AAD Device ID from the certificate
                $id = $cert.Subject.Replace("CN=", "")
                $thumb = $cert.Thumbprint
        
                # Get the tenant name from the registry
                $tenant = (Get-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin\JoinInfo\$($thumb)).UserEmail.Split('@')[1]

                # Generate the body to send to AAD containing the recovery information
                Write-Host "COMMAND BackupToAAD-BitLockerKeyProtector failed!"
                Write-Host "Saving key protector to AAD for self-service recovery by manually posting it to:"
                Write-Host "https://enterpriseregistration.windows.net/manage/$tenant/device/$($id)?api-version=1.0"
                
                # Get the BitLocker key information from WMI
                (Get-BitLockerVolume -MountPoint $OSDrive).KeyProtector | Where-Object {$_.KeyProtectorType -eq 'RecoveryPassword'} | ForEach-Object {
                    $key = $_
                    Write-Host "kid : $($key.KeyProtectorId) key: $($key.RecoveryPassword)"
                    $body = "{""key"":""$($key.RecoveryPassword)"",""kid"":""$($key.KeyProtectorId.replace('{','').Replace('}',''))"",""vol"":""OSV""}"

                    # Create the URL to post the data to based on the tenant and device information
                    $url = "https://enterpriseregistration.windows.net/manage/$tenant/device/$($id)?api-version=1.0"

                    # Post the data to the URL and sign it with the AAD Machine Certificate
                    $req = Invoke-WebRequest -Uri $url -Body $body -UseBasicParsing -Method Post -UseDefaultCredentials -Certificate $cert
                    $req.RawContent
                    Write-Host "-- Key save web request sent to AAD - Self-Service Recovery should work"
                }
            }
    }

    Write-Host "END"
}
catch {
    Write-Error "Error while setting up AAD Bitlocker Backup, make sure that you are AAD joined and are running the cmdlet as an admin. Error: $_"
}

Stop-Transcript
