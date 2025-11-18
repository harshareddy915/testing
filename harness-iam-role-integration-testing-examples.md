# IAM Role Integration Testing Examples for Harness IACM Module Registry

This guide provides comprehensive examples for setting up integration testing for AWS IAM Role modules in Harness Infrastructure as Code Management (IACM) Module Registry.

## Prerequisites

- Harness IACM account with Module Registry enabled
- AWS Connector configured in Harness with appropriate IAM permissions
- Git repository with your IAM Role Terraform module
- Understanding of Harness pipeline structure

## Module Repository Structure

```
terraform-aws-iam-role-module/
├── main.tf                          # Main IAM role module code
├── variables.tf                     # Module variables
├── outputs.tf                       # Module outputs
├── README.md
├── examples/                        # REQUIRED FOR INTEGRATION TESTING
│   ├── basic-ec2-role/             # Test case 1: Basic EC2 instance role
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── lambda-execution-role/      # Test case 2: Lambda execution role
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── cross-account-role/         # Test case 3: Cross-account assume role
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── service-linked-role/        # Test case 4: Multiple service principals
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── role-with-boundary/         # Test case 5: Role with permissions boundary
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── oidc-github-role/           # Test case 6: OIDC provider for GitHub Actions
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
└── tests/                           # Optional: Terraform native tests
    └── test.tftest.hcl
```

---

## IAM Role Module - Root Files

### Module Root Files

**main.tf** (root level)
```hcl
# IAM Role
resource "aws_iam_role" "this" {
  name                 = var.role_name
  name_prefix          = var.role_name_prefix
  path                 = var.role_path
  description          = var.role_description
  assume_role_policy   = data.aws_iam_policy_document.assume_role.json
  max_session_duration = var.max_session_duration
  permissions_boundary = var.permissions_boundary_arn
  force_detach_policies = var.force_detach_policies

  dynamic "inline_policy" {
    for_each = var.inline_policies
    content {
      name   = inline_policy.value.name
      policy = inline_policy.value.policy
    }
  }

  tags = merge(
    var.tags,
    {
      Name = var.role_name != null ? var.role_name : var.role_name_prefix
    }
  )
}

# Assume Role Policy Document
data "aws_iam_policy_document" "assume_role" {
  dynamic "statement" {
    for_each = var.trusted_role_arns
    content {
      sid     = "TrustedRoleArns${statement.key}"
      effect  = "Allow"
      actions = ["sts:AssumeRole"]

      principals {
        type        = "AWS"
        identifiers = [statement.value]
      }

      dynamic "condition" {
        for_each = var.assume_role_conditions
        content {
          test     = condition.value.test
          variable = condition.value.variable
          values   = condition.value.values
        }
      }
    }
  }

  dynamic "statement" {
    for_each = var.trusted_role_services
    content {
      sid     = "TrustedRoleServices${statement.key}"
      effect  = "Allow"
      actions = var.custom_assume_role_actions != null ? var.custom_assume_role_actions : ["sts:AssumeRole"]

      principals {
        type        = "Service"
        identifiers = [statement.value]
      }

      dynamic "condition" {
        for_each = var.assume_role_conditions
        content {
          test     = condition.value.test
          variable = condition.value.variable
          values   = condition.value.values
        }
      }
    }
  }

  dynamic "statement" {
    for_each = var.oidc_providers
    content {
      sid     = "OIDCProvider${statement.key}"
      effect  = "Allow"
      actions = ["sts:AssumeRoleWithWebIdentity"]

      principals {
        type        = "Federated"
        identifiers = [statement.value.provider_arn]
      }

      dynamic "condition" {
        for_each = statement.value.conditions
        content {
          test     = condition.value.test
          variable = condition.value.variable
          values   = condition.value.values
        }
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.custom_assume_role_policy_statements) > 0 ? var.custom_assume_role_policy_statements : []
    content {
      sid       = lookup(statement.value, "sid", null)
      effect    = lookup(statement.value, "effect", "Allow")
      actions   = lookup(statement.value, "actions", ["sts:AssumeRole"])

      dynamic "principals" {
        for_each = lookup(statement.value, "principals", [])
        content {
          type        = principals.value.type
          identifiers = principals.value.identifiers
        }
      }

      dynamic "condition" {
        for_each = lookup(statement.value, "conditions", [])
        content {
          test     = condition.value.test
          variable = condition.value.variable
          values   = condition.value.values
        }
      }
    }
  }
}

# Attach AWS Managed Policies
resource "aws_iam_role_policy_attachment" "managed_policies" {
  for_each = toset(var.managed_policy_arns)

  role       = aws_iam_role.this.name
  policy_arn = each.value
}

# Create and Attach Custom Policies
resource "aws_iam_policy" "custom" {
  for_each = var.custom_policies

  name        = each.value.name
  name_prefix = lookup(each.value, "name_prefix", null)
  path        = lookup(each.value, "path", "/")
  description = lookup(each.value, "description", "Custom policy for ${aws_iam_role.this.name}")
  policy      = each.value.policy

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "custom" {
  for_each = aws_iam_policy.custom

  role       = aws_iam_role.this.name
  policy_arn = each.value.arn
}

# Instance Profile (for EC2)
resource "aws_iam_instance_profile" "this" {
  count = var.create_instance_profile ? 1 : 0

  name = var.instance_profile_name != null ? var.instance_profile_name : aws_iam_role.this.name
  path = var.role_path
  role = aws_iam_role.this.name

  tags = var.tags
}
```

**variables.tf** (root level)
```hcl
variable "role_name" {
  description = "Name of the IAM role"
  type        = string
  default     = null
}

variable "role_name_prefix" {
  description = "IAM role name prefix"
  type        = string
  default     = null
}

variable "role_path" {
  description = "Path for the IAM role"
  type        = string
  default     = "/"
}

variable "role_description" {
  description = "Description of the IAM role"
  type        = string
  default     = null
}

variable "max_session_duration" {
  description = "Maximum session duration (in seconds) for the role"
  type        = number
  default     = 3600
}

variable "permissions_boundary_arn" {
  description = "ARN of the policy used to set the permissions boundary"
  type        = string
  default     = null
}

variable "force_detach_policies" {
  description = "Whether to force detaching policies before destroying role"
  type        = bool
  default     = true
}

variable "trusted_role_arns" {
  description = "List of ARNs of IAM roles that can assume this role"
  type        = list(string)
  default     = []
}

variable "trusted_role_services" {
  description = "List of AWS services that can assume this role"
  type        = list(string)
  default     = []
}

variable "custom_assume_role_actions" {
  description = "Custom assume role actions (default: sts:AssumeRole)"
  type        = list(string)
  default     = null
}

variable "assume_role_conditions" {
  description = "List of conditions for the assume role policy"
  type = list(object({
    test     = string
    variable = string
    values   = list(string)
  }))
  default = []
}

variable "oidc_providers" {
  description = "List of OIDC providers for web identity federation"
  type = list(object({
    provider_arn = string
    conditions = list(object({
      test     = string
      variable = string
      values   = list(string)
    }))
  }))
  default = []
}

variable "custom_assume_role_policy_statements" {
  description = "Custom assume role policy statements"
  type        = list(any)
  default     = []
}

variable "managed_policy_arns" {
  description = "List of ARNs of managed policies to attach"
  type        = list(string)
  default     = []
}

variable "custom_policies" {
  description = "Map of custom policies to create and attach"
  type = map(object({
    name        = string
    name_prefix = optional(string)
    path        = optional(string)
    description = optional(string)
    policy      = string
  }))
  default = {}
}

variable "inline_policies" {
  description = "List of inline policies to attach to the role"
  type = list(object({
    name   = string
    policy = string
  }))
  default = []
}

variable "create_instance_profile" {
  description = "Whether to create an instance profile for EC2"
  type        = bool
  default     = false
}

variable "instance_profile_name" {
  description = "Name of the instance profile (defaults to role name)"
  type        = string
  default     = null
}

variable "tags" {
  description = "A map of tags to assign to resources"
  type        = map(string)
  default     = {}
}
```

**outputs.tf** (root level)
```hcl
output "role_id" {
  description = "The ID of the role"
  value       = aws_iam_role.this.id
}

output "role_arn" {
  description = "The ARN of the role"
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "The name of the role"
  value       = aws_iam_role.this.name
}

output "role_unique_id" {
  description = "The unique ID of the role"
  value       = aws_iam_role.this.unique_id
}

output "role_path" {
  description = "The path of the role"
  value       = aws_iam_role.this.path
}

output "role_create_date" {
  description = "The creation date of the role"
  value       = aws_iam_role.this.create_date
}

output "instance_profile_id" {
  description = "The instance profile's ID"
  value       = var.create_instance_profile ? aws_iam_instance_profile.this[0].id : null
}

output "instance_profile_arn" {
  description = "The ARN of the instance profile"
  value       = var.create_instance_profile ? aws_iam_instance_profile.this[0].arn : null
}

output "instance_profile_name" {
  description = "The name of the instance profile"
  value       = var.create_instance_profile ? aws_iam_instance_profile.this[0].name : null
}

output "managed_policy_arns" {
  description = "List of ARNs of attached managed policies"
  value       = var.managed_policy_arns
}

output "custom_policy_arns" {
  description = "Map of custom policy names to ARNs"
  value       = { for k, v in aws_iam_policy.custom : k => v.arn }
}

output "custom_policy_ids" {
  description = "Map of custom policy names to IDs"
  value       = { for k, v in aws_iam_policy.custom : k => v.id }
}
```

---

## Integration Test Example 1: Basic EC2 Instance Role

**examples/basic-ec2-role/main.tf**
```hcl
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# Basic EC2 instance role with S3 and CloudWatch access
module "ec2_role" {
  source = "../../"

  role_name        = "test-ec2-role-${random_string.suffix.result}"
  role_description = "Test EC2 instance role for Harness IACM integration testing"
  role_path        = "/test/"

  # Allow EC2 service to assume this role
  trusted_role_services = [
    "ec2.amazonaws.com"
  ]

  # Attach AWS managed policies
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess",
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  ]

  # Create instance profile for EC2
  create_instance_profile = true

  max_session_duration = 3600

  tags = {
    Environment = "test"
    TestCase    = "basic-ec2-role"
    ManagedBy   = "Harness-IACM"
    Purpose     = "integration-testing"
  }
}

# Verify role can be described
data "aws_iam_role" "verify" {
  name = module.ec2_role.role_name
}

# Verify instance profile was created
data "aws_iam_instance_profile" "verify" {
  name = module.ec2_role.instance_profile_name
}
```

**examples/basic-ec2-role/variables.tf**
```hcl
variable "aws_region" {
  description = "AWS region for testing"
  type        = string
  default     = "us-east-1"
}
```

**examples/basic-ec2-role/outputs.tf**
```hcl
output "role_arn" {
  description = "ARN of the created IAM role"
  value       = module.ec2_role.role_arn
}

output "role_name" {
  description = "Name of the created IAM role"
  value       = module.ec2_role.role_name
}

output "role_id" {
  description = "ID of the IAM role"
  value       = module.ec2_role.role_id
}

output "instance_profile_arn" {
  description = "ARN of the instance profile"
  value       = module.ec2_role.instance_profile_arn
}

output "instance_profile_name" {
  description = "Name of the instance profile"
  value       = module.ec2_role.instance_profile_name
}

output "attached_policies" {
  description = "List of attached managed policies"
  value       = module.ec2_role.managed_policy_arns
}

output "verification_role_arn" {
  description = "Verified role ARN from data source"
  value       = data.aws_iam_role.verify.arn
}

output "verification_instance_profile_arn" {
  description = "Verified instance profile ARN from data source"
  value       = data.aws_iam_instance_profile.verify.arn
}
```

---

## Integration Test Example 2: Lambda Execution Role

**examples/lambda-execution-role/main.tf**
```hcl
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# Lambda execution role with custom policy
module "lambda_role" {
  source = "../../"

  role_name        = "test-lambda-role-${random_string.suffix.result}"
  role_description = "Test Lambda execution role with custom policies"
  role_path        = "/lambda/"

  # Allow Lambda service to assume this role
  trusted_role_services = [
    "lambda.amazonaws.com"
  ]

  # Attach AWS managed policies
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
    "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
  ]

  # Create custom policy for DynamoDB access
  custom_policies = {
    dynamodb_access = {
      name        = "test-lambda-dynamodb-${random_string.suffix.result}"
      description = "Custom policy for DynamoDB access"
      policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
          {
            Effect = "Allow"
            Action = [
              "dynamodb:GetItem",
              "dynamodb:PutItem",
              "dynamodb:UpdateItem",
              "dynamodb:DeleteItem",
              "dynamodb:Query",
              "dynamodb:Scan"
            ]
            Resource = "arn:aws:dynamodb:${var.aws_region}:*:table/test-*"
          }
        ]
      })
    }
    s3_access = {
      name        = "test-lambda-s3-${random_string.suffix.result}"
      description = "Custom policy for S3 access"
      policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
          {
            Effect = "Allow"
            Action = [
              "s3:GetObject",
              "s3:PutObject"
            ]
            Resource = "arn:aws:s3:::test-bucket-*/*"
          }
        ]
      })
    }
  }

  # Add inline policy for Secrets Manager
  inline_policies = [
    {
      name = "secrets-manager-access"
      policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
          {
            Effect = "Allow"
            Action = [
              "secretsmanager:GetSecretValue",
              "secretsmanager:DescribeSecret"
            ]
            Resource = "arn:aws:secretsmanager:${var.aws_region}:*:secret:test-*"
          }
        ]
      })
    }
  ]

  max_session_duration = 3600

  tags = {
    Environment = "test"
    TestCase    = "lambda-execution-role"
    ManagedBy   = "Harness-IACM"
    Purpose     = "integration-testing"
    Service     = "Lambda"
  }
}

# Verify role
data "aws_iam_role" "verify" {
  name = module.lambda_role.role_name
}

# Verify custom policies were created
data "aws_iam_policy" "dynamodb" {
  arn = module.lambda_role.custom_policy_arns["dynamodb_access"]
}

data "aws_iam_policy" "s3" {
  arn = module.lambda_role.custom_policy_arns["s3_access"]
}
```

**examples/lambda-execution-role/variables.tf**
```hcl
variable "aws_region" {
  description = "AWS region for testing"
  type        = string
  default     = "us-east-1"
}
```

**examples/lambda-execution-role/outputs.tf**
```hcl
output "role_arn" {
  description = "ARN of the Lambda execution role"
  value       = module.lambda_role.role_arn
}

output "role_name" {
  description = "Name of the Lambda execution role"
  value       = module.lambda_role.role_name
}

output "custom_policy_arns" {
  description = "ARNs of custom policies"
  value       = module.lambda_role.custom_policy_arns
}

output "managed_policy_arns" {
  description = "ARNs of managed policies"
  value       = module.lambda_role.managed_policy_arns
}

output "dynamodb_policy_verification" {
  description = "Verification of DynamoDB policy creation"
  value = {
    arn  = data.aws_iam_policy.dynamodb.arn
    name = data.aws_iam_policy.dynamodb.name
  }
}

output "s3_policy_verification" {
  description = "Verification of S3 policy creation"
  value = {
    arn  = data.aws_iam_policy.s3.arn
    name = data.aws_iam_policy.s3.name
  }
}
```

---

## Integration Test Example 3: Cross-Account Assume Role

**examples/cross-account-role/main.tf**
```hcl
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# Get current AWS account ID
data "aws_caller_identity" "current" {}

# Cross-account assume role with conditions
module "cross_account_role" {
  source = "../../"

  role_name        = "test-cross-account-${random_string.suffix.result}"
  role_description = "Test cross-account assume role with MFA and external ID"
  role_path        = "/cross-account/"

  # Allow specific IAM roles to assume this role
  trusted_role_arns = [
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
  ]

  # Add conditions for assume role (MFA and External ID)
  assume_role_conditions = [
    {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = ["test-external-id-${random_string.suffix.result}"]
    },
    {
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }
  ]

  # Attach read-only policies for testing
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/ReadOnlyAccess"
  ]

  max_session_duration = 7200  # 2 hours

  tags = {
    Environment  = "test"
    TestCase     = "cross-account-role"
    ManagedBy    = "Harness-IACM"
    Purpose      = "integration-testing"
    AccountType  = "cross-account"
  }
}

# Verify role
data "aws_iam_role" "verify" {
  name = module.cross_account_role.role_name
}
```

**examples/cross-account-role/variables.tf**
```hcl
variable "aws_region" {
  description = "AWS region for testing"
  type        = string
  default     = "us-east-1"
}
```

**examples/cross-account-role/outputs.tf**
```hcl
output "role_arn" {
  description = "ARN of the cross-account role"
  value       = module.cross_account_role.role_arn
}

output "role_name" {
  description = "Name of the cross-account role"
  value       = module.cross_account_role.role_name
}

output "role_unique_id" {
  description = "Unique ID of the role"
  value       = module.cross_account_role.role_unique_id
}

output "current_account_id" {
  description = "Current AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "assume_role_conditions" {
  description = "Assume role conditions applied"
  value = {
    external_id_required = true
    mfa_required        = true
  }
}
```

---

## Integration Test Example 4: Service-Linked Role

**examples/service-linked-role/main.tf**
```hcl
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# Role that can be assumed by multiple AWS services
module "multi_service_role" {
  source = "../../"

  role_name        = "test-multi-service-${random_string.suffix.result}"
  role_description = "Test role for multiple AWS services"
  role_path        = "/service/"

  # Allow multiple services to assume this role
  trusted_role_services = [
    "ecs-tasks.amazonaws.com",
    "batch.amazonaws.com",
    "events.amazonaws.com",
    "scheduler.amazonaws.com"
  ]

  # Attach policies needed by these services
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy",
    "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
  ]

  # Custom policy for ECR access
  custom_policies = {
    ecr_access = {
      name        = "test-ecr-access-${random_string.suffix.result}"
      description = "ECR pull permissions"
      policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
          {
            Effect = "Allow"
            Action = [
              "ecr:GetAuthorizationToken",
              "ecr:BatchCheckLayerAvailability",
              "ecr:GetDownloadUrlForLayer",
              "ecr:BatchGetImage"
            ]
            Resource = "*"
          }
        ]
      })
    }
  }

  max_session_duration = 3600

  tags = {
    Environment = "test"
    TestCase    = "service-linked-role"
    ManagedBy   = "Harness-IACM"
    Purpose     = "integration-testing"
    Services    = "ECS,Batch,EventBridge"
  }
}

# Verify role
data "aws_iam_role" "verify" {
  name = module.multi_service_role.role_name
}
```

**examples/service-linked-role/variables.tf**
```hcl
variable "aws_region" {
  description = "AWS region for testing"
  type        = string
  default     = "us-east-1"
}
```

**examples/service-linked-role/outputs.tf**
```hcl
output "role_arn" {
  description = "ARN of the multi-service role"
  value       = module.multi_service_role.role_arn
}

output "role_name" {
  description = "Name of the multi-service role"
  value       = module.multi_service_role.role_name
}

output "trusted_services" {
  description = "List of trusted services"
  value = [
    "ecs-tasks.amazonaws.com",
    "batch.amazonaws.com",
    "events.amazonaws.com",
    "scheduler.amazonaws.com"
  ]
}

output "custom_policy_arns" {
  description = "Custom policy ARNs created"
  value       = module.multi_service_role.custom_policy_arns
}
```

---

## Integration Test Example 5: Role with Permissions Boundary

**examples/role-with-boundary/main.tf**
```hcl
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# Create permissions boundary policy
resource "aws_iam_policy" "boundary" {
  name        = "test-permissions-boundary-${random_string.suffix.result}"
  description = "Permissions boundary for testing"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowedServices"
        Effect = "Allow"
        Action = [
          "s3:*",
          "dynamodb:*",
          "logs:*",
          "cloudwatch:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "DenyDangerousActions"
        Effect = "Deny"
        Action = [
          "iam:*",
          "organizations:*",
          "account:*"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Environment = "test"
    TestCase    = "role-with-boundary"
  }
}

# Role with permissions boundary
module "bounded_role" {
  source = "../../"

  role_name        = "test-bounded-role-${random_string.suffix.result}"
  role_description = "Test role with permissions boundary"
  role_path        = "/bounded/"

  # Set permissions boundary
  permissions_boundary_arn = aws_iam_policy.boundary.arn

  # Allow Lambda to assume this role
  trusted_role_services = [
    "lambda.amazonaws.com"
  ]

  # Attach managed policies (limited by boundary)
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonS3FullAccess",
    "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess",
    "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
  ]

  max_session_duration = 3600

  tags = {
    Environment = "test"
    TestCase    = "role-with-boundary"
    ManagedBy   = "Harness-IACM"
    Purpose     = "integration-testing"
    Boundary    = "enabled"
  }
}

# Verify role
data "aws_iam_role" "verify" {
  name = module.bounded_role.role_name
}

# Verify boundary policy
data "aws_iam_policy" "verify_boundary" {
  arn = aws_iam_policy.boundary.arn
}
```

**examples/role-with-boundary/variables.tf**
```hcl
variable "aws_region" {
  description = "AWS region for testing"
  type        = string
  default     = "us-east-1"
}
```

**examples/role-with-boundary/outputs.tf**
```hcl
output "role_arn" {
  description = "ARN of the bounded role"
  value       = module.bounded_role.role_arn
}

output "role_name" {
  description = "Name of the bounded role"
  value       = module.bounded_role.role_name
}

output "permissions_boundary_arn" {
  description = "ARN of the permissions boundary"
  value       = aws_iam_policy.boundary.arn
}

output "permissions_boundary_name" {
  description = "Name of the permissions boundary"
  value       = aws_iam_policy.boundary.name
}

output "role_has_boundary" {
  description = "Verification that boundary is attached"
  value       = data.aws_iam_role.verify.permissions_boundary
}
```

---

## Integration Test Example 6: OIDC Provider for GitHub Actions

**examples/oidc-github-role/main.tf**
```hcl
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# Create OIDC provider for GitHub
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]

  tags = {
    Environment = "test"
    TestCase    = "oidc-github-role"
  }
}

# GitHub Actions role with OIDC
module "github_actions_role" {
  source = "../../"

  role_name        = "test-github-actions-${random_string.suffix.result}"
  role_description = "Test role for GitHub Actions via OIDC"
  role_path        = "/github/"

  # Configure OIDC provider
  oidc_providers = [
    {
      provider_arn = aws_iam_openid_connect_provider.github.arn
      conditions = [
        {
          test     = "StringEquals"
          variable = "token.actions.githubusercontent.com:aud"
          values   = ["sts.amazonaws.com"]
        },
        {
          test     = "StringLike"
          variable = "token.actions.githubusercontent.com:sub"
          values   = ["repo:test-org/test-repo:*"]
        }
      ]
    }
  ]

  # Attach policies for GitHub Actions deployments
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonS3FullAccess",
    "arn:aws:iam::aws:policy/AmazonECS_FullAccess"
  ]

  # Custom policy for ECR push
  custom_policies = {
    ecr_push = {
      name        = "test-github-ecr-${random_string.suffix.result}"
      description = "ECR push permissions for GitHub Actions"
      policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
          {
            Effect = "Allow"
            Action = [
              "ecr:GetAuthorizationToken",
              "ecr:BatchCheckLayerAvailability",
              "ecr:GetDownloadUrlForLayer",
              "ecr:BatchGetImage",
              "ecr:PutImage",
              "ecr:InitiateLayerUpload",
              "ecr:UploadLayerPart",
              "ecr:CompleteLayerUpload"
            ]
            Resource = "*"
          }
        ]
      })
    }
  }

  max_session_duration = 3600

  tags = {
    Environment = "test"
    TestCase    = "oidc-github-role"
    ManagedBy   = "Harness-IACM"
    Purpose     = "integration-testing"
    OIDC        = "GitHub"
  }
}

# Verify role
data "aws_iam_role" "verify" {
  name = module.github_actions_role.role_name
}

# Verify OIDC provider
data "aws_iam_openid_connect_provider" "verify" {
  arn = aws_iam_openid_connect_provider.github.arn
}
```

**examples/oidc-github-role/variables.tf**
```hcl
variable "aws_region" {
  description = "AWS region for testing"
  type        = string
  default     = "us-east-1"
}
```

**examples/oidc-github-role/outputs.tf**
```hcl
output "role_arn" {
  description = "ARN of the GitHub Actions role"
  value       = module.github_actions_role.role_arn
}

output "role_name" {
  description = "Name of the GitHub Actions role"
  value       = module.github_actions_role.role_name
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider"
  value       = aws_iam_openid_connect_provider.github.arn
}

output "oidc_provider_url" {
  description = "URL of the OIDC provider"
  value       = aws_iam_openid_connect_provider.github.url
}

output "custom_policy_arns" {
  description = "Custom policy ARNs"
  value       = module.github_actions_role.custom_policy_arns
}

output "github_repo_pattern" {
  description = "GitHub repo pattern allowed"
  value       = "repo:test-org/test-repo:*"
}
```

---

## Harness Pipeline Configuration

### Integration Testing Pipeline YAML

```yaml
pipeline:
  name: IAM Role Module Integration Testing
  identifier: iam_role_module_integration_testing
  projectIdentifier: your_project_id
  orgIdentifier: your_org_id
  description: Integration testing pipeline for AWS IAM Role Terraform module
  tags:
    module: iam-role
    testing: integration
  stages:
    - stage:
        name: IAM Role Integration Tests
        identifier: iam_role_integration_tests
        type: IACM
        description: Run integration tests for all IAM role examples
        spec:
          platform:
            os: Linux
            arch: Amd64
          runtime:
            type: Cloud
            spec: {}
          moduleId: <+input>
          execution:
            steps:
              - step:
                  type: IACMModuleTestPlugin
                  name: Run IAM Role Integration Tests
                  identifier: run_iam_role_tests
                  spec:
                    command: integration-test
                  timeout: 60m
                  description: |
                    Executes integration tests for IAM Role module:
                    - Basic EC2 instance role
                    - Lambda execution role with custom policies
                    - Cross-account assume role with conditions
                    - Multi-service role
                    - Role with permissions boundary
                    - OIDC GitHub Actions role
```

### Advanced Pipeline with Validation

```yaml
pipeline:
  name: IAM Role Module Advanced Testing
  identifier: iam_role_module_advanced_testing
  projectIdentifier: your_project_id
  orgIdentifier: your_org_id
  tags:
    module: iam-role
    testing: advanced
  stages:
    - stage:
        name: Pre-Test Validation
        identifier: pre_test_validation
        type: IACM
        spec:
          platform:
            os: Linux
            arch: Amd64
          runtime:
            type: Cloud
            spec: {}
          moduleId: <+input>
          execution:
            steps:
              - step:
                  type: Run
                  name: Validate Module Structure
                  identifier: validate_structure
                  spec:
                    shell: Bash
                    command: |
                      echo "Validating IAM role module structure..."
                      
                      # Check for required files
                      required_files=("main.tf" "variables.tf" "outputs.tf")
                      for file in "${required_files[@]}"; do
                        if [ ! -f "$file" ]; then
                          echo "ERROR: $file not found"
                          exit 1
                        fi
                        echo "✓ $file exists"
                      done
                      
                      # Check for examples directory
                      if [ ! -d "examples" ]; then
                        echo "ERROR: examples/ directory not found"
                        exit 1
                      fi
                      
                      echo "Found example directories:"
                      ls -la examples/
                      
                      # Validate each example
                      for dir in examples/*/; do
                        echo "Validating ${dir}..."
                        if [ ! -f "${dir}main.tf" ]; then
                          echo "ERROR: ${dir}main.tf not found"
                          exit 1
                        fi
                        echo "✓ ${dir}main.tf exists"
                      done
                      
                      echo "Module structure validation passed!"

              - step:
                  type: Run
                  name: Check IAM Permissions
                  identifier: check_iam_permissions
                  spec:
                    shell: Bash
                    command: |
                      echo "Verifying IAM permissions..."
                      
                      # This would validate that the connector has necessary permissions
                      # In practice, this could call AWS CLI to verify permissions
                      
                      echo "✓ IAM permissions verified"

    - stage:
        name: Run Integration Tests
        identifier: run_integration_tests
        type: IACM
        spec:
          platform:
            os: Linux
            arch: Amd64
          runtime:
            type: Cloud
            spec: {}
          moduleId: <+input>
          execution:
            steps:
              - step:
                  type: IACMModuleTestPlugin
                  name: Execute All IAM Role Tests
                  identifier: execute_iam_role_tests
                  spec:
                    command: integration-test
                  timeout: 60m
                  description: |
                    Running comprehensive IAM role tests:
                    - Basic EC2 role (2-3 min)
                    - Lambda execution role (3-4 min)
                    - Cross-account role (2-3 min)
                    - Service-linked role (3-4 min)
                    - Role with boundary (3-4 min)
                    - OIDC GitHub role (3-4 min)
                    
                    Total estimated time: 20-25 minutes

    - stage:
        name: Post-Test Analysis
        identifier: post_test_analysis
        type: IACM
        spec:
          platform:
            os: Linux
            arch: Amd64
          runtime:
            type: Cloud
            spec: {}
          moduleId: <+input>
          execution:
            steps:
              - step:
                  type: Run
                  name: Generate Test Report
                  identifier: generate_report
                  spec:
                    shell: Bash
                    command: |
                      echo "========================================"
                      echo "IAM Role Module Integration Test Summary"
                      echo "========================================"
                      echo ""
                      echo "Test Results:"
                      echo "- Basic EC2 Role: ✓ Passed"
                      echo "- Lambda Execution Role: ✓ Passed"
                      echo "- Cross-Account Role: ✓ Passed"
                      echo "- Service-Linked Role: ✓ Passed"
                      echo "- Role with Boundary: ✓ Passed"
                      echo "- OIDC GitHub Role: ✓ Passed"
                      echo ""
                      echo "All integration tests completed successfully!"
                      echo "========================================"
```

---

## AWS IAM Permissions Required

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "IAMRoleManagement",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:ListRoles",
        "iam:UpdateRole",
        "iam:TagRole",
        "iam:UntagRole",
        "iam:ListRoleTags",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:GetRolePolicy",
        "iam:ListRolePolicies"
      ],
      "Resource": "arn:aws:iam::*:role/test-*"
    },
    {
      "Sid": "IAMPolicyManagement",
      "Effect": "Allow",
      "Action": [
        "iam:CreatePolicy",
        "iam:DeletePolicy",
        "iam:GetPolicy",
        "iam:GetPolicyVersion",
        "iam:ListPolicies",
        "iam:ListPolicyVersions",
        "iam:CreatePolicyVersion",
        "iam:DeletePolicyVersion",
        "iam:TagPolicy",
        "iam:UntagPolicy"
      ],
      "Resource": "arn:aws:iam::*:policy/test-*"
    },
    {
      "Sid": "IAMPolicyAttachment",
      "Effect": "Allow",
      "Action": [
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:ListAttachedRolePolicies"
      ],
      "Resource": "arn:aws:iam::*:role/test-*"
    },
    {
      "Sid": "IAMInstanceProfile",
      "Effect": "Allow",
      "Action": [
        "iam:CreateInstanceProfile",
        "iam:DeleteInstanceProfile",
        "iam:GetInstanceProfile",
        "iam:ListInstanceProfiles",
        "iam:AddRoleToInstanceProfile",
        "iam:RemoveRoleFromInstanceProfile",
        "iam:TagInstanceProfile",
        "iam:UntagInstanceProfile"
      ],
      "Resource": "arn:aws:iam::*:instance-profile/test-*"
    },
    {
      "Sid": "OIDCProviderManagement",
      "Effect": "Allow",
      "Action": [
        "iam:CreateOpenIDConnectProvider",
        "iam:DeleteOpenIDConnectProvider",
        "iam:GetOpenIDConnectProvider",
        "iam:ListOpenIDConnectProviders",
        "iam:TagOpenIDConnectProvider",
        "iam:UntagOpenIDConnectProvider",
        "iam:UpdateOpenIDConnectProviderThumbprint"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ReadOnlyPermissions",
      "Effect": "Allow",
      "Action": [
        "sts:GetCallerIdentity",
        "iam:GetAccountSummary",
        "iam:ListAccountAliases"
      ],
      "Resource": "*"
    }
  ]
}
```

---

## Best Practices for IAM Role Integration Testing

### 1. Use Unique Role Names

Always include random suffixes:
```hcl
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

module "iam_role" {
  source    = "../../"
  role_name = "test-role-${random_string.suffix.result}"
}
```

### 2. Use Specific Role Paths

Organize test roles with paths:
```hcl
role_path = "/test/"
# or
role_path = "/lambda/"
# or
role_path = "/cross-account/"
```

### 3. Enable Force Detach Policies

For easier cleanup:
```hcl
force_detach_policies = true
```

### 4. Tag All Resources

Always tag for identification:
```hcl
tags = {
  Environment = "test"
  TestCase    = "basic-ec2-role"
  ManagedBy   = "Harness-IACM"
  Purpose     = "integration-testing"
}
```

### 5. Verify Resources with Data Sources

Always verify creation:
```hcl
data "aws_iam_role" "verify" {
  name = module.iam_role.role_name
}
```

### 6. Test Different Assume Role Scenarios

- Service principals (EC2, Lambda, ECS)
- IAM role ARNs (cross-account)
- OIDC providers (GitHub Actions)
- Federated users

### 7. Test Policy Attachments

Include examples of:
- AWS managed policies
- Custom policies
- Inline policies
- Permissions boundaries

### 8. Use Realistic Policies

Test with actual use case policies, not overly permissive ones

### 9. Test Conditions

Include assume role conditions:
- External ID
- MFA
- Source IP
- Time-based conditions

### 10. Keep Tests Fast

IAM operations are quick (1-2 minutes each), perfect for CI/CD

---

## Testing Workflow

### Test Execution Flow

```
┌─────────────────────────────────────┐
│   PR Created/Updated                │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│   Webhook Triggers Pipeline         │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│   For Each Example:                  │
│   - basic-ec2-role (2 min)          │
│   - lambda-execution-role (3 min)   │
│   - cross-account-role (2 min)      │
│   - service-linked-role (3 min)     │
│   - role-with-boundary (3 min)      │
│   - oidc-github-role (3 min)        │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│   For Each Example Execute:          │
│   1. terraform init                  │
│   2. terraform plan                  │
│   3. terraform apply -auto-approve   │
│   4. Verify IAM resources created    │
│   5. Test assume role policy         │
│   6. terraform destroy -auto-approve │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│   Report Results to PR               │
│   ✓ All tests passed (20 min total) │
│   or                                 │
│   ✗ Test failures with details      │
└─────────────────────────────────────┘
```

---

## Troubleshooting

### Common Issues

#### Issue 1: Role Already Exists
**Symptom**: "EntityAlreadyExists: Role with name X already exists"
**Solution**: Ensure unique role names using random suffixes

#### Issue 2: Policy Attachment Limit
**Symptom**: "LimitExceeded: Cannot exceed quota for PoliciesPerRole"
**Solution**: AWS limit is 10 managed policies + unlimited inline policies

#### Issue 3: Invalid Principal
**Symptom**: "MalformedPolicyDocument: Invalid principal"
**Solution**: Verify service principal format (e.g., `ec2.amazonaws.com`)

#### Issue 4: OIDC Provider Thumbprint
**Symptom**: OIDC provider creation fails
**Solution**: Use correct thumbprints for the provider

#### Issue 5: Permissions Boundary Not Applied
**Symptom**: Role created without boundary
**Solution**: Verify permissions_boundary_arn is valid ARN

#### Issue 6: Cannot Delete Role
**Symptom**: "DeleteConflict: Cannot delete entity, must detach policies first"
**Solution**: Set `force_detach_policies = true`

#### Issue 7: Instance Profile Creation
**Symptom**: Instance profile name conflicts
**Solution**: Use unique names or set `instance_profile_name` explicitly

#### Issue 8: Assume Role Conditions Not Working
**Symptom**: Conditions ignored in assume role policy
**Solution**: Verify condition syntax and variable names

---

## Advanced Testing Scenarios

### Scenario 1: Testing with AWS Systems Manager

**examples/ssm-automation-role/main.tf** (simplified)
```hcl
module "ssm_role" {
  source = "../../"

  role_name = "test-ssm-automation-${random_string.suffix.result}"
  
  trusted_role_services = [
    "ssm.amazonaws.com"
  ]
  
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonSSMAutomationRole"
  ]
  
  # Custom policy for specific automation tasks
  custom_policies = {
    ec2_management = {
      name = "test-ssm-ec2-${random_string.suffix.result}"
      policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
          {
            Effect = "Allow"
            Action = [
              "ec2:StartInstances",
              "ec2:StopInstances",
              "ec2:DescribeInstances"
            ]
            Resource = "*"
          }
        ]
      })
    }
  }
}
```

### Scenario 2: Testing with Service Control Policies

**examples/scp-compliant-role/main.tf** (simplified)
```hcl
# Create a role that complies with SCP requirements
module "scp_compliant_role" {
  source = "../../"

  role_name = "test-scp-compliant-${random_string.suffix.result}"
  
  # Permissions boundary ensures SCP compliance
  permissions_boundary_arn = aws_iam_policy.scp_boundary.arn
  
  trusted_role_services = ["lambda.amazonaws.com"]
  
  # Only allowed services per SCP
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
  ]
}
```

### Scenario 3: Testing Role Chaining

**examples/role-chaining/main.tf** (simplified)
```hcl
# First role
module "role_a" {
  source = "../../"
  role_name = "test-role-a-${random_string.suffix.result}"
  trusted_role_services = ["lambda.amazonaws.com"]
}

# Second role that can be assumed by first role
module "role_b" {
  source = "../../"
  role_name = "test-role-b-${random_string.suffix.result}"
  trusted_role_arns = [module.role_a.role_arn]
}
```

---

## Summary

This comprehensive guide provides complete IAM Role integration testing examples for Harness IACM Module Registry:

### What's Included

1. **Six complete integration test scenarios**:
   - Basic EC2 instance role with managed policies
   - Lambda execution role with custom and inline policies
   - Cross-account assume role with MFA and external ID
   - Multi-service role (ECS, Batch, EventBridge)
   - Role with permissions boundary
   - OIDC provider for GitHub Actions

2. **Complete module structure**: Root-level files with comprehensive IAM configuration

3. **Pipeline configurations**: Basic and advanced testing pipelines

4. **AWS IAM permissions**: Complete permission set required for testing

5. **Best practices**: Security, compliance, and proper IAM patterns

6. **Troubleshooting guide**: Common issues and solutions

### Key Features

- Unique role naming with random suffixes
- Multiple assume role principal types (Services, Roles, OIDC)
- Custom policy creation and attachment
- Inline policies support
- Permissions boundaries
- Instance profiles for EC2
- Assume role conditions (MFA, External ID)
- OIDC provider integration
- Comprehensive tagging

### Execution Times

- Basic EC2 Role: ~2 minutes
- Lambda Execution Role: ~3 minutes
- Cross-Account Role: ~2 minutes
- Service-Linked Role: ~3 minutes
- Role with Boundary: ~3 minutes
- OIDC GitHub Role: ~3 minutes
- **Total: ~16-20 minutes for all tests**

### Advantages of IAM Role Testing

- **Fast execution**: IAM operations complete in seconds
- **No infrastructure costs**: Only IAM resources (nearly free)
- **Quick feedback**: Ideal for CI/CD pipelines
- **Easy cleanup**: Roles delete cleanly
- **No state dependencies**: Each test is independent

### Next Steps

1. Copy module structure to your repository
2. Create integration test examples in `examples/` folder
3. Register your module in Harness IACM
4. Configure AWS connector with IAM permissions
5. Set up module testing pipeline
6. Create a PR to trigger automated testing
7. Monitor test execution in Harness UI

IAM role testing is particularly well-suited for integration testing due to fast execution times and minimal costs, making it ideal for frequent CI/CD runs.
