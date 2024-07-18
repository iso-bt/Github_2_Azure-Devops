# GitHub ve Azure DevOps bilgilerini ortam değişkenlerinden al
$githubUsername = $env:GITHUB_USERNAME
$githubToken = $env:GITHUB_PERSONAL_ACCESS_TOKEN
$azureOrgUrl = $env:AZURE_ORG_URL
$azurePat = $env:AZURE_PERSONAL_ACCESS_TOKEN

# Base64 encoding for Azure PAT
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$azurePat"))

# Log dosyası ayarları
$logDir = "C:\log"
$logFileGeneral = "$logDir\migration_general.log"
$logFileError = "$logDir\migration_error.log"
$logFileAll = "$logDir\migration_all.log"
$logRetentionDays = 7

# Geçici repo klasörü
$tempRepoDir = "C:\temp_repo"

# Log klasörünü ve geçici repo klasörünü oluşturma
if (-Not (Test-Path -Path $logDir)) {
    New-Item -ItemType Directory -Force -Path $logDir
}
if (-Not (Test-Path -Path $tempRepoDir)) {
    New-Item -ItemType Directory -Force -Path $tempRepoDir
}

# Log yazma fonksiyonu
function Write-Log {
    param (
        [string]$message,
        [string]$level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp [$level] $message"
    
    if ($level -eq "ERROR") {
        Add-Content -Path $logFileError -Value $logMessage
    } else {
        Add-Content -Path $logFileGeneral -Value $logMessage
    }
    Add-Content -Path $logFileAll -Value $logMessage
}

# Haftalık log temizleme
function Cleanup-Logs {
    Get-ChildItem -Path $logDir -Filter "*.log" | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$logRetentionDays) } | Remove-Item -Force
}

# Geçici repo klasörünü temizleme
function Cleanup-TempRepo {
    Remove-Item -Recurse -Force -Path "$tempRepoDir\*"
}

# GitHub API'den tüm repoları listeleme
function Get-GitHubRepos {
    Write-Log "Starting: Getting list of GitHub repositories..."
    try {
        $headers = @{
            Authorization = "token $githubToken"
            Accept = "application/vnd.github.v3+json"
        }
        $response = Invoke-RestMethod -Uri "https://api.github.com/user/repos" -Headers $headers
        Write-Log "Completed: Getting list of GitHub repositories."
        return $response
    } catch {
        Write-Log "Error during 'Getting list of GitHub repositories': $_" "ERROR"
        exit 1
    }
}

# Azure DevOps'taki tüm projeleri listeleme
function Get-AzureProjects {
    Write-Log "Starting: Getting list of Azure DevOps projects..."
    try {
        $url = "$azureOrgUrl/_apis/projects?api-version=6.0"
        $headers = @{
            "Authorization" = "Basic $base64AuthInfo"
        }
        $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
        Write-Log "Completed: Getting list of Azure DevOps projects."
        return $response.value
    } catch {
        Write-Log "Error during 'Getting list of Azure DevOps projects': $_" "ERROR"
        exit 1
    }
}

# Azure DevOps'ta proje oluşturma
function Create-AzureProject {
    param (
        [string]$projectName
    )
    Write-Log "Starting: Creating Azure DevOps project: $projectName"
    try {
        $url = "$azureOrgUrl/_apis/projects?api-version=6.0"
        $headers = @{
            "Content-Type"  = "application/json"
            "Authorization" = "Basic $base64AuthInfo"
        }
        $body = @{
            name = $projectName
            visibility = "private"
            capabilities = @{
                versioncontrol = @{
                    sourceControlType = "Git"
                }
                processTemplate = @{
                    templateTypeId = "adcc42ab-9882-485e-a3ed-7678f01f66bc" # Scrum template
                }
            }
        }
        $bodyJson = $body | ConvertTo-Json
        $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Post -Body $bodyJson
        Write-Log "Completed: Creating Azure DevOps project: $projectName"
        Start-Sleep -Seconds 10 # Projenin tam olarak oluşturulması için bekleme süresi
        return $response
    } catch {
        if ($_.Exception.Response.StatusCode.Value__ -eq 409) {
            Write-Log "Project $projectName already exists. Skipping project creation."
            return $null
        } else {
            Write-Log "Error during 'Creating Azure DevOps project': $_" "ERROR"
            exit 1
        }
    }
}

# Azure DevOps'a GitHub reposunu import etme
function Import-GitHubRepoToAzure {
    param (
        [string]$projectName,
        [string]$repoName,
        [string]$repoCloneUrl
    )
    Write-Log "Starting: Importing GitHub repo: $repoName to Azure DevOps project: $projectName"
    try {
        $url = "$azureOrgUrl/$projectName/_apis/git/repositories?api-version=6.0"
        $headers = @{
            "Content-Type"  = "application/json"
            "Authorization" = "Basic $base64AuthInfo"
        }
        $body = @{
            name = $repoName
            remoteUrl = $repoCloneUrl
        }
        $bodyJson = $body | ConvertTo-Json
        $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Post -Body $bodyJson
        Write-Log "Completed: Importing GitHub repo: $repoName to Azure DevOps project: $projectName"
        return $response
    } catch {
        Write-Log "Error during 'Importing GitHub repo to Azure DevOps': $_" "ERROR"
        exit 1
    }
}

# GitHub reposunu klonlayıp Azure DevOps projesine gönderme
function CloneAndPushRepo {
    param (
        [string]$repoName,
        [string]$repoCloneUrl,
        [string]$azureProjectUrl
    )
    Write-Log "Starting: Cloning GitHub repo: $repoName"
    try {
        $localRepoPath = "$tempRepoDir\$repoName"
        git clone $repoCloneUrl $localRepoPath
        Set-Location -Path $localRepoPath
        git remote set-url origin $azureProjectUrl
        git push --all
        Set-Location -Path $tempRepoDir
        Write-Log "Completed: Cloning and pushing GitHub repo: $repoName to Azure DevOps project."
    } catch {
        Write-Log "Error during 'Cloning and pushing GitHub repo to Azure DevOps': $_" "ERROR"
        exit 1
    }
}

# Ana fonksiyon
function Main {
    Write-Log "Starting: Main function"
    $repos = Get-GitHubRepos
    $azureProjects = Get-AzureProjects

    foreach ($repo in $repos) {
        $repoName = $repo.name
        $repoCloneUrl = $repo.clone_url
        Write-Log "Processing repository: $repoName"
        $projectExists = $false
        foreach ($project in $azureProjects) {
            if ($project.name -eq $repoName) {
                $projectExists = $true
                break
            }
        }
        if ($projectExists) {
            Write-Log "$repoName : Project already exists. Updating project with GitHub repo."
        } else {
            Write-Log "$repoName : Project does not exist. Creating new project."
            $projectCreationResponse = Create-AzureProject -projectName $repoName
            if ($projectCreationResponse -eq $null) {
                Write-Log "$repoName : Skipping project creation as it already exists."
            } elseif ($projectCreationResponse -ne $null) {
                $importResponse = Import-GitHubRepoToAzure -projectName $repoName -repoName $repoName -repoCloneUrl $repoCloneUrl
                if ($importResponse -ne $null) {
                    Write-Log "$repoName : Successfully imported repo to new project."
                }
            } else {
                Write-Log "$repoName : Failed to create project." "ERROR"
                exit 1
            }
        }

        # Azure DevOps repo URL'sini oluştur
        $azureProjectUrl = "$azureOrgUrl/$repoName/_git/$repoName"

        # GitHub reposunu klonlayıp Azure DevOps'a gönder
        CloneAndPushRepo -repoName $repoName -repoCloneUrl $repoCloneUrl -azureProjectUrl $azureProjectUrl
    }
    Write-Log "Completed: Main function"
    Cleanup-TempRepo
    Cleanup-Logs
}

# Scripti çalıştır
Main
