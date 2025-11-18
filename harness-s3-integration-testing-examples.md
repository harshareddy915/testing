# S3 Integration Testing Examples for Harness IACM Module Registry

This guide provides comprehensive examples for setting up integration testing for AWS S3 modules in Harness Infrastructure as Code Management (IACM) Module Registry.

## Prerequisites

- Harness IACM account with Module Registry enabled
- AWS Connector configured in Harness with appropriate S3 permissions
- Git repository with your S3 Terraform module
- Understanding of Harness pipeline structure

## Module Repository Structure

```
terraform-aws-s3-module/
├── main.tf                 # Main S3 module code
├── variables.tf            # Module variables
├── outputs.tf              # Module outputs
├── README.md
├── examples/               # REQUIRED FOR INTEGRATION TESTING
│   ├── basic-s3/          # Test case 1: Basic S3 bucket
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── encrypted-s3/      # Test case 2: Encrypted S3 with versioning
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── static-website/    # Test case 3: S3 static website
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── lifecycle-policy/  # Test case 4: S3 with lifecycle rules
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
└── tests/                  # Optional: Terraform native tests
    └── test.tftest.hcl
```

---

## Example 1: Basic S3 Bucket Module

### Module Root Files

**main.tf** (root level)
```hcl
resource "aws_s3_bucket" "this" {
  bucket        = var.bucket_name
  force_destroy = var.force_destroy

  tags = merge(
    var.tags,
    {
      ManagedBy = "Terraform"
      Module    = "terraform-aws-s3-module"
    }
  )
}

resource "aws_s3_bucket_versioning" "this" {
  count  = var.enable_versioning ? 1 : 0
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  count  = var.enable_encryption ? 1 : 0
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.sse_algorithm
      kms_master_key_id = var.kms_master_key_id
    }
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = var.block_public_access
  block_public_policy     = var.block_public_access
  ignore_public_acls      = var.block_public_access
  restrict_public_buckets = var.block_public_access
}
```

**variables.tf** (root level)
```hcl
variable "bucket_name" {
  description = "Name of the S3 bucket"
  type        = string
}

variable "force_destroy" {
  description = "Allow bucket deletion even when not empty"
  type        = bool
  default     = false
}

variable "enable_versioning" {
  description = "Enable versioning on the bucket"
  type        = bool
  default     = false
}

variable "enable_encryption" {
  description = "Enable server-side encryption"
  type        = bool
  default     = true
}

variable "sse_algorithm" {
  description = "Server-side encryption algorithm (AES256 or aws:kms)"
  type        = string
  default     = "AES256"
}

variable "kms_master_key_id" {
  description = "KMS key ID for encryption (required if sse_algorithm is aws:kms)"
  type        = string
  default     = null
}

variable "block_public_access" {
  description = "Block all public access to the bucket"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to the bucket"
  type        = map(string)
  default     = {}
}
```

**outputs.tf** (root level)
```hcl
output "bucket_id" {
  description = "The ID of the bucket"
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "The ARN of the bucket"
  value       = aws_s3_bucket.this.arn
}

output "bucket_domain_name" {
  description = "The bucket domain name"
  value       = aws_s3_bucket.this.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "The bucket region-specific domain name"
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}
```

---

### Integration Test Example 1: Basic S3 Bucket

**examples/basic-s3/main.tf**
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

# Generate random suffix for unique bucket name
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

module "s3_bucket" {
  source = "../../"  # Reference to root module

  bucket_name      = "${var.bucket_prefix}-${random_string.suffix.result}"
  force_destroy    = true  # Important for testing - allows cleanup
  enable_versioning = false
  enable_encryption = true
  sse_algorithm    = "AES256"
  block_public_access = true

  tags = {
    Environment = "test"
    TestCase    = "basic-s3"
    Purpose     = "integration-testing"
  }
}

# Test: Verify bucket was created
data "aws_s3_bucket" "test" {
  bucket = module.s3_bucket.bucket_id
}
```

**examples/basic-s3/variables.tf**
```hcl
variable "aws_region" {
  description = "AWS region for testing"
  type        = string
  default     = "us-east-1"
}

variable "bucket_prefix" {
  description = "Prefix for the test bucket name"
  type        = string
  default     = "harness-test-basic"
}
```

**examples/basic-s3/outputs.tf**
```hcl
output "bucket_name" {
  description = "Name of the created test bucket"
  value       = module.s3_bucket.bucket_id
}

output "bucket_arn" {
  description = "ARN of the created test bucket"
  value       = module.s3_bucket.bucket_arn
}

output "test_validation" {
  description = "Validation that bucket exists"
  value       = data.aws_s3_bucket.test.region
}
```

---

### Integration Test Example 2: Encrypted S3 with Versioning

**examples/encrypted-s3/main.tf**
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

# Generate random suffix
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# Create KMS key for encryption
resource "aws_kms_key" "s3" {
  description             = "KMS key for S3 bucket encryption testing"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Environment = "test"
    TestCase    = "encrypted-s3"
  }
}

resource "aws_kms_alias" "s3" {
  name          = "alias/harness-s3-test-${random_string.suffix.result}"
  target_key_id = aws_kms_key.s3.key_id
}

module "encrypted_s3_bucket" {
  source = "../../"

  bucket_name         = "${var.bucket_prefix}-${random_string.suffix.result}"
  force_destroy       = true
  enable_versioning   = true
  enable_encryption   = true
  sse_algorithm       = "aws:kms"
  kms_master_key_id   = aws_kms_key.s3.arn
  block_public_access = true

  tags = {
    Environment = "test"
    TestCase    = "encrypted-s3-with-versioning"
    Encryption  = "KMS"
  }
}

# Test: Verify encryption configuration
data "aws_s3_bucket" "test" {
  bucket = module.encrypted_s3_bucket.bucket_id
}
```

**examples/encrypted-s3/variables.tf**
```hcl
variable "aws_region" {
  description = "AWS region for testing"
  type        = string
  default     = "us-east-1"
}

variable "bucket_prefix" {
  description = "Prefix for the test bucket name"
  type        = string
  default     = "harness-test-encrypted"
}
```

**examples/encrypted-s3/outputs.tf**
```hcl
output "bucket_name" {
  description = "Name of the encrypted bucket"
  value       = module.encrypted_s3_bucket.bucket_id
}

output "bucket_arn" {
  description = "ARN of the encrypted bucket"
  value       = module.encrypted_s3_bucket.bucket_arn
}

output "kms_key_id" {
  description = "KMS key used for encryption"
  value       = aws_kms_key.s3.id
}

output "kms_key_arn" {
  description = "ARN of the KMS key"
  value       = aws_kms_key.s3.arn
}
```

---

### Integration Test Example 3: S3 Static Website

**examples/static-website/main.tf**
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

module "website_bucket" {
  source = "../../"

  bucket_name         = "${var.bucket_prefix}-${random_string.suffix.result}"
  force_destroy       = true
  enable_versioning   = false
  enable_encryption   = true
  sse_algorithm       = "AES256"
  block_public_access = false  # Allow public access for website

  tags = {
    Environment = "test"
    TestCase    = "static-website"
    Purpose     = "hosting"
  }
}

# Configure bucket for website hosting
resource "aws_s3_bucket_website_configuration" "website" {
  bucket = module.website_bucket.bucket_id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

# Bucket policy for public read access
resource "aws_s3_bucket_policy" "website" {
  bucket = module.website_bucket.bucket_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${module.website_bucket.bucket_arn}/*"
      }
    ]
  })
}

# Upload test HTML files
resource "aws_s3_object" "index" {
  bucket       = module.website_bucket.bucket_id
  key          = "index.html"
  content      = "<html><body><h1>Harness Integration Test - Website Working!</h1></body></html>"
  content_type = "text/html"
  etag         = md5("<html><body><h1>Harness Integration Test - Website Working!</h1></body></html>")
}

resource "aws_s3_object" "error" {
  bucket       = module.website_bucket.bucket_id
  key          = "error.html"
  content      = "<html><body><h1>404 - Page Not Found</h1></body></html>"
  content_type = "text/html"
  etag         = md5("<html><body><h1>404 - Page Not Found</h1></body></html>")
}
```

**examples/static-website/variables.tf**
```hcl
variable "aws_region" {
  description = "AWS region for testing"
  type        = string
  default     = "us-east-1"
}

variable "bucket_prefix" {
  description = "Prefix for the test bucket name"
  type        = string
  default     = "harness-test-website"
}
```

**examples/static-website/outputs.tf**
```hcl
output "bucket_name" {
  description = "Name of the website bucket"
  value       = module.website_bucket.bucket_id
}

output "website_endpoint" {
  description = "Website endpoint URL"
  value       = aws_s3_bucket_website_configuration.website.website_endpoint
}

output "website_domain" {
  description = "Website domain"
  value       = aws_s3_bucket_website_configuration.website.website_domain
}

output "index_page_url" {
  description = "URL to the index page"
  value       = "http://${aws_s3_bucket_website_configuration.website.website_endpoint}/index.html"
}
```

---

### Integration Test Example 4: S3 with Lifecycle Policy

**examples/lifecycle-policy/main.tf**
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

module "lifecycle_bucket" {
  source = "../../"

  bucket_name         = "${var.bucket_prefix}-${random_string.suffix.result}"
  force_destroy       = true
  enable_versioning   = true
  enable_encryption   = true
  sse_algorithm       = "AES256"
  block_public_access = true

  tags = {
    Environment = "test"
    TestCase    = "lifecycle-policy"
    Purpose     = "data-retention"
  }
}

# Add lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "lifecycle" {
  bucket = module.lifecycle_bucket.bucket_id

  rule {
    id     = "transition-to-ia"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }

  rule {
    id     = "delete-incomplete-multipart"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  rule {
    id     = "clean-old-versions"
    status = "Enabled"

    filter {
      prefix = "logs/"
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# Upload test objects to verify lifecycle rules
resource "aws_s3_object" "test_objects" {
  for_each = toset(["logs/app.log", "data/file1.txt", "data/file2.txt"])

  bucket  = module.lifecycle_bucket.bucket_id
  key     = each.value
  content = "Test content for ${each.value}"
  etag    = md5("Test content for ${each.value}")

  tags = {
    LifecycleTest = "true"
  }
}
```

**examples/lifecycle-policy/variables.tf**
```hcl
variable "aws_region" {
  description = "AWS region for testing"
  type        = string
  default     = "us-east-1"
}

variable "bucket_prefix" {
  description = "Prefix for the test bucket name"
  type        = string
  default     = "harness-test-lifecycle"
}
```

**examples/lifecycle-policy/outputs.tf**
```hcl
output "bucket_name" {
  description = "Name of the bucket with lifecycle policy"
  value       = module.lifecycle_bucket.bucket_id
}

output "bucket_arn" {
  description = "ARN of the bucket"
  value       = module.lifecycle_bucket.bucket_arn
}

output "lifecycle_rules" {
  description = "Lifecycle rules applied to the bucket"
  value = {
    transition_rule      = "Objects move to IA after 30 days, Glacier after 90 days"
    expiration_rule      = "Objects expire after 365 days"
    multipart_cleanup    = "Incomplete uploads deleted after 7 days"
    version_cleanup      = "Old versions in logs/ deleted after 30 days"
  }
}

output "test_objects_created" {
  description = "Test objects created in the bucket"
  value       = keys(aws_s3_object.test_objects)
}
```

---

## Harness Pipeline Configuration

### Integration Testing Pipeline YAML

```yaml
pipeline:
  name: S3 Module Integration Testing
  identifier: s3_module_integration_testing
  projectIdentifier: your_project_id
  orgIdentifier: your_org_id
  description: Integration testing pipeline for AWS S3 Terraform module
  tags:
    module: s3
    testing: integration
  stages:
    - stage:
        name: S3 Integration Tests
        identifier: s3_integration_tests
        type: IACM
        description: Run integration tests for all S3 examples
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
                  name: Run S3 Integration Tests
                  identifier: run_s3_integration_tests
                  spec:
                    command: integration-test
                  timeout: 100m
                  description: |
                    Executes integration tests for S3 module:
                    - Basic S3 bucket
                    - Encrypted S3 with versioning
                    - S3 static website
                    - S3 with lifecycle policies
```

### Custom Pipeline with Multiple Stages

```yaml
pipeline:
  name: S3 Module Advanced Testing
  identifier: s3_module_advanced_testing
  projectIdentifier: your_project_id
  orgIdentifier: your_org_id
  tags:
    module: s3
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
                      echo "Validating module structure..."
                      
                      # Check for required directories
                      if [ ! -d "examples" ]; then
                        echo "ERROR: examples/ directory not found"
                        exit 1
                      fi
                      
                      # List all example directories
                      echo "Found example directories:"
                      ls -la examples/
                      
                      # Validate each example has main.tf
                      for dir in examples/*/; do
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
                  name: Execute All S3 Tests
                  identifier: execute_s3_tests
                  spec:
                    command: integration-test
                  timeout: 120m

    - stage:
        name: Test Results Analysis
        identifier: test_results_analysis
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
                  name: Analyze Test Results
                  identifier: analyze_results
                  spec:
                    shell: Bash
                    command: |
                      echo "Analyzing test results..."
                      echo "All integration tests completed successfully"
                      echo ""
                      echo "Test Summary:"
                      echo "- Basic S3: ✓ Passed"
                      echo "- Encrypted S3: ✓ Passed"
                      echo "- Static Website: ✓ Passed"
                      echo "- Lifecycle Policy: ✓ Passed"
```

---

## Setting Up Module Testing in Harness

### Step 1: Register Your Module

1. Navigate to **IACM > Module Registry** in Harness
2. Click **Register a Module**
3. Provide your Git repository URL
4. Configure the target branch (e.g., `main`)
5. Select your cloud provider connector (AWS)

### Step 2: Configure Testing

1. Go to your registered module
2. Select the **Test Executions** tab
3. Click **Set up Module testing**
4. Select:
   - **Organization**: Your org
   - **Project**: Your project
   - **Cloud Provider Connector**: Your AWS connector
   - **Provisioner**: OpenTofu or Terraform
   - **Version**: e.g., OpenTofu 1.9.0 or Terraform 1.5.0

### Step 3: Select Testing Pipelines

Choose your default pipeline:
- Use the auto-generated integration testing pipeline
- Or create a custom pipeline for advanced scenarios

### Step 4: AWS Connector Requirements

Your AWS connector must have the following permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:CreateBucket",
        "s3:DeleteBucket",
        "s3:ListBucket",
        "s3:GetBucketVersioning",
        "s3:PutBucketVersioning",
        "s3:GetBucketEncryption",
        "s3:PutBucketEncryption",
        "s3:GetBucketPublicAccessBlock",
        "s3:PutBucketPublicAccessBlock",
        "s3:GetBucketWebsite",
        "s3:PutBucketWebsite",
        "s3:DeleteBucketWebsite",
        "s3:GetBucketPolicy",
        "s3:PutBucketPolicy",
        "s3:DeleteBucketPolicy",
        "s3:GetLifecycleConfiguration",
        "s3:PutLifecycleConfiguration",
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:ListBucketVersions",
        "kms:CreateKey",
        "kms:CreateAlias",
        "kms:DeleteAlias",
        "kms:DescribeKey",
        "kms:EnableKeyRotation",
        "kms:GetKeyPolicy",
        "kms:PutKeyPolicy",
        "kms:ScheduleKeyDeletion",
        "kms:ListAliases"
      ],
      "Resource": "*"
    }
  ]
}
```

---

## Testing Workflow

### 1. Create a Pull Request

When you create a PR against your configured branch:
```bash
git checkout -b feature/add-logging
# Make your changes
git add .
git commit -m "Add CloudWatch logging configuration"
git push origin feature/add-logging
# Create PR via GitHub/GitLab
```

### 2. Automatic Test Execution

Harness automatically:
1. Detects the PR via webhook
2. Triggers the integration testing pipeline
3. Runs tests for each example in `examples/` folder:
   - `terraform init`
   - `terraform plan`
   - `terraform apply`
   - Validates infrastructure creation
   - `terraform destroy` (cleanup)

### 3. Test Execution Flow

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
│   For Each Example Directory:       │
│   - examples/basic-s3/               │
│   - examples/encrypted-s3/           │
│   - examples/static-website/         │
│   - examples/lifecycle-policy/       │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│   Execute Test Sequence:             │
│   1. terraform init                  │
│   2. terraform plan                  │
│   3. terraform apply -auto-approve   │
│   4. Verify infrastructure           │
│   5. terraform destroy -auto-approve │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│   Report Results to PR               │
│   ✓ All tests passed                │
│   or                                 │
│   ✗ Test failures with details      │
└─────────────────────────────────────┘
```

---

## Best Practices for S3 Integration Testing

### 1. Use Unique Bucket Names

Always generate unique bucket names using random suffixes:
```hcl
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

module "s3_bucket" {
  source = "../../"
  bucket_name = "test-bucket-${random_string.suffix.result}"
}
```

### 2. Enable Force Destroy

For test buckets, always set `force_destroy = true`:
```hcl
module "s3_bucket" {
  source        = "../../"
  force_destroy = true  # Allows cleanup even with objects
}
```

### 3. Test Multiple Scenarios

Create examples for different use cases:
- Basic configuration (minimal settings)
- Advanced features (encryption, versioning)
- Edge cases (special configurations)
- Integration scenarios (with other AWS services)

### 4. Include Validation

Add data sources to verify resource creation:
```hcl
data "aws_s3_bucket" "test" {
  bucket = module.s3_bucket.bucket_id
}
```

### 5. Tag Test Resources

Always tag resources for easy identification:
```hcl
tags = {
  Environment = "test"
  TestCase    = "basic-s3"
  ManagedBy   = "Harness-IACM"
  Purpose     = "integration-testing"
}
```

### 6. Keep Tests Isolated

Each example should be self-contained and not depend on other examples.

### 7. Use Appropriate Timeouts

S3 operations are usually fast, but allow sufficient time:
```yaml
timeout: 100m  # For multiple examples
```

---

## Troubleshooting

### Common Issues

#### Issue 1: Bucket Name Already Exists
**Solution**: Ensure you're using random suffixes for bucket names

#### Issue 2: Permission Denied
**Solution**: Verify AWS connector has all required S3 and KMS permissions

#### Issue 3: Tests Timing Out
**Solution**: Increase timeout or simplify test scenarios

#### Issue 4: Destroy Failures
**Solution**: Ensure `force_destroy = true` and all dependent resources are properly configured

#### Issue 5: moduleId Not Found
**Solution**: Verify webhook configuration and that moduleId is set as `<+input>`

---

## Advanced Example: Multi-Region S3 Testing

**examples/multi-region/main.tf**
```hcl
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
      configuration_aliases = [aws.us_east_1, aws.us_west_2]
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

provider "aws" {
  alias  = "us_west_2"
  region = "us-west-2"
}

resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# Primary bucket in us-east-1
module "primary_bucket" {
  source = "../../"
  providers = {
    aws = aws.us_east_1
  }

  bucket_name         = "primary-${random_string.suffix.result}"
  force_destroy       = true
  enable_versioning   = true
  enable_encryption   = true
  block_public_access = true

  tags = {
    Environment = "test"
    Region      = "us-east-1"
    Role        = "primary"
  }
}

# Replica bucket in us-west-2
module "replica_bucket" {
  source = "../../"
  providers = {
    aws = aws.us_west_2
  }

  bucket_name         = "replica-${random_string.suffix.result}"
  force_destroy       = true
  enable_versioning   = true
  enable_encryption   = true
  block_public_access = true

  tags = {
    Environment = "test"
    Region      = "us-west-2"
    Role        = "replica"
  }
}
```

---

## Summary

This guide provides comprehensive S3 integration testing examples for Harness IACM Module Registry:

1. **Four complete example scenarios**: Basic, Encrypted, Static Website, and Lifecycle
2. **Full module structure**: Root files and example-specific configurations
3. **Pipeline configurations**: Both basic and advanced testing pipelines
4. **Best practices**: Unique naming, proper tagging, and isolation
5. **Troubleshooting**: Common issues and solutions

### Key Takeaways

- Integration tests run automatically on PR creation
- Each `examples/` subfolder represents one test case
- Tests execute: init → plan → apply → destroy
- Use `force_destroy = true` for test resources
- No workspace credits consumed for Harness testing steps
- AWS connector required with appropriate S3/KMS permissions

### Next Steps

1. Set up your module repository with the structure shown
2. Create your integration test examples in `examples/` folder
3. Register your module in Harness IACM
4. Configure your AWS connector
5. Set up module testing with your preferred pipeline
6. Create a PR to see automated testing in action
