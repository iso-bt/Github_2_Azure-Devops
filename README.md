
# Github 2 Azure Devops Server

Bu proje, github depolarını Azure Devops Sunucusuna yedeklemek için otomasyon işlemlerini gerçekleştirmek üzere oluşturuldu.

## Otomasyon

Aşağıda yer alan kod ile tüm işlemleri otomatik yapılmasını sağlayabilirsiniz.

Otomasyon script'ine buradan erişebilirsibiz: [Otomasyon Linki](https://github.com/iso-bt/Github_2_Azure-Devops/releases/download/0.0.1/automation.ps1).

Bu script'i admin yetkisi ile açarak çalıştırmanız yeterli olacaktır.

Kod:

```
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
```

## Yapılması gerekenler

Otomasyon haricinde kodları kendiniz çalıştırmak isterseniz. Release kısmından kodları indirebilirsiniz.

- [Otomasyon Script](https://github.com/iso-bt/Github_2_Azure-Devops/releases/download/0.0.1/automation.ps1)
- [Zamanlayızı Script](https://github.com/iso-bt/Github_2_Azure-Devops/releases/download/0.0.1/win_scheduler.ps1)
- [Senkranizasyon Script](https://github.com/iso-bt/Github_2_Azure-Devops/releases/download/0.0.1/Github_2_AzureDevopsServer.ps1)
