# İndirilecek dosyaların URL'leri
$github2AzureDevopsUrl = "https://github.com/iso-bt/Github_2_Azure-Devops/releases/download/0.0.1/Github_2_AzureDevopsServer.ps1"
$winSchedulerUrl = "https://github.com/iso-bt/Github_2_Azure-Devops/releases/download/0.0.1/win_scheduler.ps1"

# İndirilen dosyaların geçici kaydedileceği yol
$tempDir = "$env:TEMP\Github_2_AzureDevops"
$github2AzureDevopsPath = "$tempDir\Github_2_AzureDevopsServer.ps1"
$winSchedulerPath = "$tempDir\win_scheduler.ps1"

# Hedef dosya yolu
$targetPath = "C:\Github_2_AzureDevopsServer.ps1"

# Geçici klasör oluşturma
if (-Not (Test-Path -Path $tempDir)) {
    New-Item -ItemType Directory -Force -Path $tempDir
}

# Dosyaları indirme
Invoke-WebRequest -Uri $github2AzureDevopsUrl -OutFile $github2AzureDevopsPath
Invoke-WebRequest -Uri $winSchedulerUrl -OutFile $winSchedulerPath

# İndirilen Github_2_AzureDevopsServer.ps1 dosyasını C:\ içerisine taşıma
Move-Item -Path $github2AzureDevopsPath -Destination $targetPath -Force

# win_scheduler.ps1 dosyasını çalıştırma
Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$winSchedulerPath`""

Write-Host "Scripts have been downloaded, moved, and win_scheduler.ps1 has been executed."
