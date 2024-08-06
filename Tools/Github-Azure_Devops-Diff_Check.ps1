# Ortam değişkenlerinden bilgileri al
$github_username = $env:GITHUB_USERNAME
$github_token = $env:GITHUB_PERSONAL_ACCESS_TOKEN
$azure_org_url = $env:AZURE_ORG_URL
$azure_pat = $env:AZURE_PERSONAL_ACCESS_TOKEN

# Azure DevOps için temel kimlik doğrulama bilgisi
$azure_auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$azure_pat"))
$azure_headers = @{
    'Authorization' = "Basic $azure_auth"
}

# Log dosyası ayarları
$log_dir = "C:\log"
$log_file_repo_diff = Join-Path $log_dir "repo_diff.log"
$json_output_file = Join-Path $log_dir "repo_comparison.json"
$log_retention_days = 7

# Log yazma fonksiyonu
function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $log_message = "$timestamp [$Level] $Message"
    # Write-Host $log_message
    Add-Content -Path $log_file_repo_diff -Value $log_message
}

# Haftalık log temizleme
function Cleanup-Logs {
    $cutoff_date = (Get-Date).AddDays(-$log_retention_days)
    Get-ChildItem -Path $log_dir -File | ForEach-Object {
        if ($_.LastWriteTime -lt $cutoff_date) {
            Remove-Item $_.FullName
        }
    }
}

# GitHub API'den tüm repoları listeleme
function Get-GithubRepos {
    Write-Log "Starting: Getting list of GitHub repositories..."
    try {
        $headers = @{
            'Authorization' = "token $github_token"
            'Accept' = 'application/vnd.github.v3+json'
        }
        $response = Invoke-RestMethod -Uri "https://api.github.com/user/repos" -Headers $headers -Method Get
        Write-Log "Completed: Getting list of GitHub repositories"
        return $response
    } catch {
        Write-Log "Error: $($_.Exception.Message)" "ERROR"
        return @()
    }
}

# Azure DevOps'tan tüm projeleri listeleme
function Get-AzureProjects {
    Write-Log "Starting: Getting list of Azure DevOps projects..."
    try {
        $response = Invoke-RestMethod -Uri "$($azure_org_url)_apis/projects?api-version=6.0" -Headers $azure_headers -Method Get
        Write-Log "Completed: Getting list of Azure DevOps projects"
        return $response.value
    } catch {
        Write-Log "Error: $($_.Exception.Message)" "ERROR"
        return @()
    }
}

# GitHub repo ve branch commit sayılarını getirme
function Get-GithubCommitCount {
    param (
        [string]$RepoName,
        [string]$BranchName
    )
    try {
        $headers = @{
            'Authorization' = "token $github_token"
            'Accept' = 'application/vnd.github.v3+json'
        }
        $url = "https://api.github.com/repos/$github_username/$RepoName/commits"
        $params = @{
            'sha' = $BranchName
            'per_page' = 100
            'page' = 1
        }

        $total_commits = 0
        while ($true) {
            $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get -Body $params
            $total_commits += $response.Length
            if ($response.Length -lt $params['per_page']) { break }
            $params['page'] += 1
        }

        return $total_commits
    } catch {
        Write-Log "Error fetching commit count for $RepoName/$BranchName from GitHub: $($_.Exception.Message)" "ERROR"
        return 0
    }
}

# Azure DevOps repo ve branch commit sayılarını getirme
function Get-AzureCommitCount {
    param (
        [string]$ProjectName,
        [string]$RepoId,
        [string]$BranchName
    )
    try {
        $commits_url = "$azure_org_url/$ProjectName/_apis/git/repositories/$RepoId/commits?searchCriteria.itemVersion.version=$BranchName&searchCriteria.`$top=100"
        $page = 0
        $commit_count = 0

        while ($true) {
            $paged_commits_url = "$commits_url&searchCriteria.`$skip=$($page * 100)"
            $response = Invoke-RestMethod -Uri $paged_commits_url -Headers $azure_headers -Method Get
            $count = $response.count
            $commit_count += $count
            
            if ($count -lt 100) { break }

            $page += 1
        }

        return $commit_count
    } catch {
        Write-Log "Error fetching commit count for $RepoId/$BranchName in project $ProjectName from Azure DevOps: $($_.Exception.Message)" "ERROR"
        return 0
    }
}

# GitHub repoları ve dalları listeleme
function Get-GithubReposAndBranches {
    param (
        [Array]$Repos
    )
    Write-Log "Starting: Getting GitHub repositories and branches..."
    $github_repos_and_branches = @{}
    try {
        $headers = @{
            'Authorization' = "token $github_token"
            'Accept' = 'application/vnd.github.v3+json'
        }
        foreach ($repo in $Repos) {
            $repo_name = $repo.name
            $response = Invoke-RestMethod -Uri "https://api.github.com/repos/$github_username/$repo_name/branches" -Headers $headers -Method Get
            $branch_info = @()
            foreach ($branch in $response) {
                $branch_name = $branch.name
                $commit_count = Get-GithubCommitCount -RepoName $repo_name -BranchName $branch_name
                $branch_info += @{ $branch_name = $commit_count }
            }
            $github_repos_and_branches[$repo_name] = $branch_info
        }
        Write-Log "Completed: Getting GitHub repositories and branches"
        return $github_repos_and_branches
    } catch {
        Write-Log "Error: $($_.Exception.Message)" "ERROR"
        return @{}
    }
}

# Azure DevOps repoları ve dalları listeleme
function Get-AzureReposAndBranches {
    param (
        [string]$ProjectName
    )
    Write-Log "Starting: Getting Azure DevOps repositories and branches for project $ProjectName..."
    $azure_repos_and_branches = @{}
    try {
        $response = Invoke-RestMethod -Uri "$azure_org_url/$ProjectName/_apis/git/repositories?api-version=6.0" -Headers $azure_headers -Method Get
        $repos = $response.value
        foreach ($repo in $repos) {
            $repo_name = $repo.name
            $repo_id = $repo.id
            $branch_response = Invoke-RestMethod -Uri "$azure_org_url/$ProjectName/_apis/git/repositories/$repo_id/refs?filter=heads&api-version=6.0" -Headers $azure_headers -Method Get
            $branches = $branch_response.value
            $branch_info = @()
            foreach ($branch in $branches) {
                $branch_name = $branch.name -split '/' | Select-Object -Last 1
                $commit_count = Get-AzureCommitCount -ProjectName $ProjectName -RepoId $repo_id -BranchName $branch_name
                $branch_info += @{ $branch_name = $commit_count }
            }
            $azure_repos_and_branches[$repo_name] = $branch_info
        }
        Write-Log "Completed: Getting Azure DevOps repositories and branches for project $ProjectName"
        return $azure_repos_and_branches
    } catch {
        Write-Log "Error: $($_.Exception.Message)" "ERROR"
        return @{}
    }
}

# Repo ve branch karşılaştırma ve loglama
function Compare-And-LogDifferences {
    param (
        [Hashtable]$GithubReposAndBranches,
        [Hashtable]$AzureReposAndBranches
    )
    Write-Log "Starting: Comparing GitHub and Azure DevOps repositories and branches..."
    $comparison_results = @{
        "github" = @()
        "azure" = @()
    }
    
    # GitHub
    foreach ($repo in $GithubReposAndBranches.Keys) {
        $comparison_results["github"] += @{
            "repository" = $repo
            "branches" = $GithubReposAndBranches[$repo]
        }
    }
    
    # Azure
    foreach ($repo in $AzureReposAndBranches.Keys) {
        $comparison_results["azure"] += @{
            "repository" = $repo
            "branches" = $AzureReposAndBranches[$repo]
        }
    }

    # Writing JSON output
    $comparison_results | ConvertTo-Json -Depth 4 | Out-File -FilePath $json_output_file -Force

    Write-Log "Completed: Comparing GitHub and Azure DevOps repositories and branches"
}

function Compare-Repos {
    param (
        [string]$FilePath
    )

    # Dosyanın var olup olmadığını kontrol et
    if (-Not (Test-Path $FilePath)) {
        $path_error = "Error: $FilePath dosyası bulunamadı."
        Write-Log $path_error
        Write-Host $path_error
        return
    }

    # JSON verisini yükle
    $data = Get-Content $FilePath | ConvertFrom-Json

    # GitHub ve Azure verilerini çıkar
    $github_data = $data.github
    $azure_data = $data.azure

	# Veriyi daha kolay erişilebilir bir formata dönüştürme
	function Create-RepoDict {
		param ([Array]$RepoData)
		$repo_dict = @{}
		foreach ($repo in $RepoData) {
			$repo_name = $repo.repository
			$repo_dict[$repo_name] = @{}
			foreach ($branch in $repo.branches) {
				$repo_dict[$repo_name][$branch.PSObject.Properties.Name] = $branch.PSObject.Properties.Value
			}
		}
		return $repo_dict
	}

    # GitHub ve Azure verilerini dictionary formatına dönüştür
    $github_dict = Create-RepoDict -RepoData $github_data
    $azure_dict = Create-RepoDict -RepoData $azure_data

    # Karşılaştırma ve sonuçların yazdırılması
    $header = "{0,-30} {1,-30} {2,-15} {3,-15} {4}" -f 'Repository', 'Branch', 'GitHub Value', 'Azure Value', 'Equal'
    Write-Log $header
    Write-Host $header

    foreach ($repo in $github_dict.Keys) {
        foreach ($branch in $github_dict[$repo].Keys) {
            $github_value = $github_dict[$repo][$branch]
            $azure_value = if ($azure_dict.ContainsKey($repo)) { $azure_dict[$repo][$branch] } else { $null }
            $equal = $github_value -eq $azure_value
            $result = "{0,-30} {1,-30} {2,-15} {3,-15} {4}" -f $repo, $branch, $github_value, $azure_value, $equal
            Write-Log $result
            Write-Host $result
        }
    }

    foreach ($repo in $azure_dict.Keys) {
        if (-Not $github_dict.ContainsKey($repo)) {
            foreach ($branch in $azure_dict[$repo].Keys) {
                $github_value = $null
                $azure_value = $azure_dict[$repo][$branch]
                $equal = $false
                $result = "{0,-30} {1,-30} {2,-15} {3,-15} {4}" -f $repo, $branch, $github_value, $azure_value, $equal
                Write-Log $result
                Write-Host $result
            }
        }
    }
}

# Ana fonksiyon
function Main {
    Write-Log "Starting: Main function"
    
    Write-Log "Step 1: Fetching GitHub Repositories"
    $github_repos = Get-GithubRepos
    if (-Not $github_repos) {
        Write-Log "No GitHub repositories found or an error occurred." "ERROR"
        return
    }

    Write-Log "Step 2: Fetching Azure DevOps Projects"
    $azure_projects = Get-AzureProjects
    if (-Not $azure_projects) {
        Write-Log "No Azure DevOps projects found or an error occurred." "ERROR"
        return
    }

    Write-Log "Step 3: Fetching GitHub Repos and Branches"
    $github_repos_and_branches = Get-GithubReposAndBranches -Repos $github_repos

    Write-Log "Step 4: Fetching Azure DevOps Repos and Branches"
    $azure_repos_and_branches = @{}
    foreach ($project in $azure_projects) {
        $project_repos_and_branches = Get-AzureReposAndBranches -ProjectName $project.name
        $azure_repos_and_branches += $project_repos_and_branches
    }

    Write-Log "Step 5: Comparing Repositories and Logging Differences"
    Compare-And-LogDifferences -GithubReposAndBranches $github_repos_and_branches -AzureReposAndBranches $azure_repos_and_branches

    Write-Log "Completed: Main function"
    
    Compare-Repos -FilePath $json_output_file
    Cleanup-Logs
}

Main
