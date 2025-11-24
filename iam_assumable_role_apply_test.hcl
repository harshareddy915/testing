variables {
  aws_region  = "us-east-1"
  test_prefix = "test-iam-role"
  timestamp   = formatdate("YYYYMMDDhhmmss", timestamp())
}

run "create_role_with_account_trust" {
  command = apply

  variables {
    role_name        = "${var.test_prefix}-account-${var.timestamp}"
    role_description = "Test IAM role with account trust"
    
    # Trust policy configuration
    trusted_principal_type = "AWS"
    trusted_principals = [
      "arn:aws:iam::123456789012:root"
    ]
    
    require_mfa          = true
    max_session_duration = 3600
    
    tags = {
      Environment = "test"
      ManagedBy   = "Terraform"
      TestType    = "Integration"
    }
  }

  assert {
    condition     = output.role_arn != ""
    error_message = "Role ARN must not be empty"
  }

  assert {
    condition     = output.role_name == "${var.test_prefix}-account-${var.timestamp}"
    error_message = "Role name does not match expected value"
  }

  assert {
    condition     = output.assume_role_policy != ""
    error_message = "Assume role policy must not be empty"
  }
}

run "create_role_with_iam_role_trust" {
  command = apply

  variables {
    role_name        = "${var.test_prefix}-role-${var.timestamp}"
    role_description = "Test IAM role with IAM role trust"
    
    # Trust policy configuration
    trusted_principal_type = "AWS"
    trusted_principals = [
      "arn:aws:iam::123456789012:role/AdminRole",
      "arn:aws:iam::123456789012:role/DevOpsRole"
    ]
    
    require_mfa          = true
    max_session_duration = 7200
    
    tags = {
      Environment = "test"
      ManagedBy   = "Terraform"
    }
  }

  assert {
    condition     = output.role_arn != ""
    error_message = "Role with IAM role trust must be created"
  }

  assert {
    condition     = can(jsondecode(output.assume_role_policy))
    error_message = "Assume role policy must be valid JSON"
  }
}

run "create_role_without_mfa" {
  command = apply

  variables {
    role_name        = "${var.test_prefix}-nomfa-${var.timestamp}"
    role_description = "Test IAM role without MFA requirement"
    
    # Trust policy configuration
    trusted_principal_type = "AWS"
    trusted_principals = [
      "arn:aws:iam::123456789012:role/TrustedRole"
    ]
    
    require_mfa          = false
    max_session_duration = 3600
    
    tags = {
      Environment = "test"
      ManagedBy   = "Terraform"
    }
  }

  assert {
    condition     = output.role_arn != ""
    error_message = "Role without MFA must be created"
  }

  assert {
    condition     = output.role_id != ""
    error_message = "Role ID must not be empty"
  }
}

run "create_role_with_external_id" {
  command = apply

  variables {
    role_name        = "${var.test_prefix}-extid-${var.timestamp}"
    role_description = "Test IAM role with external ID"
    
    # Trust policy configuration
    trusted_principal_type = "AWS"
    trusted_principals = [
      "arn:aws:iam::123456789012:root"
    ]
    
    require_mfa  = true
    external_id  = "unique-external-id-12345"
    
    max_session_duration = 3600
    
    tags = {
      Environment = "test"
      ManagedBy   = "Terraform"
    }
  }

  assert {
    condition     = output.role_arn != ""
    error_message = "Role with external ID must be created"
  }
}

run "create_role_with_service_trust" {
  command = apply

  variables {
    role_name        = "${var.test_prefix}-service-${var.timestamp}"
    role_description = "Test IAM role with service trust"
    role_path        = "/service-roles/"
    
    # Trust policy configuration for AWS service
    trusted_principal_type = "Service"
    trusted_principals = [
      "lambda.amazonaws.com",
      "ecs-tasks.amazonaws.com"
    ]
    
    require_mfa          = false
    max_session_duration = 3600
    
    tags = {
      Environment = "test"
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

run "create_role_with_federated_trust" {
  command = apply

  variables {
    role_name        = "${var.test_prefix}-federated-${var.timestamp}"
    role_description = "Test IAM role with federated trust"
    
    # Trust policy configuration for federated access
    trusted_principal_type = "Federated"
    trusted_principals = [
      "arn:aws:iam::123456789012:saml-provider/CompanySAML"
    ]
    
    federated_conditions = [
      {
        test     = "StringEquals"
        variable = "SAML:aud"
        values   = ["https://signin.aws.amazon.com/saml"]
      }
    ]
    
    require_mfa          = false
    max_session_duration = 3600
    
    tags = {
      Environment = "test"
      ManagedBy   = "Terraform"
    }
  }

  assert {
    condition     = output.role_arn != ""
    error_message = "Federated role must be created"
  }
}

run "create_role_with_multiple_conditions" {
  command = apply

  variables {
    role_name        = "${var.test_prefix}-cond-${var.timestamp}"
    role_description = "Test IAM role with multiple conditions"
    
    # Trust policy configuration
    trusted_principal_type = "AWS"
    trusted_principals = [
      "arn:aws:iam::123456789012:role/TrustedRole"
    ]
    
    require_mfa = true
    external_id = "test-external-id"
    
    additional_conditions = [
      {
        test     = "IpAddress"
        variable = "aws:SourceIp"
        values   = ["203.0.113.0/24", "198.51.100.0/24"]
      },
      {
        test     = "StringEquals"
        variable = "aws:PrincipalOrgID"
        values   = ["o-exampleorgid"]
      }
    ]
    
    max_session_duration = 3600
    
    tags = {
      Environment = "test"
      ManagedBy   = "Terraform"
    }
  }

  assert {
    condition     = output.role_arn != ""
    error_message = "Role with multiple conditions must be created"
  }
}

run "create_role_with_permissions_boundary" {
  command = apply

  variables {
    role_name        = "${var.test_prefix}-boundary-${var.timestamp}"
    role_description = "Test IAM role with permissions boundary"
    
    # Trust policy configuration
    trusted_principal_type = "AWS"
    trusted_principals = [
      "arn:aws:iam::123456789012:role/TrustedRole"
    ]
    
    require_mfa                = true
    permissions_boundary_arn   = "arn:aws:iam::123456789012:policy/PermissionsBoundary"
    max_session_duration       = 3600
    
    tags = {
      Environment = "test"
      ManagedBy   = "Terraform"
    }
  }

  assert {
    condition     = output.role_arn != ""
    error_message = "Role with permissions boundary must be created"
  }

  assert {
    condition     = output.permissions_boundary_arn == "arn:aws:iam::123456789012:policy/PermissionsBoundary"
    error_message = "Permissions boundary ARN must match"
  }
}

run "create_role_with_custom_path" {
  command = apply

  variables {
    role_name        = "${var.test_prefix}-path-${var.timestamp}"
    role_description = "Test IAM role with custom path"
    role_path        = "/custom/path/"
    
    # Trust policy configuration
    trusted_principal_type = "AWS"
    trusted_principals = [
      "arn:aws:iam::123456789012:root"
    ]
    
    require_mfa          = true
    max_session_duration = 3600
    
    tags = {
      Environment = "test"
      ManagedBy   = "Terraform"
    }
  }

  assert {
    condition     = output.role_arn != ""
    error_message = "Role with custom path must be created"
  }

  assert {
    condition     = contains(output.role_arn, "/custom/path/")
    error_message = "Role ARN must contain custom path"
  }
}

run "create_role_with_max_session_duration" {
  command = apply

  variables {
    role_name        = "${var.test_prefix}-maxsession-${var.timestamp}"
    role_description = "Test IAM role with maximum session duration"
    
    # Trust policy configuration
    trusted_principal_type = "AWS"
    trusted_principals = [
      "arn:aws:iam::123456789012:role/TrustedRole"
    ]
    
    require_mfa          = true
    max_session_duration = 43200  # 12 hours
    
    tags = {
      Environment = "test"
      ManagedBy   = "Terraform"
    }
  }

  assert {
    condition     = output.role_arn != ""
    error_message = "Role with max session duration must be created"
  }

  assert {
    condition     = output.max_session_duration == 43200
    error_message = "Max session duration should be 43200 seconds"
  }
}

run "create_role_cross_account_with_mfa" {
  command = apply

  variables {
    role_name        = "${var.test_prefix}-xacct-mfa-${var.timestamp}"
    role_description = "Test cross-account IAM role with MFA"
    
    # Trust policy configuration for cross-account
    trusted_principal_type = "AWS"
    trusted_principals = [
      "arn:aws:iam::123456789012:root",
      "arn:aws:iam::210987654321:root"
    ]
    
    require_mfa          = true
    max_session_duration = 7200
    
    tags = {
      Environment = "test"
      ManagedBy   = "Terraform"
      AccessType  = "CrossAccount"
    }
  }

  assert {
    condition     = output.role_arn != ""
    error_message = "Cross-account role with MFA must be created"
  }

  assert {
    condition     = can(regex("Bool.*aws:MultiFactorAuthPresent", output.assume_role_policy))
    error_message = "Assume role policy must contain MFA condition"
  }
}

run "create_role_with_force_detach_policies" {
  command = apply

  variables {
    role_name        = "${var.test_prefix}-detach-${var.timestamp}"
    role_description = "Test IAM role with force detach policies"
    
    # Trust policy configuration
    trusted_principal_type = "AWS"
    trusted_principals = [
      "arn:aws:iam::123456789012:role/TrustedRole"
    ]
    
    require_mfa            = true
    force_detach_policies  = true
    max_session_duration   = 3600
    
    tags = {
      Environment = "test"
      ManagedBy   = "Terraform"
    }
  }

  assert {
    condition     = output.role_arn != ""
    error_message = "Role with force detach policies must be created"
  }
}
