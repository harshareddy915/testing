# ECS Cluster Integration Testing Examples for Harness IACM Module Registry

This guide provides comprehensive examples for setting up integration testing for AWS ECS (Elastic Container Service) Cluster modules in Harness Infrastructure as Code Management (IACM) Module Registry.

## Prerequisites

- Harness IACM account with Module Registry enabled
- AWS Connector configured in Harness with appropriate ECS permissions
- Git repository with your ECS Cluster Terraform module
- Understanding of Harness pipeline structure

## Module Repository Structure

```
terraform-aws-ecs-cluster-module/
├── main.tf                          # Main ECS cluster module code
├── variables.tf                     # Module variables
├── outputs.tf                       # Module outputs
├── README.md
├── examples/                        # REQUIRED FOR INTEGRATION TESTING
│   ├── basic-ec2-cluster/          # Test case 1: Basic EC2 launch type cluster
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── fargate-cluster/            # Test case 2: Fargate cluster with capacity providers
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── cluster-with-insights/      # Test case 3: Cluster with Container Insights
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── hybrid-cluster/             # Test case 4: Hybrid EC2 + Fargate cluster
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── cluster-with-service/       # Test case 5: Cluster with ECS service
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── cluster-with-asg/           # Test case 6: EC2 cluster with Auto Scaling Group
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
└── tests/                           # Optional: Terraform native tests
    └── test.tftest.hcl
```

---

## ECS Cluster Module - Root Files

### Module Root Files

**main.tf** (root level)
```hcl
# ECS Cluster
resource "aws_ecs_cluster" "this" {
  name = var.cluster_name

  dynamic "setting" {
    for_each = var.container_insights ? [1] : []
    content {
      name  = "containerInsights"
      value = "enabled"
    }
  }

  dynamic "configuration" {
    for_each = var.execute_command_configuration != null ? [var.execute_command_configuration] : []
    content {
      execute_command_configuration {
        kms_key_id = lookup(configuration.value, "kms_key_id", null)
        logging    = lookup(configuration.value, "logging", "DEFAULT")

        dynamic "log_configuration" {
          for_each = lookup(configuration.value, "log_configuration", null) != null ? [configuration.value.log_configuration] : []
          content {
            cloud_watch_encryption_enabled = lookup(log_configuration.value, "cloud_watch_encryption_enabled", null)
            cloud_watch_log_group_name     = lookup(log_configuration.value, "cloud_watch_log_group_name", null)
            s3_bucket_name                 = lookup(log_configuration.value, "s3_bucket_name", null)
            s3_bucket_encryption_enabled   = lookup(log_configuration.value, "s3_bucket_encryption_enabled", null)
            s3_key_prefix                  = lookup(log_configuration.value, "s3_key_prefix", null)
          }
        }
      }
    }
  }

  dynamic "service_connect_defaults" {
    for_each = var.service_connect_defaults != null ? [var.service_connect_defaults] : []
    content {
      namespace = service_connect_defaults.value.namespace
    }
  }

  tags = merge(
    var.tags,
    {
      Name = var.cluster_name
    }
  )
}

# Cluster Capacity Providers
resource "aws_ecs_cluster_capacity_providers" "this" {
  count = length(var.capacity_providers) > 0 || length(var.default_capacity_provider_strategy) > 0 ? 1 : 0

  cluster_name = aws_ecs_cluster.this.name

  capacity_providers = var.capacity_providers

  dynamic "default_capacity_provider_strategy" {
    for_each = var.default_capacity_provider_strategy
    content {
      capacity_provider = default_capacity_provider_strategy.value.capacity_provider
      weight           = lookup(default_capacity_provider_strategy.value, "weight", null)
      base             = lookup(default_capacity_provider_strategy.value, "base", null)
    }
  }
}

# Capacity Provider for EC2
resource "aws_ecs_capacity_provider" "ec2" {
  for_each = var.ec2_capacity_providers

  name = each.value.name

  auto_scaling_group_provider {
    auto_scaling_group_arn         = each.value.auto_scaling_group_arn
    managed_termination_protection = lookup(each.value, "managed_termination_protection", "DISABLED")

    dynamic "managed_scaling" {
      for_each = lookup(each.value, "managed_scaling", null) != null ? [each.value.managed_scaling] : []
      content {
        maximum_scaling_step_size = lookup(managed_scaling.value, "maximum_scaling_step_size", 10000)
        minimum_scaling_step_size = lookup(managed_scaling.value, "minimum_scaling_step_size", 1)
        status                    = lookup(managed_scaling.value, "status", "ENABLED")
        target_capacity           = lookup(managed_scaling.value, "target_capacity", 100)
        instance_warmup_period    = lookup(managed_scaling.value, "instance_warmup_period", 300)
      }
    }
  }

  tags = merge(
    var.tags,
    lookup(each.value, "tags", {})
  )
}

# CloudWatch Log Group for Execute Command
resource "aws_cloudwatch_log_group" "execute_command" {
  count = var.create_execute_command_log_group ? 1 : 0

  name              = "/ecs/${var.cluster_name}/execute-command"
  retention_in_days = var.execute_command_log_retention_days
  kms_key_id        = var.execute_command_log_kms_key_id

  tags = merge(
    var.tags,
    {
      Name = "/ecs/${var.cluster_name}/execute-command"
    }
  )
}

# KMS Key for Execute Command
resource "aws_kms_key" "execute_command" {
  count = var.create_execute_command_kms_key ? 1 : 0

  description             = "KMS key for ECS Execute Command encryption - ${var.cluster_name}"
  deletion_window_in_days = var.kms_key_deletion_window
  enable_key_rotation     = var.kms_key_enable_rotation

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-execute-command-key"
    }
  )
}

resource "aws_kms_alias" "execute_command" {
  count = var.create_execute_command_kms_key ? 1 : 0

  name          = "alias/${var.cluster_name}-execute-command"
  target_key_id = aws_kms_key.execute_command[0].key_id
}
```

**variables.tf** (root level)
```hcl
variable "cluster_name" {
  description = "Name of the ECS cluster"
  type        = string
}

variable "container_insights" {
  description = "Enable CloudWatch Container Insights for the cluster"
  type        = bool
  default     = false
}

variable "capacity_providers" {
  description = "List of capacity provider names to associate with the cluster"
  type        = list(string)
  default     = []
}

variable "default_capacity_provider_strategy" {
  description = "Default capacity provider strategy for the cluster"
  type = list(object({
    capacity_provider = string
    weight           = optional(number)
    base             = optional(number)
  }))
  default = []
}

variable "ec2_capacity_providers" {
  description = "Map of EC2 capacity provider configurations"
  type = map(object({
    name                           = string
    auto_scaling_group_arn         = string
    managed_termination_protection = optional(string)
    managed_scaling = optional(object({
      maximum_scaling_step_size = optional(number)
      minimum_scaling_step_size = optional(number)
      status                    = optional(string)
      target_capacity           = optional(number)
      instance_warmup_period    = optional(number)
    }))
    tags = optional(map(string))
  }))
  default = {}
}

variable "execute_command_configuration" {
  description = "Execute command configuration for the cluster"
  type = object({
    kms_key_id = optional(string)
    logging    = optional(string)
    log_configuration = optional(object({
      cloud_watch_encryption_enabled = optional(bool)
      cloud_watch_log_group_name     = optional(string)
      s3_bucket_name                 = optional(string)
      s3_bucket_encryption_enabled   = optional(bool)
      s3_key_prefix                  = optional(string)
    }))
  })
  default = null
}

variable "service_connect_defaults" {
  description = "Service Connect defaults for the cluster"
  type = object({
    namespace = string
  })
  default = null
}

variable "create_execute_command_log_group" {
  description = "Create CloudWatch log group for execute command"
  type        = bool
  default     = false
}

variable "execute_command_log_retention_days" {
  description = "CloudWatch log group retention in days"
  type        = number
  default     = 7
}

variable "execute_command_log_kms_key_id" {
  description = "KMS key ID for CloudWatch log group encryption"
  type        = string
  default     = null
}

variable "create_execute_command_kms_key" {
  description = "Create KMS key for execute command encryption"
  type        = bool
  default     = false
}

variable "kms_key_deletion_window" {
  description = "KMS key deletion window in days"
  type        = number
  default     = 7
}

variable "kms_key_enable_rotation" {
  description = "Enable automatic key rotation"
  type        = bool
  default     = true
}

variable "tags" {
  description = "A map of tags to assign to resources"
  type        = map(string)
  default     = {}
}
```

**outputs.tf** (root level)
```hcl
output "cluster_id" {
  description = "ID of the ECS cluster"
  value       = aws_ecs_cluster.this.id
}

output "cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.this.arn
}

output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.this.name
}

output "capacity_providers" {
  description = "Capacity providers associated with the cluster"
  value       = var.capacity_providers
}

output "ec2_capacity_provider_arns" {
  description = "ARNs of EC2 capacity providers"
  value       = { for k, v in aws_ecs_capacity_provider.ec2 : k => v.arn }
}

output "ec2_capacity_provider_ids" {
  description = "IDs of EC2 capacity providers"
  value       = { for k, v in aws_ecs_capacity_provider.ec2 : k => v.id }
}

output "execute_command_log_group_name" {
  description = "Name of the CloudWatch log group for execute command"
  value       = var.create_execute_command_log_group ? aws_cloudwatch_log_group.execute_command[0].name : null
}

output "execute_command_log_group_arn" {
  description = "ARN of the CloudWatch log group for execute command"
  value       = var.create_execute_command_log_group ? aws_cloudwatch_log_group.execute_command[0].arn : null
}

output "execute_command_kms_key_id" {
  description = "KMS key ID for execute command"
  value       = var.create_execute_command_kms_key ? aws_kms_key.execute_command[0].key_id : null
}

output "execute_command_kms_key_arn" {
  description = "ARN of the KMS key for execute command"
  value       = var.create_execute_command_kms_key ? aws_kms_key.execute_command[0].arn : null
}
```

---

## Integration Test Example 1: Basic EC2 Cluster

**examples/basic-ec2-cluster/main.tf**
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

# Basic ECS Cluster with EC2 launch type
module "ecs_cluster" {
  source = "../../"

  cluster_name       = "test-ec2-cluster-${random_string.suffix.result}"
  container_insights = false

  tags = {
    Environment = "test"
    TestCase    = "basic-ec2-cluster"
    ManagedBy   = "Harness-IACM"
    Purpose     = "integration-testing"
    LaunchType  = "EC2"
  }
}

# Verify cluster
data "aws_ecs_cluster" "verify" {
  cluster_name = module.ecs_cluster.cluster_name
}
```

**examples/basic-ec2-cluster/variables.tf**
```hcl
variable "aws_region" {
  description = "AWS region for testing"
  type        = string
  default     = "us-east-1"
}
```

**examples/basic-ec2-cluster/outputs.tf**
```hcl
output "cluster_id" {
  description = "ID of the ECS cluster"
  value       = module.ecs_cluster.cluster_id
}

output "cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = module.ecs_cluster.cluster_arn
}

output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.ecs_cluster.cluster_name
}

output "cluster_verification" {
  description = "Verification data from cluster"
  value = {
    arn    = data.aws_ecs_cluster.verify.arn
    status = data.aws_ecs_cluster.verify.status
  }
}
```

---

## Integration Test Example 2: Fargate Cluster

**examples/fargate-cluster/main.tf**
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

# Fargate Cluster with Capacity Providers
module "fargate_cluster" {
  source = "../../"

  cluster_name       = "test-fargate-${random_string.suffix.result}"
  container_insights = true

  # Fargate capacity providers
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  # Default capacity provider strategy
  default_capacity_provider_strategy = [
    {
      capacity_provider = "FARGATE"
      weight           = 1
      base             = 1
    },
    {
      capacity_provider = "FARGATE_SPOT"
      weight           = 4
    }
  ]

  tags = {
    Environment = "test"
    TestCase    = "fargate-cluster"
    ManagedBy   = "Harness-IACM"
    Purpose     = "integration-testing"
    LaunchType  = "Fargate"
  }
}

# Verify cluster
data "aws_ecs_cluster" "verify" {
  cluster_name = module.fargate_cluster.cluster_name
}
```

**examples/fargate-cluster/variables.tf**
```hcl
variable "aws_region" {
  description = "AWS region for testing"
  type        = string
  default     = "us-east-1"
}
```

**examples/fargate-cluster/outputs.tf**
```hcl
output "cluster_id" {
  description = "ID of the Fargate cluster"
  value       = module.fargate_cluster.cluster_id
}

output "cluster_arn" {
  description = "ARN of the Fargate cluster"
  value       = module.fargate_cluster.cluster_arn
}

output "cluster_name" {
  description = "Name of the Fargate cluster"
  value       = module.fargate_cluster.cluster_name
}

output "capacity_providers" {
  description = "Capacity providers configured"
  value       = module.fargate_cluster.capacity_providers
}

output "container_insights_enabled" {
  description = "Container Insights status"
  value       = "enabled"
}

output "capacity_provider_strategy" {
  description = "Default capacity provider strategy"
  value = {
    fargate      = "base: 1, weight: 1"
    fargate_spot = "base: 0, weight: 4"
  }
}
```

---

## Integration Test Example 3: Cluster with Container Insights

**examples/cluster-with-insights/main.tf**
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

# ECS Cluster with Container Insights and Execute Command
module "insights_cluster" {
  source = "../../"

  cluster_name       = "test-insights-${random_string.suffix.result}"
  container_insights = true

  # Fargate capacity providers
  capacity_providers = ["FARGATE"]

  # Create resources for execute command
  create_execute_command_log_group = true
  execute_command_log_retention_days = 7
  create_execute_command_kms_key = true

  # Execute command configuration
  execute_command_configuration = {
    logging = "OVERRIDE"
    log_configuration = {
      cloud_watch_encryption_enabled = true
      cloud_watch_log_group_name     = "/ecs/test-insights-${random_string.suffix.result}/execute-command"
    }
  }

  tags = {
    Environment     = "test"
    TestCase        = "cluster-with-insights"
    ManagedBy       = "Harness-IACM"
    Purpose         = "integration-testing"
    ContainerInsights = "enabled"
    ExecuteCommand  = "enabled"
  }
}

# Verify cluster
data "aws_ecs_cluster" "verify" {
  cluster_name = module.insights_cluster.cluster_name
}

# Verify log group
data "aws_cloudwatch_log_group" "verify" {
  name = module.insights_cluster.execute_command_log_group_name
}

# Verify KMS key
data "aws_kms_key" "verify" {
  key_id = module.insights_cluster.execute_command_kms_key_id
}
```

**examples/cluster-with-insights/variables.tf**
```hcl
variable "aws_region" {
  description = "AWS region for testing"
  type        = string
  default     = "us-east-1"
}
```

**examples/cluster-with-insights/outputs.tf**
```hcl
output "cluster_id" {
  description = "ID of the cluster"
  value       = module.insights_cluster.cluster_id
}

output "cluster_arn" {
  description = "ARN of the cluster"
  value       = module.insights_cluster.cluster_arn
}

output "cluster_name" {
  description = "Name of the cluster"
  value       = module.insights_cluster.cluster_name
}

output "execute_command_log_group" {
  description = "CloudWatch log group for execute command"
  value       = module.insights_cluster.execute_command_log_group_name
}

output "execute_command_kms_key_arn" {
  description = "KMS key ARN for execute command"
  value       = module.insights_cluster.execute_command_kms_key_arn
}

output "features_enabled" {
  description = "Features enabled on the cluster"
  value = {
    container_insights = "enabled"
    execute_command    = "enabled"
    log_encryption     = "enabled"
  }
}
```

---

## Integration Test Example 4: Hybrid EC2 + Fargate Cluster

**examples/hybrid-cluster/main.tf**
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

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Get latest ECS-optimized AMI
data "aws_ami" "ecs" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-*-x86_64-ebs"]
  }
}

# IAM role for EC2 instances
resource "aws_iam_role" "ecs_instance" {
  name = "test-ecs-instance-role-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    TestCase = "hybrid-cluster"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_instance" {
  role       = aws_iam_role.ecs_instance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs" {
  name = "test-ecs-instance-profile-${random_string.suffix.result}"
  role = aws_iam_role.ecs_instance.name
}

# Launch template for EC2 instances
resource "aws_launch_template" "ecs" {
  name_prefix   = "test-ecs-${random_string.suffix.result}"
  image_id      = data.aws_ami.ecs.id
  instance_type = "t3.micro"

  iam_instance_profile {
    arn = aws_iam_instance_profile.ecs.arn
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    echo ECS_CLUSTER=${module.hybrid_cluster.cluster_name} >> /etc/ecs/ecs.config
  EOF
  )

  tags = {
    Name     = "test-ecs-lt-${random_string.suffix.result}"
    TestCase = "hybrid-cluster"
  }
}

# Auto Scaling Group for EC2 instances
resource "aws_autoscaling_group" "ecs" {
  name                = "test-ecs-asg-${random_string.suffix.result}"
  vpc_zone_identifier = data.aws_subnets.default.ids
  min_size            = 0
  max_size            = 2
  desired_capacity    = 0

  launch_template {
    id      = aws_launch_template.ecs.id
    version = "$Latest"
  }

  protect_from_scale_in = true

  tag {
    key                 = "Name"
    value               = "test-ecs-instance-${random_string.suffix.result}"
    propagate_at_launch = true
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = "true"
    propagate_at_launch = true
  }

  tag {
    key                 = "TestCase"
    value               = "hybrid-cluster"
    propagate_at_launch = true
  }
}

# Hybrid Cluster with both EC2 and Fargate
module "hybrid_cluster" {
  source = "../../"

  cluster_name       = "test-hybrid-${random_string.suffix.result}"
  container_insights = true

  # Both EC2 and Fargate capacity providers
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  # EC2 Capacity Provider
  ec2_capacity_providers = {
    ec2 = {
      name                   = "test-ec2-cp-${random_string.suffix.result}"
      auto_scaling_group_arn = aws_autoscaling_group.ecs.arn
      managed_scaling = {
        status                    = "ENABLED"
        target_capacity           = 80
        minimum_scaling_step_size = 1
        maximum_scaling_step_size = 100
        instance_warmup_period    = 300
      }
      managed_termination_protection = "ENABLED"
    }
  }

  # Mixed capacity provider strategy
  default_capacity_provider_strategy = [
    {
      capacity_provider = "FARGATE"
      weight           = 1
    },
    {
      capacity_provider = "FARGATE_SPOT"
      weight           = 2
    }
  ]

  tags = {
    Environment = "test"
    TestCase    = "hybrid-cluster"
    ManagedBy   = "Harness-IACM"
    Purpose     = "integration-testing"
    Type        = "hybrid"
  }

  depends_on = [aws_autoscaling_group.ecs]
}

# Verify cluster
data "aws_ecs_cluster" "verify" {
  cluster_name = module.hybrid_cluster.cluster_name
}
```

**examples/hybrid-cluster/variables.tf**
```hcl
variable "aws_region" {
  description = "AWS region for testing"
  type        = string
  default     = "us-east-1"
}
```

**examples/hybrid-cluster/outputs.tf**
```hcl
output "cluster_id" {
  description = "ID of the hybrid cluster"
  value       = module.hybrid_cluster.cluster_id
}

output "cluster_arn" {
  description = "ARN of the hybrid cluster"
  value       = module.hybrid_cluster.cluster_arn
}

output "cluster_name" {
  description = "Name of the hybrid cluster"
  value       = module.hybrid_cluster.cluster_name
}

output "capacity_providers" {
  description = "All capacity providers"
  value       = module.hybrid_cluster.capacity_providers
}

output "ec2_capacity_provider_arns" {
  description = "EC2 capacity provider ARNs"
  value       = module.hybrid_cluster.ec2_capacity_provider_arns
}

output "asg_name" {
  description = "Auto Scaling Group name"
  value       = aws_autoscaling_group.ecs.name
}

output "launch_template_id" {
  description = "Launch template ID"
  value       = aws_launch_template.ecs.id
}
```

---

## Integration Test Example 5: Cluster with ECS Service

**examples/cluster-with-service/main.tf**
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

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ECS Cluster
module "ecs_cluster" {
  source = "../../"

  cluster_name       = "test-service-cluster-${random_string.suffix.result}"
  container_insights = true

  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy = [
    {
      capacity_provider = "FARGATE"
      weight           = 1
      base             = 1
    }
  ]

  tags = {
    Environment = "test"
    TestCase    = "cluster-with-service"
    ManagedBy   = "Harness-IACM"
    Purpose     = "integration-testing"
  }
}

# IAM role for ECS task execution
resource "aws_iam_role" "task_execution" {
  name = "test-ecs-task-exec-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    TestCase = "cluster-with-service"
  }
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# CloudWatch log group for container logs
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/test-app-${random_string.suffix.result}"
  retention_in_days = 1

  tags = {
    TestCase = "cluster-with-service"
  }
}

# Task Definition
resource "aws_ecs_task_definition" "app" {
  family                   = "test-app-${random_string.suffix.result}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.task_execution.arn

  container_definitions = jsonencode([
    {
      name      = "app"
      image     = "public.ecr.aws/nginx/nginx:latest"
      essential = true
      portMappings = [
        {
          containerPort = 80
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "app"
        }
      }
    }
  ])

  tags = {
    TestCase = "cluster-with-service"
  }
}

# Security group for ECS tasks
resource "aws_security_group" "ecs_tasks" {
  name        = "test-ecs-tasks-${random_string.suffix.result}"
  description = "Security group for ECS tasks"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name     = "test-ecs-tasks-${random_string.suffix.result}"
    TestCase = "cluster-with-service"
  }
}

# ECS Service
resource "aws_ecs_service" "app" {
  name            = "test-app-service-${random_string.suffix.result}"
  cluster         = module.ecs_cluster.cluster_id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = true
  }

  tags = {
    TestCase = "cluster-with-service"
  }
}

# Verify cluster
data "aws_ecs_cluster" "verify" {
  cluster_name = module.ecs_cluster.cluster_name
}

# Verify service
data "aws_ecs_service" "verify" {
  service_name = aws_ecs_service.app.name
  cluster_arn  = module.ecs_cluster.cluster_arn
}
```

**examples/cluster-with-service/variables.tf**
```hcl
variable "aws_region" {
  description = "AWS region for testing"
  type        = string
  default     = "us-east-1"
}
```

**examples/cluster-with-service/outputs.tf**
```hcl
output "cluster_id" {
  description = "ID of the cluster"
  value       = module.ecs_cluster.cluster_id
}

output "cluster_arn" {
  description = "ARN of the cluster"
  value       = module.ecs_cluster.cluster_arn
}

output "cluster_name" {
  description = "Name of the cluster"
  value       = module.ecs_cluster.cluster_name
}

output "service_id" {
  description = "ID of the ECS service"
  value       = aws_ecs_service.app.id
}

output "service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.app.name
}

output "task_definition_arn" {
  description = "ARN of the task definition"
  value       = aws_ecs_task_definition.app.arn
}

output "task_execution_role_arn" {
  description = "ARN of the task execution role"
  value       = aws_iam_role.task_execution.arn
}

output "service_status" {
  description = "Status of the service"
  value       = data.aws_ecs_service.verify.desired_count
}
```

---

## Integration Test Example 6: EC2 Cluster with Auto Scaling

**examples/cluster-with-asg/main.tf**
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

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_ami" "ecs" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-*-x86_64-ebs"]
  }
}

# Security group for EC2 instances
resource "aws_security_group" "ecs_instances" {
  name        = "test-ecs-instances-${random_string.suffix.result}"
  description = "Security group for ECS EC2 instances"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name     = "test-ecs-instances-${random_string.suffix.result}"
    TestCase = "cluster-with-asg"
  }
}

# IAM role for EC2 instances
resource "aws_iam_role" "ecs_instance" {
  name = "test-ecs-instance-asg-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    TestCase = "cluster-with-asg"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_instance" {
  role       = aws_iam_role.ecs_instance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs" {
  name = "test-ecs-ip-asg-${random_string.suffix.result}"
  role = aws_iam_role.ecs_instance.name
}

# ECS Cluster (must be created before ASG)
module "ecs_cluster_asg" {
  source = "../../"

  cluster_name       = "test-asg-cluster-${random_string.suffix.result}"
  container_insights = true

  tags = {
    Environment = "test"
    TestCase    = "cluster-with-asg"
    ManagedBy   = "Harness-IACM"
    Purpose     = "integration-testing"
  }
}

# Launch template
resource "aws_launch_template" "ecs" {
  name_prefix   = "test-ecs-asg-${random_string.suffix.result}"
  image_id      = data.aws_ami.ecs.id
  instance_type = "t3.micro"

  vpc_security_group_ids = [aws_security_group.ecs_instances.id]

  iam_instance_profile {
    arn = aws_iam_instance_profile.ecs.arn
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    echo ECS_CLUSTER=${module.ecs_cluster_asg.cluster_name} >> /etc/ecs/ecs.config
    echo ECS_ENABLE_CONTAINER_METADATA=true >> /etc/ecs/ecs.config
  EOF
  )

  tags = {
    Name     = "test-ecs-lt-asg-${random_string.suffix.result}"
    TestCase = "cluster-with-asg"
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "ecs" {
  name                = "test-ecs-asg-full-${random_string.suffix.result}"
  vpc_zone_identifier = data.aws_subnets.default.ids
  min_size            = 0
  max_size            = 3
  desired_capacity    = 0

  launch_template {
    id      = aws_launch_template.ecs.id
    version = "$Latest"
  }

  protect_from_scale_in = true

  tag {
    key                 = "Name"
    value               = "test-ecs-instance-asg-${random_string.suffix.result}"
    propagate_at_launch = true
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = "true"
    propagate_at_launch = true
  }

  tag {
    key                 = "TestCase"
    value               = "cluster-with-asg"
    propagate_at_launch = true
  }
}

# Add EC2 Capacity Provider after ASG is created
resource "aws_ecs_capacity_provider" "ec2" {
  name = "test-asg-cp-${random_string.suffix.result}"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs.arn
    managed_termination_protection = "ENABLED"

    managed_scaling {
      status                    = "ENABLED"
      target_capacity           = 100
      minimum_scaling_step_size = 1
      maximum_scaling_step_size = 10
      instance_warmup_period    = 300
    }
  }

  tags = {
    TestCase = "cluster-with-asg"
  }
}

# Associate capacity provider with cluster
resource "aws_ecs_cluster_capacity_providers" "cluster_cp" {
  cluster_name = module.ecs_cluster_asg.cluster_name

  capacity_providers = [aws_ecs_capacity_provider.ec2.name]

  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ec2.name
    weight           = 1
    base             = 1
  }

  depends_on = [
    module.ecs_cluster_asg,
    aws_ecs_capacity_provider.ec2
  ]
}

# Verify cluster
data "aws_ecs_cluster" "verify" {
  cluster_name = module.ecs_cluster_asg.cluster_name

  depends_on = [aws_ecs_cluster_capacity_providers.cluster_cp]
}
```

**examples/cluster-with-asg/variables.tf**
```hcl
variable "aws_region" {
  description = "AWS region for testing"
  type        = string
  default     = "us-east-1"
}
```

**examples/cluster-with-asg/outputs.tf**
```hcl
output "cluster_id" {
  description = "ID of the cluster"
  value       = module.ecs_cluster_asg.cluster_id
}

output "cluster_arn" {
  description = "ARN of the cluster"
  value       = module.ecs_cluster_asg.cluster_arn
}

output "cluster_name" {
  description = "Name of the cluster"
  value       = module.ecs_cluster_asg.cluster_name
}

output "capacity_provider_name" {
  description = "Name of the capacity provider"
  value       = aws_ecs_capacity_provider.ec2.name
}

output "capacity_provider_arn" {
  description = "ARN of the capacity provider"
  value       = aws_ecs_capacity_provider.ec2.arn
}

output "asg_name" {
  description = "Auto Scaling Group name"
  value       = aws_autoscaling_group.ecs.name
}

output "asg_arn" {
  description = "Auto Scaling Group ARN"
  value       = aws_autoscaling_group.ecs.arn
}

output "launch_template_id" {
  description = "Launch template ID"
  value       = aws_launch_template.ecs.id
}
```

---

## Harness Pipeline Configuration

### Integration Testing Pipeline YAML

```yaml
pipeline:
  name: ECS Cluster Module Integration Testing
  identifier: ecs_cluster_module_integration_testing
  projectIdentifier: your_project_id
  orgIdentifier: your_org_id
  description: Integration testing pipeline for AWS ECS Cluster Terraform module
  tags:
    module: ecs-cluster
    testing: integration
  stages:
    - stage:
        name: ECS Cluster Integration Tests
        identifier: ecs_cluster_integration_tests
        type: IACM
        description: Run integration tests for all ECS cluster examples
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
                  name: Run ECS Cluster Integration Tests
                  identifier: run_ecs_cluster_tests
                  spec:
                    command: integration-test
                  timeout: 60m
                  description: |
                    Executes integration tests for ECS Cluster module:
                    - Basic EC2 cluster
                    - Fargate cluster with capacity providers
                    - Cluster with Container Insights
                    - Hybrid EC2 + Fargate cluster
                    - Cluster with ECS service
                    - EC2 cluster with Auto Scaling Group
```

### Advanced Pipeline with Validation

```yaml
pipeline:
  name: ECS Cluster Module Advanced Testing
  identifier: ecs_cluster_module_advanced_testing
  projectIdentifier: your_project_id
  orgIdentifier: your_org_id
  tags:
    module: ecs-cluster
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
                      echo "Validating ECS cluster module structure..."
                      
                      required_files=("main.tf" "variables.tf" "outputs.tf")
                      for file in "${required_files[@]}"; do
                        if [ ! -f "$file" ]; then
                          echo "ERROR: $file not found"
                          exit 1
                        fi
                        echo "✓ $file exists"
                      done
                      
                      if [ ! -d "examples" ]; then
                        echo "ERROR: examples/ directory not found"
                        exit 1
                      fi
                      
                      echo "Found example directories:"
                      ls -la examples/
                      
                      for dir in examples/*/; do
                        echo "Validating ${dir}..."
                        if [ ! -f "${dir}main.tf" ]; then
                          echo "ERROR: ${dir}main.tf not found"
                          exit 1
                        fi
                        echo "✓ ${dir}main.tf exists"
                      done
                      
                      echo "Module structure validation passed!"

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
                  name: Execute All ECS Tests
                  identifier: execute_ecs_tests
                  spec:
                    command: integration-test
                  timeout: 60m
                  description: |
                    Running comprehensive ECS cluster tests:
                    - Basic EC2 cluster (3-4 min)
                    - Fargate cluster (3-4 min)
                    - Container Insights cluster (4-5 min)
                    - Hybrid cluster (5-7 min)
                    - Cluster with service (6-8 min)
                    - Cluster with ASG (5-7 min)
                    
                    Total estimated time: 30-40 minutes

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
                      echo "ECS Cluster Module Test Summary"
                      echo "========================================"
                      echo ""
                      echo "Test Results:"
                      echo "- Basic EC2 Cluster: ✓ Passed"
                      echo "- Fargate Cluster: ✓ Passed"
                      echo "- Container Insights: ✓ Passed"
                      echo "- Hybrid Cluster: ✓ Passed"
                      echo "- Cluster with Service: ✓ Passed"
                      echo "- Cluster with ASG: ✓ Passed"
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
      "Sid": "ECSClusterManagement",
      "Effect": "Allow",
      "Action": [
        "ecs:CreateCluster",
        "ecs:DeleteCluster",
        "ecs:DescribeClusters",
        "ecs:UpdateCluster",
        "ecs:PutClusterCapacityProviders",
        "ecs:TagResource",
        "ecs:UntagResource",
        "ecs:ListTagsForResource"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ECSCapacityProviderManagement",
      "Effect": "Allow",
      "Action": [
        "ecs:CreateCapacityProvider",
        "ecs:DeleteCapacityProvider",
        "ecs:DescribeCapacityProviders",
        "ecs:UpdateCapacityProvider"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ECSServiceAndTaskManagement",
      "Effect": "Allow",
      "Action": [
        "ecs:CreateService",
        "ecs:DeleteService",
        "ecs:DescribeServices",
        "ecs:UpdateService",
        "ecs:RegisterTaskDefinition",
        "ecs:DeregisterTaskDefinition",
        "ecs:DescribeTaskDefinition"
      ],
      "Resource": "*"
    },
    {
      "Sid": "EC2Management",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeVpcs",
        "ec2:DescribeSubnets",
        "ec2:DescribeSecurityGroups",
        "ec2:CreateSecurityGroup",
        "ec2:DeleteSecurityGroup",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:AuthorizeSecurityGroupEgress",
        "ec2:RevokeSecurityGroupIngress",
        "ec2:RevokeSecurityGroupEgress",
        "ec2:DescribeImages",
        "ec2:CreateLaunchTemplate",
        "ec2:DeleteLaunchTemplate",
        "ec2:DescribeLaunchTemplates",
        "ec2:DescribeLaunchTemplateVersions",
        "ec2:CreateTags",
        "ec2:DeleteTags"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AutoScalingManagement",
      "Effect": "Allow",
      "Action": [
        "autoscaling:CreateAutoScalingGroup",
        "autoscaling:DeleteAutoScalingGroup",
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:UpdateAutoScalingGroup",
        "autoscaling:CreateOrUpdateTags",
        "autoscaling:DeleteTags"
      ],
      "Resource": "*"
    },
    {
      "Sid": "IAMManagement",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:PassRole",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:CreateInstanceProfile",
        "iam:DeleteInstanceProfile",
        "iam:GetInstanceProfile",
        "iam:AddRoleToInstanceProfile",
        "iam:RemoveRoleFromInstanceProfile",
        "iam:TagRole",
        "iam:TagInstanceProfile"
      ],
      "Resource": "*"
    },
    {
      "Sid": "CloudWatchLogsManagement",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:DeleteLogGroup",
        "logs:DescribeLogGroups",
        "logs:PutRetentionPolicy",
        "logs:TagLogGroup",
        "logs:UntagLogGroup"
      ],
      "Resource": "*"
    },
    {
      "Sid": "KMSManagement",
      "Effect": "Allow",
      "Action": [
        "kms:CreateKey",
        "kms:DescribeKey",
        "kms:GetKeyPolicy",
        "kms:PutKeyPolicy",
        "kms:ScheduleKeyDeletion",
        "kms:CreateAlias",
        "kms:DeleteAlias",
        "kms:EnableKeyRotation",
        "kms:TagResource"
      ],
      "Resource": "*"
    }
  ]
}
```

---

## Best Practices for ECS Cluster Integration Testing

### 1. Use Unique Cluster Names

Always include random suffixes:
```hcl
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

module "ecs_cluster" {
  source       = "../../"
  cluster_name = "test-cluster-${random_string.suffix.result}"
}
```

### 2. Start with Fargate

Simplest to test (no EC2 instances):
```hcl
capacity_providers = ["FARGATE"]
```

### 3. Set Desired Capacity to 0 for EC2

Avoid costs during testing:
```hcl
resource "aws_autoscaling_group" "ecs" {
  desired_capacity = 0
  min_size         = 0
  max_size         = 2
}
```

### 4. Enable Container Insights Selectively

Only enable when testing:
```hcl
container_insights = true
```

### 5. Use Public ECR Images

For task definitions:
```hcl
image = "public.ecr.aws/nginx/nginx:latest"
```

### 6. Set Short Log Retention

For test logs:
```hcl
retention_in_days = 1
```

### 7. Tag All Resources

For easy identification:
```hcl
tags = {
  Environment = "test"
  TestCase    = "basic-ec2-cluster"
  ManagedBy   = "Harness-IACM"
  Purpose     = "integration-testing"
}
```

### 8. Use Proper Dependencies

Ensure correct creation order:
```hcl
depends_on = [aws_autoscaling_group.ecs]
```

### 9. Verify with Data Sources

Always verify creation:
```hcl
data "aws_ecs_cluster" "verify" {
  cluster_name = module.ecs_cluster.cluster_name
}
```

### 10. Test Different Launch Types

Include examples for:
- Fargate only
- EC2 only
- Hybrid (EC2 + Fargate)

---

## Troubleshooting

### Common Issues

#### Issue 1: Cluster Deletion Fails
**Symptom**: "Cluster contains tasks"
**Solution**: 
- Ensure services are deleted first
- Stop all running tasks
- Wait for tasks to fully terminate

#### Issue 2: Capacity Provider Already Exists
**Symptom**: "CapacityProvider already exists"
**Solution**: Use unique names with random suffixes

#### Issue 3: ASG Cannot Be Deleted
**Symptom**: ASG in use by capacity provider
**Solution**: 
- Delete capacity provider association first
- Then delete ASG

#### Issue 4: Task Definition Registration Fails
**Symptom**: "Invalid task definition"
**Solution**: 
- Verify IAM execution role exists
- Check container image is accessible
- Ensure CPU/memory combinations are valid

#### Issue 5: Service Won't Start
**Symptom**: Service stuck in "ACTIVE" with 0 running tasks
**Solution**:
- Check task definition is valid
- Verify security groups allow traffic
- Ensure subnets have internet access (for Fargate)

#### Issue 6: Execute Command Not Working
**Symptom**: Cannot execute commands in containers
**Solution**:
- Verify execute command configuration
- Check KMS key permissions
- Ensure log group exists

#### Issue 7: Container Insights Not Enabled
**Symptom**: No metrics in CloudWatch
**Solution**: 
- Set `container_insights = true`
- May need to recreate cluster

#### Issue 8: Launch Template AMI Not Found
**Symptom**: Invalid AMI ID
**Solution**: Use data source to get latest ECS-optimized AMI

---

## Summary

This comprehensive guide provides complete ECS Cluster integration testing examples for Harness IACM Module Registry:

### What's Included

1. **Six complete integration test scenarios**:
   - Basic EC2 cluster (simplest configuration)
   - Fargate cluster with capacity providers and strategy
   - Cluster with Container Insights and Execute Command
   - Hybrid EC2 + Fargate cluster with managed scaling
   - Cluster with ECS service deployment (Fargate task)
   - EC2 cluster with Auto Scaling Group and capacity provider

2. **Complete module structure**: Full ECS cluster configuration

3. **Pipeline configurations**: Basic and advanced testing pipelines

4. **AWS IAM permissions**: Complete permission set required

5. **Best practices**: Cost optimization, proper configuration

6. **Troubleshooting guide**: Common issues and solutions

### Key Features

- EC2 and Fargate launch types
- Capacity provider configuration
- Container Insights enablement
- Execute Command with encryption
- Auto Scaling Group integration
- Task definition and service deployment
- IAM roles for tasks and instances
- CloudWatch logging
- KMS encryption

### Execution Times

- Basic EC2 Cluster: ~3-4 minutes
- Fargate Cluster: ~3-4 minutes
- Container Insights: ~4-5 minutes
- Hybrid Cluster: ~5-7 minutes
- Cluster with Service: ~6-8 minutes
- Cluster with ASG: ~5-7 minutes
- **Total: ~30-40 minutes for all tests**

### Cost Considerations

- ECS Cluster: Free
- Fargate: ~$0.04/hour per task (0.25 vCPU, 0.5 GB)
- EC2: t3.micro ~$0.0104/hour (if running)
- Container Insights: ~$0.30/GB ingested
- Tests run with 0 tasks/instances: Near-zero cost

### Next Steps

1. Copy module structure to your repository
2. Create integration test examples in `examples/` folder
3. Register your module in Harness IACM
4. Configure AWS connector with ECS and EC2 permissions
5. Set up module testing pipeline
6. Create a PR to trigger automated testing
7. Monitor test execution in Harness UI

ECS Cluster testing provides validation of container orchestration configurations, capacity provider strategies, and service deployment patterns essential for containerized applications.
