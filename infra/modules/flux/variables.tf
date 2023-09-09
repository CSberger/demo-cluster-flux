variable "cluster_name" {
  type        = string
  description = "cluster name"
}

variable "github_owner" {
  type        = string
  description = "github owner"
}

variable "github_token" {
  type        = string
  description = "github token"
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
  default     = "staging-cluster"
  description = "flux sync target path"
}

variable "components_extra" {
  type        = list(string)
  default     =  ["image-reflector-controller", "image-automation-controller"]
  description = "extra flux components"
}
