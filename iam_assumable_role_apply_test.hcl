
variables {
  aws_region = "us-east-1"
  test_prefix = "test-iam-assumable"
  environment = "test"
  timestamp = formatdate("YYYYMMDDhhmmss", timestamp())
}

run "create_basic_assumable_role" {
  command = apply

  variables {
    role_name        = "${var.test_prefix}-basic-${var.timestamp}"
    role_description = "Test IAM assumable role"
    
    trusted_role_arns = [
      "arn:aws:iam::123456789012:role/TrustedRole"
    ]
    
    max_session_duration = 3600
    
    tags = {
      Environment = var.environment
      ManagedBy   = "Terraform"
      TestType    = "Integration"
    }
  }

  assert {
    condition     = output.role_arn != ""
    error_message = "Role ARN must not be empty"
  }

  assert {
    condition     = output.role_name == "${var.test_prefix}-basic-${var.timestamp}"
    error_message = "Role name does not match expected value"
  }
}

run "create_role_with_managed_policies" {
  command = apply

  variables {
    role_name        = "${var.test_prefix}-managed-${var.timestamp}"
    role_description = "Test role with managed policies"
    
    trusted_role_arns = [
      "arn:aws:iam::123456789012:role/TrustedRole"
    ]
    
    managed_policy_arns = [
      "arn:aws:iam::aws:policy/ReadOnlyAccess",
      "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
    ]
    
    tags = {
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }

  assert {
    condition     = output.role_arn != ""
    error_message = "Role with managed policies must be created"
  }
}

run "create_role_with_inline_policy" {
  command = apply

  variables {
    role_name        = "${var.test_prefix}-inline-${var.timestamp}"
    role_description = "Test role with inline policy"
    
    trusted_role_arns = [
      "arn:aws:iam::123456789012:role/TrustedRole"
    ]
    
    inline_policy_name = "TestInlinePolicy"
    
    inline_policy_statements = [
      {
        effect = "Allow"
        actions = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        resources = [
          "arn:aws:s3:::test-bucket/*",
          "arn:aws:s3:::test-bucket"
        ]
      }
    ]
    
    tags = {
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }

  assert {
    condition     = output.role_arn != ""
    error_message = "Role with inline policy must be created"
  }
}

run "create_cross_account_role" {
  command = apply

  variables {
    role_name        = "${var.test_prefix}-xacct-${var.timestamp}"
    role_description = "Test cross-account assumable role"
    
    trusted_account_ids = [
      "123456789012",
      "210987654321"
    ]
    
    require_mfa          = true
    max_session_duration = 7200
    
    tags = {
      Environment = var.environment
      ManagedBy   = "Terraform"
      AccessType  = "CrossAccount"
    }
  }

  assert {
    condition     = output.role_arn != ""
    error_message = "Cross-account role must be created"
  }

  assert {
    condition     = output.max_session_duration == 7200
    error_message = "Max session duration should be 7200"
  }
}

run "create_role_with_external_id" {
  command = apply

  variables {
    role_name        = "${var.test_prefix}-extid-${var.timestamp}"
    role_description = "Test role with external ID condition"
    
    trusted_role_arns = [
      "arn:aws:iam::123456789012:role/TrustedRole"
    ]
    
    external_id = "unique-external-id-12345"
    
    tags = {
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }

  assert {
    condition     = output.role_arn != ""
    error_message = "Role with external ID must be created"
  }
}

run "create_role_with_conditions" {
  command = apply

  variables {
    role_name        = "${var.test_prefix}-cond-${var.timestamp}"
    role_description = "Test role with trust policy conditions"
    
    trusted_role_arns = [
      "arn:aws:iam::123456789012:role/TrustedRole"
    ]
    
    assume_role_conditions = [
      {
        test     = "StringEquals"
        variable = "sts:ExternalId"
        values   = ["test-external-id"]
      },
      {
        test     = "IpAddress"
        variable = "aws:SourceIp"
        values   = ["203.0.113.0/24", "198.51.100.0/24"]
      }
    ]
    
    tags = {
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }

  assert {
    condition     = output.role_arn != ""
    error_message = "Role with conditions must be created"
  }
}

run "create_service_role" {
  command = apply

  variables {
    role_name        = "${var.test_prefix}-service-${var.timestamp}"
    role_description = "Test service role for AWS services"
    role_path        = "/service-roles/"
    
    trusted_services = [
      "lambda.amazonaws.com",
      "ecs-tasks.amazonaws.com"
    ]
    
    managed_policy_arns = [
      "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
    ]
    
    tags = {
      Environment = var.environment
      ManagedBy   = "Terraform"
      RoleType    = "Service"
    }
  }

  assert {
    condition     = output.role_arn != ""
    error_message = "Service role must be created"
  }

  assert {
    condition     = output.role_path == "/service-roles/"
    error_message = "Role path should be /service-roles/"
  }
}

run "create_role_with_permissions_boundary" {
  command = apply

  variables {
    role_name        = "${var.test_prefix}-boundary-${var.timestamp}"
    role_description = "Test role with permissions boundary"
    
    trusted_role_arns = [
      "arn:aws:iam::123456789012:role/TrustedRole"
    ]
    
    permissions_boundary_arn = "arn:aws:iam::123456789012:policy/PermissionsBoundary"
    
    managed_policy_arns = [
      "arn:aws:iam::aws:policy/PowerUserAccess"
    ]
    
    tags = {
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }

  assert {
    condition     = output.role_arn != ""
    error_message = "Role with permissions boundary must be created"
  }

  assert {
    condition     = output.permissions_boundary_arn != ""
    error_message = "Permissions boundary should be attached"
  }
}

run "create_role_with_session_tags" {
  command = apply

  variables {
    role_name        = "${var.test_prefix}-session-${var.timestamp}"
    role_description = "Test role with session tag requirements"
    
    trusted_role_arns = [
      "arn:aws:iam::123456789012:role/TrustedRole"
    ]
    
    force_mfa           = true
    max_session_duration = 3600
    
    session_tag_keys = ["Project", "CostCenter"]
    
    tags = {
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }

  assert {
    condition     = output.role_arn != ""
    error_message = "Role with session tags must be created"
  }
}
