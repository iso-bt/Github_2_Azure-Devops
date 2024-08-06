import os
import base64
import requests
import json
from datetime import datetime, timedelta
import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# Ortam değişkenlerinden bilgileri al
github_username = os.getenv('GITHUB_USERNAME')
github_token = os.getenv('GITHUB_PERSONAL_ACCESS_TOKEN')
azure_org_url = os.getenv('AZURE_ORG_URL')
azure_pat = os.getenv('AZURE_PERSONAL_ACCESS_TOKEN')

# Azure DevOps için temel kimlik doğrulama bilgisi
azure_auth = base64.b64encode(f":{azure_pat}".encode('ascii')).decode('ascii')
azure_headers = {
    'Authorization': f'Basic {azure_auth}'
}

# Log dosyası ayarları
log_dir = "C:/log"
log_file_repo_diff = os.path.join(log_dir, "repo_diff.log")
json_output_file = os.path.join(log_dir, "repo_comparison.json")
log_retention_days = 7

# Log yazma fonksiyonu
def write_log(message, level="INFO"):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    log_message = f"{timestamp} [{level}] {message}"
    
    #print(log_message)
    
    with open(log_file_repo_diff, "a") as log_file:
        log_file.write(log_message + "\n")

# Haftalık log temizleme
def cleanup_logs():
    cutoff_date = datetime.now() - timedelta(days=log_retention_days)
    for log_file in os.listdir(log_dir):
        log_file_path = os.path.join(log_dir, log_file)
        if os.path.isfile(log_file_path):
            file_mtime = datetime.fromtimestamp(os.path.getmtime(log_file_path))
            if file_mtime < cutoff_date:
                os.remove(log_file_path)

# GitHub API'den tüm repoları listeleme
def get_github_repos():
    write_log("Starting: Getting list of GitHub repositories...")
    try:
        headers = {
            'Authorization': f'token {github_token}',
            'Accept': 'application/vnd.github.v3+json'
        }
        response = requests.get("https://api.github.com/user/repos", headers=headers, verify=False)
        response.raise_for_status()
        repos = response.json()
        write_log("Completed: Getting list of GitHub repositories")
        return repos
    except Exception as e:
        write_log(f"Error: {str(e)}", "ERROR")
        return []

# Azure DevOps'tan tüm projeleri listeleme
def get_azure_projects():
    write_log("Starting: Getting list of Azure DevOps projects...")
    try:
        response = requests.get(f"{azure_org_url}_apis/projects?api-version=6.0", headers=azure_headers, verify=False)
        response.raise_for_status()
        projects = response.json()['value']
        write_log("Completed: Getting list of Azure DevOps projects")
        return projects
    except Exception as e:
        write_log(f"Error: {str(e)}", "ERROR")
        return []

# GitHub repo ve branch commit sayılarını getirme
def get_github_commit_count(repo_name, branch_name):
    try:
        headers = {
            'Authorization': f'token {github_token}',
            'Accept': 'application/vnd.github.v3+json'
        }
        url = f"https://api.github.com/repos/{github_username}/{repo_name}/commits"
        params = {
            'sha': branch_name,
            'per_page': 100,
            'page': 1
        }

        total_commits = 0
        while True:
            response = requests.get(url, headers=headers, params=params, verify=False)
            response.raise_for_status()
            commits = response.json()
            total_commits += len(commits)
            if len(commits) < params['per_page']:
                break
            params['page'] += 1

        return total_commits
    except Exception as e:
        write_log(f"Error fetching commit count for {repo_name}/{branch_name} from GitHub: {str(e)}", "ERROR")
        return 0

# Azure DevOps repo ve branch commit sayılarını getirme
def get_azure_commit_count(project_name, repo_id, branch_name):
    try:        
        commits_url = f"{azure_org_url}/{project_name}/_apis/git/repositories/{repo_id}/commits?searchCriteria.itemVersion.version={branch_name}&searchCriteria.$top=100"
        page = 0
        commit_count = 0

        while True:
            paged_commits_url = f"{commits_url}&searchCriteria.$skip={page * 100}"
            response = requests.get(paged_commits_url, headers=azure_headers, verify=False)
            response.raise_for_status()
            count = response.json()['count']
            commit_count += count
            
            if count < 100:
                break

            page += 1

        return commit_count
        
    except Exception as e:
        write_log(f"Error fetching commit count for {repo_id}/{branch_name} in project {project_name} from Azure DevOps: {str(e)}", "ERROR")
        return 0

# GitHub repoları ve dalları listeleme
def get_github_repos_and_branches(repos):
    write_log("Starting: Getting GitHub repositories and branches...")
    github_repos_and_branches = {}
    try:
        headers = {
            'Authorization': f'token {github_token}',
            'Accept': 'application/vnd.github.v3+json'
        }
        for repo in repos:
            repo_name = repo['name']
            response = requests.get(f"https://api.github.com/repos/{github_username}/{repo_name}/branches", headers=headers, verify=False)
            response.raise_for_status()
            branches = response.json()
            branch_info = []
            for branch in branches:
                branch_name = branch['name']
                commit_count = get_github_commit_count(repo_name, branch_name)
                branch_info.append({branch_name: commit_count})
            github_repos_and_branches[repo_name] = branch_info
        write_log("Completed: Getting GitHub repositories and branches")
        return github_repos_and_branches
    except Exception as e:
        write_log(f"Error: {str(e)}", "ERROR")
        return {}

# Azure DevOps repoları ve dalları listeleme
def get_azure_repos_and_branches(project_name):
    write_log(f"Starting: Getting Azure DevOps repositories and branches for project {project_name}...")
    azure_repos_and_branches = {}
    try:
        response = requests.get(f"{azure_org_url}{project_name}/_apis/git/repositories?api-version=6.0", headers=azure_headers, verify=False)
        response.raise_for_status()
        repos = response.json()['value']
        for repo in repos:
            repo_name = repo['name']
            repo_id = repo['id']
            branch_response = requests.get(f"{azure_org_url}{project_name}/_apis/git/repositories/{repo_id}/refs?filter=heads&api-version=6.0", headers=azure_headers, verify=False)
            branch_response.raise_for_status()
            branches = branch_response.json()['value']
            branch_info = []
            for branch in branches:
                branch_name = branch['name'].split('/')[-1]
                commit_count = get_azure_commit_count(project_name, repo_id, branch_name)
                branch_info.append({branch_name: commit_count})
            azure_repos_and_branches[repo_name] = branch_info
        write_log(f"Completed: Getting Azure DevOps repositories and branches for project {project_name}")
        return azure_repos_and_branches
    except Exception as e:
        write_log(f"Error: {str(e)}", "ERROR")
        return {}

# Repo ve branch karşılaştırma ve loglama
def compare_and_log_differences(github_repos_and_branches, azure_repos_and_branches):
    write_log("Starting: Comparing GitHub and Azure DevOps repositories and branches...")
    comparison_results = {
        "github": [],
        "azure": []
    }
    
    # GitHub
    for repo, branches in github_repos_and_branches.items():
        comparison_results["github"].append({"repository": repo, "branches": branches})
    
    # Azure
    for repo, branches in azure_repos_and_branches.items():
        comparison_results["azure"].append({"repository": repo, "branches": branches})

    # Writing JSON output
    with open(json_output_file, 'w') as json_file:
        json.dump(comparison_results, json_file, indent=4)

    write_log("Completed: Comparing GitHub and Azure DevOps repositories and branches")

def compare_repos(file_path):
    # Dosyanın var olup olmadığını kontrol et
    if not os.path.exists(file_path):
        path_error = f"Error: {file_path} dosyası bulunamadı."
        print(path_error)
        write_log(path_error)
        return

    # JSON verisini yükle
    with open(file_path, 'r') as file:
        data = json.load(file)

    # GitHub ve Azure verilerini çıkar
    github_data = data['github']
    azure_data = data['azure']

    # Veriyi daha kolay erişilebilir bir formata dönüştürme
    def create_repo_dict(repo_data):
        repo_dict = {}
        for repo in repo_data:
            repo_name = repo['repository']
            repo_dict[repo_name] = {}
            for branch in repo['branches']:
                repo_dict[repo_name].update(branch)
        return repo_dict

    # GitHub ve Azure verilerini dictionary formatına dönüştür
    github_dict = create_repo_dict(github_data)
    azure_dict = create_repo_dict(azure_data)

    # Karşılaştırma ve sonuçların yazdırılması
    writeText = f"{'Repository':<30} {'Branch':<30} {'GitHub Value':<15} {'Azure Value':<15} {'Equal'}"
    write_log(writeText)
    write_log("-" * 110)
    print(writeText)
    print("-" * 110)

    for repo in github_dict:
        for branch in github_dict[repo]:
            github_value = github_dict[repo][branch]
            azure_value = azure_dict.get(repo, {}).get(branch, None)
            equal = github_value == azure_value
            equalText = f"{repo:<30} {branch:<30} {str(github_value):<15} {str(azure_value):<15} {equal}"
            print(equalText)
            write_log(equalText)

    for repo in azure_dict:
        if repo not in github_dict:
            for branch in azure_dict[repo]:
                github_value = None
                azure_value = azure_dict[repo][branch]
                equal = False
                print(f"{repo:<30} {branch:<30} {str(github_value):<15} {str(azure_value):<15} {equal}")


# Ana fonksiyon
def main():
    write_log("Starting: Main function")
    
    write_log("Step 1: Fetching GitHub Repositories")
    github_repos = get_github_repos()
    if not github_repos:
        write_log("No GitHub repositories found or an error occurred.", "ERROR")
        return

    write_log("Step 2: Fetching Azure DevOps Projects")
    azure_projects = get_azure_projects()
    if not azure_projects:
        write_log("No Azure DevOps projects found or an error occurred.", "ERROR")
        return

    write_log("Step 3: Fetching GitHub Repos and Branches")
    github_repos_and_branches = get_github_repos_and_branches(github_repos)

    write_log("Step 4: Fetching Azure DevOps Repos and Branches")
    azure_repos_and_branches = {}
    for project in azure_projects:
        project_repos_and_branches = get_azure_repos_and_branches(project['name'])
        azure_repos_and_branches.update(project_repos_and_branches)

    write_log("Step 5: Comparing Repositories and Logging Differences")
    compare_and_log_differences(github_repos_and_branches, azure_repos_and_branches)

    write_log("Completed: Main function")
    
    compare_repos(json_output_file)
    cleanup_logs()

if __name__ == "__main__":
    main()
