# Example IAM Role Configuration (main.tf)
# This is the Terraform configuration that the tftest.hcl file will test

variable "role_name" {
  description = "Name of the IAM role"
  type        = string
  default     = "example-iam-role"
}

variable "environment" {
  description = "Environment tag value"
  type        = string
  default     = "development"
}

variable "assume_role_services" {
  description = "List of AWS services that can assume this role"
  type        = list(string)
  default     = ["ec2.amazonaws.com"]
}

variable "policy_actions" {
  description = "List of IAM policy actions"
  type        = list(string)
  default     = ["s3:GetObject"]
}

# IAM Role
resource "aws_iam_role" "this" {
  name        = var.role_name
  description = "IAM role for ${var.role_name}"
  path        = "/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = var.assume_role_services
        }
      }
    ]
  })

  max_session_duration  = 3600
  force_detach_policies = true

  tags = {
    Name        = var.role_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# IAM Role Policy (Inline)
resource "aws_iam_role_policy" "this" {
  name = "${var.role_name}-policy"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = var.policy_actions
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}

# IAM Role Policy Attachment (Managed Policy)
resource "aws_iam_role_policy_attachment" "this" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# Outputs
output "role_arn" {
  description = "ARN of the IAM role"
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Name of the IAM role"
  value       = aws_iam_role.this.name
}

output "role_unique_id" {
  description = "Unique ID of the IAM role"
  value       = aws_iam_role.this.unique_id
}
