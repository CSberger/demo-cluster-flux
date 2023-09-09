terraform {
  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 4.0"
    }
  }
}

provider "github" {
  token        = var.github_token
  owner = var.github_owner
}

module "repo" {
  source = "./github"
  repo_name = var.repo_name
}


