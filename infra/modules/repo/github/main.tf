terraform {
  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 4.0"
    }
  }
}

variable "repo_name" {}


resource "github_repository" "repo" {
  name        = var.repo_name
  description = "My awesome codebase"
  auto_init   = true
  visibility = "private"

}

resource "github_branch" "main" {
  branch     = "main"
  repository = github_repository.repo.name
}
resource github_branch_default "repo" {
  branch = github_branch.main.branch
  repository = github_repository.repo.name
}


resource "github_actions_secret" "sonar_token" {
  repository  = github_repository.repo.name
  secret_name = "SONAR_TOKEN"
  plaintext_value = "local"
}
