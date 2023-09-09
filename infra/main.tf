terraform {
  required_version = ">= 0.13"
  required_providers {
    github = {
      source  = "integrations/github"
      version = ">= 4.5.2"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0.2"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.10.0"
    }
    flux = {
      source = "fluxcd/flux"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "3.1.0"
    }
  }
}

locals {
  account_id = data.aws_caller_identity.current.account_id

  namespace                = "external-secrets"
  cluster_secretstore_name = "cluster-secretstore-sm"
  cluster_secretstore_sa   = "cluster-secretstore-sa"
  secret_prefix = "secretstore"
  secret_region = var.aws_region
  istio_elb_hostname = "addab9898bc784e4486d6d4c15f68720-3217248.us-west-2.elb.amazonaws.com"
  dns_basename = "sandcastle.work"
  tags = {}
}
provider "aws" {
  region = var.aws_region
}

provider "github" {
  owner = var.github_owner
  token = var.github_token
}

data "aws_caller_identity" "current" {}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "eks-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-west-2a", "us-west-2b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.201.0/24"]

  enable_nat_gateway = true
  enable_vpn_gateway = true

  tags = {
    Terraform = "true"
    Environment = "dev"
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = "demo-cluster"
  cluster_version = "1.27"

  cluster_endpoint_public_access  = true

  cluster_addons = {
    coredns = {
      most_recent = true
      configuration_values = jsonencode({

        nodeSelector = {
          "role": "system"
        }
        tolerations = [
          {
            "key" = "dedicated",
            "value" = "system"
          }
        ]
      })
    }
      
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  node_security_group_additional_rules = {
      istio_injection_webhook = {
        description                = "Cluster API to istiod webhook"
        protocol                   = "tcp"
        from_port                  = "15017"
        to_port                    = "15017"
        type                       = "ingress"
        source_cluster_security_group = true
      }
    }
  # Fargate Profile(s)
  # fargate_profiles = {
  #   default = {
  #     name = "default"
  #     selectors = [
  #       {
  #         namespace = "*"
  #         labels = {"fargate": "true"}
  #       }
  #     ]
  #   }
  # }

  eks_managed_node_groups = {
    system2 = {
      min_size     = 1
      max_size     = 3
      desired_size = 1

      instance_types = ["m7g.medium"]
      ami_type = "BOTTLEROCKET_ARM_64"

      labels = {
        role        = "system"
      }

      taints = {
        dedicated = {
          key    = "dedicated"
          value  = "system"
          effect = "NO_SCHEDULE"
        }
      }
    }
    

    monitoring2 = {
      min_size      = 1
      max_size      = 3
      desired_size  = 1

      instance_types = ["m7g.medium"]
      ami_type = "BOTTLEROCKET_ARM_64"

      labels = {
        role        = "monitoring"
      }

      taints = {
        dedicated = {
          key       = "dedicated"
          value     = "monitoring"
          effect    = "NO_SCHEDULE"
        }
      }
    }
    workerm = {
      min_size      = 1
      max_size      = 3
      desired_size  = 1

      instance_types = ["m7g.large"]
      ami_type = "BOTTLEROCKET_ARM_64"

      labels = {
        role        = "worker"
      }
    }        
  }

  tags = {
    Environment = "dev"
    Terraform   = "true"
  }
}

resource "tls_private_key" "flux" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "github_repository" "main" {
  name       = var.repository_name
  visibility = var.repository_visibility
  auto_init  = true
  lifecycle {
    prevent_destroy = false
  }
}

resource "github_branch_default" "main" {
  repository = github_repository.main.name
  branch     = var.branch
  lifecycle {
    prevent_destroy = false
  }
}

resource "github_repository_deploy_key" "this" {
  title      = "staging-cluster"
  repository = github_repository.main.name
  key        = tls_private_key.flux.public_key_openssh
  read_only  = false
  lifecycle {
    prevent_destroy = false
  }
}

provider "flux" {
  kubernetes = {
    host                   =  module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(
      module.eks.cluster_certificate_authority_data
    )
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
      command     = "aws"
    }  
  }

  git = {
    url = "ssh://git@github.com/${var.github_owner}/${var.repository_name}.git"
    ssh = {
      username    = "git"
      private_key = tls_private_key.flux.private_key_pem
    }
  }
}

resource "flux_bootstrap_git" "this" {
  depends_on = [github_repository_deploy_key.this]

  path = var.target_path
  components_extra = ["image-reflector-controller", "image-automation-controller"]
  toleration_keys = ["dedicated"]
}




module "cluster_autoscaler_irsa_role" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name                        = "cluster-autoscaler-role"
  attach_cluster_autoscaler_policy = true
  cluster_autoscaler_cluster_names = [module.eks.cluster_name]

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["autoscaler:autoscaler-aws-cluster-autoscaler"]
    }
  }
}

resource "aws_kms_key" "secrets" {
  enable_key_rotation = true
}

module "cluster_secretstore_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.20"

  role_name_prefix = "${module.eks.cluster_name}-secrets-manager-"

  role_policy_arns = {
    policy = aws_iam_policy.cluster_secretstore.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${local.namespace}:${local.cluster_secretstore_sa}"]
    }
  }

  tags = local.tags
}

resource "aws_iam_policy" "cluster_secretstore" {
  name_prefix = local.cluster_secretstore_sa
  policy      = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetResourcePolicy",
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
        "secretsmanager:ListSecretVersionIds"
      ],
      "Resource": [
        "arn:aws:secretsmanager:${local.secret_region}:${local.account_id}:secret:${local.secret_prefix}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt"
      ],
      "Resource": "${aws_kms_key.secrets.arn}"
    }
  ]
}
POLICY
}


resource "random_password" "grafana_admin_password" {
  length           = 32
  special          = true
  override_special = "_%@"
}

locals {
  monitoring_credentials = {
      "username" = "admin"
      "password" = random_password.grafana_admin_password.result
  }
} 

resource "aws_secretsmanager_secret" "monitoring_credentials" {
  name = "${local.secret_prefix}/monitoring_credentials"
}

resource "aws_secretsmanager_secret_version" "monitoring_credentials" {
  secret_id     = aws_secretsmanager_secret.monitoring_credentials.id
  secret_string = jsonencode(local.monitoring_credentials)
}
resource "aws_secretsmanager_secret" "ilant_credentials" {
  name = "${local.secret_prefix}/ilant_api_key"
}

resource "aws_secretsmanager_secret_version" "ilant_credentials" {
  secret_id     = aws_secretsmanager_secret.ilant_credentials.id
  secret_string = jsonencode({api_key = ""})
}


resource "aws_acm_certificate" "cert" {
  domain_name       = "*.${local.dns_basename}"
  validation_method = "DNS"

  tags = {
    Environment = "dev"
  }

  lifecycle {
    create_before_destroy = true
  }
}



# module "ilant_fe_img_repo" {
#   source = "./modules/img_repo"
#   git_repo_name = "ilant-fe"
#   repo_name = "ilant-fe"
#   github_owner = var.github_owner
#   github_token = var.github_token
#   aws_region= "us-west-2"
# }


# module "ilant_be_img_repo" {
#   source = "./modules/img_repo"
#   git_repo_name = "ilant-test"
#   repo_name = "ilant-be"
#   github_owner = var.github_owner
#   github_token = var.github_token
#   aws_region= "us-west-2"
# }
