# Find Intune CurrentEnrollmentId and remove enrollment if one exists...
Try { $enrollment = Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Logger CurrentEnrollmentId -ErrorAction Stop }
Catch {}

If ($enrollment) {
  $enrollmentId = $enrollment.CurrentEnrollmentId

  # Get Tasks and delete...
  $scheduleObject = New-Object -ComObject Schedule.Service
  $scheduleObject.Connect()
  $TaskFolder = $scheduleObject.GetFolder("\Microsoft\Windows\EnterpriseMgmt\"+$enrollmentId)
  $Tasks = $TaskFolder.GetTasks(1)
  ForEach($Task in $Tasks){ $TaskFolder.DeleteTask($Task.Name,0) }
  $rootFolder = $scheduleObject.GetFolder("\Microsoft\Windows\EnterpriseMgmt")
  $rootFolder.DeleteFolder($enrollmentId,0)

  # Remove old registry keys...
  Remove-Item HKLM:\SOFTWARE\Microsoft\Enrollments\$enrollmentId -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item HKLM:\SOFTWARE\Microsoft\Enrollments\Status\$enrollmentId -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item HKLM:\SOFTWARE\Microsoft\EnterpriseResourceManager\Tracked\$enrollmentId -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item HKLM:\SOFTWARE\Microsoft\PolicyManager\AdmxInstalled\$enrollmentId -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item HKLM:\SOFTWARE\Microsoft\PolicyManager\Providers\$enrollmentId -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Accounts\$enrollmentId -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Logger\$enrollmentId -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Sessions\$enrollmentId -Recurse -Force -ErrorAction SilentlyContinue
  Remove-ItemProperty HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Logger\ -Name CurrentEnrollmentId -Force -ErrorAction SilentlyContinue

  # Remove old and new style Intune certificates...
  $certNew = Get-ChildItem Cert:\LocalMachine\My\ | Where-Object { $_.Issuer -Match "CN=Microsoft Intune MDM Device CA" }
  $certOld = Get-ChildItem Cert:\LocalMachine\My\ | Where-Object { $_.Issuer -Match "CN=SC_Online_Issuing" }
  If ($certNew) { $certNew | Remove-Item -Force -ErrorAction SilentlyContinue }
  If ($certOld) { $certOld | Remove-Item -Force -ErrorAction SilentlyContinue }
}
