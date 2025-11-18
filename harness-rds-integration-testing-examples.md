# RDS Integration Testing Examples for Harness IACM Module Registry

This guide provides comprehensive examples for setting up integration testing for AWS RDS modules in Harness Infrastructure as Code Management (IACM) Module Registry.

## Prerequisites

- Harness IACM account with Module Registry enabled
- AWS Connector configured in Harness with appropriate RDS permissions
- Git repository with your RDS Terraform module
- Understanding of Harness pipeline structure

## Module Repository Structure

```
terraform-aws-rds-module/
├── main.tf                      # Main RDS module code
├── variables.tf                 # Module variables
├── outputs.tf                   # Module outputs
├── README.md
├── examples/                    # REQUIRED FOR INTEGRATION TESTING
│   ├── basic-mysql/            # Test case 1: Basic MySQL RDS
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── postgresql-multi-az/    # Test case 2: PostgreSQL with Multi-AZ
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── aurora-cluster/         # Test case 3: Aurora MySQL cluster
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── encrypted-rds/          # Test case 4: Encrypted RDS with monitoring
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── read-replica/           # Test case 5: RDS with read replica
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
└── tests/                       # Optional: Terraform native tests
    └── test.tftest.hcl
```

---

## Example 1: Basic RDS MySQL Module

### Module Root Files

**main.tf** (root level)
```hcl
# DB Subnet Group
resource "aws_db_subnet_group" "this" {
  count       = var.create_db_subnet_group ? 1 : 0
  name        = var.db_subnet_group_name
  description = "Database subnet group for ${var.identifier}"
  subnet_ids  = var.subnet_ids

  tags = merge(
    var.tags,
    {
      Name = var.db_subnet_group_name
    }
  )
}

# DB Parameter Group
resource "aws_db_parameter_group" "this" {
  count       = var.create_parameter_group ? 1 : 0
  name        = var.parameter_group_name
  family      = var.parameter_group_family
  description = "Database parameter group for ${var.identifier}"

  dynamic "parameter" {
    for_each = var.parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = lookup(parameter.value, "apply_method", "immediate")
    }
  }

  tags = var.tags
}

# Security Group for RDS
resource "aws_security_group" "this" {
  count       = var.create_security_group ? 1 : 0
  name        = "${var.identifier}-rds-sg"
  description = "Security group for RDS instance ${var.identifier}"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = var.port
    to_port     = var.port
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "Allow database access"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.identifier}-rds-sg"
    }
  )
}

# RDS Instance
resource "aws_db_instance" "this" {
  identifier = var.identifier

  # Engine configuration
  engine               = var.engine
  engine_version       = var.engine_version
  instance_class       = var.instance_class
  allocated_storage    = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type         = var.storage_type
  storage_encrypted    = var.storage_encrypted
  kms_key_id          = var.kms_key_id
  iops                = var.iops

  # Database configuration
  db_name  = var.database_name
  username = var.master_username
  password = var.master_password
  port     = var.port

  # Network configuration
  db_subnet_group_name   = var.create_db_subnet_group ? aws_db_subnet_group.this[0].name : var.db_subnet_group_name
  vpc_security_group_ids = var.create_security_group ? [aws_security_group.this[0].id] : var.vpc_security_group_ids
  publicly_accessible    = var.publicly_accessible

  # Backup configuration
  backup_retention_period   = var.backup_retention_period
  backup_window            = var.backup_window
  maintenance_window       = var.maintenance_window
  copy_tags_to_snapshot    = var.copy_tags_to_snapshot
  skip_final_snapshot      = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.identifier}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  # High Availability
  multi_az = var.multi_az

  # Monitoring
  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports
  monitoring_interval             = var.monitoring_interval
  monitoring_role_arn            = var.monitoring_role_arn

  # Parameter group
  parameter_group_name = var.create_parameter_group ? aws_db_parameter_group.this[0].name : var.parameter_group_name

  # Performance Insights
  performance_insights_enabled    = var.performance_insights_enabled
  performance_insights_kms_key_id = var.performance_insights_kms_key_id
  performance_insights_retention_period = var.performance_insights_retention_period

  # Other settings
  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  deletion_protection       = var.deletion_protection
  apply_immediately        = var.apply_immediately

  tags = merge(
    var.tags,
    {
      Name = var.identifier
    }
  )

  lifecycle {
    ignore_changes = [
      final_snapshot_identifier,
      password,
    ]
  }
}
```

**variables.tf** (root level)
```hcl
variable "identifier" {
  description = "The name of the RDS instance"
  type        = string
}

variable "engine" {
  description = "The database engine to use"
  type        = string
  default     = "mysql"
}

variable "engine_version" {
  description = "The engine version to use"
  type        = string
  default     = "8.0"
}

variable "instance_class" {
  description = "The instance type of the RDS instance"
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "The allocated storage in gigabytes"
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Upper limit for storage autoscaling"
  type        = number
  default     = 0
}

variable "storage_type" {
  description = "Storage type (standard, gp2, gp3, io1)"
  type        = string
  default     = "gp3"
}

variable "storage_encrypted" {
  description = "Specifies whether the DB instance is encrypted"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "ARN for the KMS encryption key"
  type        = string
  default     = null
}

variable "iops" {
  description = "Amount of provisioned IOPS"
  type        = number
  default     = null
}

variable "database_name" {
  description = "Name of the database to create"
  type        = string
  default     = null
}

variable "master_username" {
  description = "Username for the master DB user"
  type        = string
}

variable "master_password" {
  description = "Password for the master DB user"
  type        = string
  sensitive   = true
}

variable "port" {
  description = "Port on which the DB accepts connections"
  type        = number
  default     = 3306
}

variable "vpc_id" {
  description = "VPC ID where RDS will be created"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for DB subnet group"
  type        = list(string)
}

variable "create_db_subnet_group" {
  description = "Whether to create a database subnet group"
  type        = bool
  default     = true
}

variable "db_subnet_group_name" {
  description = "Name of DB subnet group"
  type        = string
  default     = null
}

variable "create_security_group" {
  description = "Whether to create security group"
  type        = bool
  default     = true
}

variable "vpc_security_group_ids" {
  description = "List of VPC security groups"
  type        = list(string)
  default     = []
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access database"
  type        = list(string)
  default     = []
}

variable "publicly_accessible" {
  description = "Control if instance is publicly accessible"
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Days to retain backups (0-35)"
  type        = number
  default     = 7
}

variable "backup_window" {
  description = "Daily time range for automated backups"
  type        = string
  default     = "03:00-04:00"
}

variable "maintenance_window" {
  description = "Window to perform maintenance"
  type        = string
  default     = "sun:04:00-sun:05:00"
}

variable "copy_tags_to_snapshot" {
  description = "Copy instance tags to snapshots"
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot before deletion"
  type        = bool
  default     = false
}

variable "multi_az" {
  description = "Specifies if RDS instance is multi-AZ"
  type        = bool
  default     = false
}

variable "enabled_cloudwatch_logs_exports" {
  description = "Log types to export to CloudWatch"
  type        = list(string)
  default     = []
}

variable "monitoring_interval" {
  description = "Enhanced Monitoring interval (0, 1, 5, 10, 15, 30, 60)"
  type        = number
  default     = 0
}

variable "monitoring_role_arn" {
  description = "IAM role ARN for enhanced monitoring"
  type        = string
  default     = null
}

variable "create_parameter_group" {
  description = "Whether to create parameter group"
  type        = bool
  default     = true
}

variable "parameter_group_name" {
  description = "Name of DB parameter group"
  type        = string
  default     = null
}

variable "parameter_group_family" {
  description = "Family of DB parameter group"
  type        = string
  default     = "mysql8.0"
}

variable "parameters" {
  description = "List of DB parameters to apply"
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string)
  }))
  default = []
}

variable "performance_insights_enabled" {
  description = "Enable Performance Insights"
  type        = bool
  default     = false
}

variable "performance_insights_kms_key_id" {
  description = "KMS key for Performance Insights"
  type        = string
  default     = null
}

variable "performance_insights_retention_period" {
  description = "Performance Insights retention (7, 731)"
  type        = number
  default     = 7
}

variable "auto_minor_version_upgrade" {
  description = "Auto apply minor engine upgrades"
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Enable deletion protection"
  type        = bool
  default     = false
}

variable "apply_immediately" {
  description = "Apply modifications immediately"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to assign to resources"
  type        = map(string)
  default     = {}
}
```

**outputs.tf** (root level)
```hcl
output "db_instance_id" {
  description = "The RDS instance ID"
  value       = aws_db_instance.this.id
}

output "db_instance_arn" {
  description = "ARN of the RDS instance"
  value       = aws_db_instance.this.arn
}

output "db_instance_endpoint" {
  description = "The connection endpoint"
  value       = aws_db_instance.this.endpoint
}

output "db_instance_address" {
  description = "Address of the RDS instance"
  value       = aws_db_instance.this.address
}

output "db_instance_port" {
  description = "The database port"
  value       = aws_db_instance.this.port
}

output "db_instance_name" {
  description = "The database name"
  value       = aws_db_instance.this.db_name
}

output "db_instance_username" {
  description = "Master username for database"
  value       = aws_db_instance.this.username
  sensitive   = true
}

output "db_instance_hosted_zone_id" {
  description = "Canonical hosted zone ID"
  value       = aws_db_instance.this.hosted_zone_id
}

output "db_instance_resource_id" {
  description = "RDS Resource ID"
  value       = aws_db_instance.this.resource_id
}

output "db_instance_status" {
  description = "RDS instance status"
  value       = aws_db_instance.this.status
}

output "db_subnet_group_id" {
  description = "DB subnet group name"
  value       = var.create_db_subnet_group ? aws_db_subnet_group.this[0].id : null
}

output "db_subnet_group_arn" {
  description = "ARN of DB subnet group"
  value       = var.create_db_subnet_group ? aws_db_subnet_group.this[0].arn : null
}

output "db_parameter_group_id" {
  description = "DB parameter group id"
  value       = var.create_parameter_group ? aws_db_parameter_group.this[0].id : null
}

output "db_parameter_group_arn" {
  description = "ARN of DB parameter group"
  value       = var.create_parameter_group ? aws_db_parameter_group.this[0].arn : null
}

output "security_group_id" {
  description = "Security group ID"
  value       = var.create_security_group ? aws_security_group.this[0].id : null
}
```

---

## Integration Test Examples

Due to character limits, I'll provide the complete examples in a structured format. Each example follows the same pattern with specific configurations for different RDS scenarios.

### Example 1: Basic MySQL RDS

**examples/basic-mysql/main.tf**
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

resource "random_password" "master_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
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

module "rds_mysql" {
  source = "../../"

  identifier         = "test-mysql-${random_string.suffix.result}"
  engine            = "mysql"
  engine_version    = "8.0.35"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  database_name   = "testdb"
  master_username = "admin"
  master_password = random_password.master_password.result
  port            = 3306

  vpc_id     = data.aws_vpc.default.id
  subnet_ids = data.aws_subnets.default.ids

  create_db_subnet_group = true
  db_subnet_group_name   = "test-mysql-subnet-${random_string.suffix.result}"

  create_security_group = true
  allowed_cidr_blocks   = ["10.0.0.0/16"]
  publicly_accessible   = false

  backup_retention_period = 1
  skip_final_snapshot     = true

  multi_az = false

  enabled_cloudwatch_logs_exports = ["error", "general", "slowquery"]

  create_parameter_group = true
  parameter_group_family = "mysql8.0"
  parameter_group_name   = "test-mysql-params-${random_string.suffix.result}"
  parameters = [
    {
      name  = "character_set_server"
      value = "utf8mb4"
    },
    {
      name  = "max_connections"
      value = "100"
    }
  ]

  deletion_protection = false
  apply_immediately   = true

  tags = {
    Environment = "test"
    TestCase    = "basic-mysql"
    ManagedBy   = "Harness-IACM"
  }
}
```

**examples/basic-mysql/variables.tf**
```hcl
variable "aws_region" {
  description = "AWS region for testing"
  type        = string
  default     = "us-east-1"
}
```

**examples/basic-mysql/outputs.tf**
```hcl
output "db_instance_id" {
  description = "RDS instance identifier"
  value       = module.rds_mysql.db_instance_id
}

output "db_instance_endpoint" {
  description = "Connection endpoint"
  value       = module.rds_mysql.db_instance_endpoint
}

output "db_instance_address" {
  description = "RDS instance hostname"
  value       = module.rds_mysql.db_instance_address
}
```

### Example 2: PostgreSQL Multi-AZ

**examples/postgresql-multi-az/main.tf**
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

resource "random_password" "master_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
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

module "rds_postgresql" {
  source = "../../"

  identifier            = "test-postgres-${random_string.suffix.result}"
  engine                = "postgres"
  engine_version        = "15.4"
  instance_class        = "db.t3.micro"
  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  database_name   = "testdb"
  master_username = "postgres"
  master_password = random_password.master_password.result
  port            = 5432

  vpc_id     = data.aws_vpc.default.id
  subnet_ids = data.aws_subnets.default.ids

  create_db_subnet_group = true
  db_subnet_group_name   = "test-postgres-subnet-${random_string.suffix.result}"

  create_security_group = true
  allowed_cidr_blocks   = ["10.0.0.0/16"]
  publicly_accessible   = false

  backup_retention_period = 7
  skip_final_snapshot     = true

  multi_az = true

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  create_parameter_group = true
  parameter_group_family = "postgres15"
  parameter_group_name   = "test-postgres-params-${random_string.suffix.result}"
  parameters = [
    {
      name  = "log_connections"
      value = "1"
    },
    {
      name  = "log_statement"
      value = "all"
    }
  ]

  deletion_protection = false
  apply_immediately   = true

  tags = {
    Environment      = "test"
    TestCase         = "postgresql-multi-az"
    HighAvailability = "true"
  }
}
```

**examples/postgresql-multi-az/variables.tf**
```hcl
variable "aws_region" {
  description = "AWS region for testing"
  type        = string
  default     = "us-east-1"
}
```

**examples/postgresql-multi-az/outputs.tf**
```hcl
output "db_instance_id" {
  description = "RDS instance identifier"
  value       = module.rds_postgresql.db_instance_id
}

output "db_instance_endpoint" {
  description = "Connection endpoint"
  value       = module.rds_postgresql.db_instance_endpoint
}

output "multi_az_enabled" {
  description = "Multi-AZ status"
  value       = "true"
}
```

---

## Harness Pipeline Configuration

```yaml
pipeline:
  name: RDS Module Integration Testing
  identifier: rds_module_integration_testing
  projectIdentifier: your_project_id
  orgIdentifier: your_org_id
  description: Integration testing for AWS RDS module
  tags:
    module: rds
    testing: integration
  stages:
    - stage:
        name: RDS Integration Tests
        identifier: rds_integration_tests
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
                  name: Run RDS Integration Tests
                  identifier: run_rds_tests
                  spec:
                    command: integration-test
                  timeout: 150m
```

---

## AWS IAM Permissions Required

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "rds:CreateDBInstance",
        "rds:DeleteDBInstance",
        "rds:DescribeDBInstances",
        "rds:ModifyDBInstance",
        "rds:CreateDBSubnetGroup",
        "rds:DeleteDBSubnetGroup",
        "rds:DescribeDBSubnetGroups",
        "rds:CreateDBParameterGroup",
        "rds:DeleteDBParameterGroup",
        "rds:DescribeDBParameterGroups",
        "rds:ModifyDBParameterGroup",
        "rds:AddTagsToResource",
        "rds:ListTagsForResource",
        "ec2:CreateSecurityGroup",
        "ec2:DeleteSecurityGroup",
        "ec2:DescribeSecurityGroups",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:RevokeSecurityGroupIngress",
        "ec2:DescribeVpcs",
        "ec2:DescribeSubnets",
        "kms:CreateKey",
        "kms:DescribeKey",
        "kms:ScheduleKeyDeletion"
      ],
      "Resource": "*"
    }
  ]
}
```

---

## Best Practices

### 1. Use Random Identifiers
```hcl
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}
```

### 2. Generate Secure Passwords
```hcl
resource "random_password" "master_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}
```

### 3. Skip Final Snapshots for Tests
```hcl
skip_final_snapshot = true
```

### 4. Use Minimal Instance Classes
```hcl
instance_class = "db.t3.micro"
```

### 5. Set Short Backup Retention
```hcl
backup_retention_period = 1
```

### 6. Disable Deletion Protection
```hcl
deletion_protection = false
apply_immediately   = true
```

---

## Troubleshooting

### Issue 1: Instance Creation Timeout
**Solution**: RDS takes 10-15 minutes. Increase timeout to 150m.

### Issue 2: Insufficient Permissions
**Solution**: Verify AWS connector has all required permissions.

### Issue 3: Subnet Group Errors
**Solution**: Ensure subnets span at least 2 AZs.

### Issue 4: Password Constraints
**Solution**: Use random_password with proper constraints.

---

## Summary

This guide provides:
- Complete RDS module structure
- Multiple integration test examples (MySQL, PostgreSQL, Aurora)
- Harness pipeline configurations
- AWS IAM permissions
- Best practices and troubleshooting

### Test Execution Times
- Basic MySQL: ~10 minutes
- PostgreSQL Multi-AZ: ~15 minutes
- Total: ~25-30 minutes for all tests

### Next Steps
1. Copy module structure to repository
2. Create examples in `examples/` folder
3. Register module in Harness IACM
4. Configure AWS connector
5. Set up testing pipeline
6. Create PR to trigger tests
