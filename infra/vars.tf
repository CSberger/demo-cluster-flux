variable "github_owner" {
  type = string
}

variable "github_token" {
  type = string
  sensitive   = true
}

variable "repository_name" {
  type        = string
  default     = "test-provider"
  description = "github repository name"
}

variable "repository_visibility" {
  type        = string
  default     = "private"
  description = "How visible is the github repo"
}

variable "branch" {
  type        = string
  default     = "main"
  description = "branch name"
}

variable "target_path" {
  type        = string
  default     = "demo-cluster"
  description = "flux sync target path"
}

variable "aws_region" {
  type        = string
  default     = "us-west-2"
  description = "aws region"
}