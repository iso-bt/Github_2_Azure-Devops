# Görev adını belirleyin
$taskName = "Github_2_AzureDevopsServer"

# Görev açıklaması
$taskDescription = "Run the Github_2_AzureDevopsServer.ps1 script every 5 minutes"

# PowerShell script yolunu belirleyin
$scriptPath = "C:\Github_2_AzureDevopsServer.ps1"

# Zamanlayıcı görevi oluşturun
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-File `"$scriptPath`""
$trigger = New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Minutes 5) -RepeatIndefinitely -AtStartup
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

# Zamanlayıcı görevi kaydedin
Register-ScheduledTask -TaskName $taskName -Description $taskDescription -Action $action -Trigger $trigger -Settings $settings -Principal $principal

Write-Host "Scheduled task '$taskName' has been created to run every 5 minutes."
