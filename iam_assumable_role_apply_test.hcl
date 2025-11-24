provider "aws" {
  region = "us-east-1"
}

variables {
  aws_caller_identity = "current"
  aws_partition       = "current"
}

run "test_basic_assume_role_creation" {
  command = apply

  variables {
    create_role                        = true
    role_name                          = "test-assume-role-basic"
    role_sts_externalid               = ["ExternalId123"]
    trusted_role_actions              = ["sts:AssumeRole"]
    trusted_role_arns                 = ["arn:aws:iam::123456789012:root"]
    create_custom_role_trust_policy    = false
    role_requires_mfa                  = false
  }

  assert {
    condition     = length(aws_iam_role.this) > 0
    error_message = "IAM role should be created"
  }

  assert {
    condition     = aws_iam_role.this[0].name == "test-assume-role-basic"
    error_message = "IAM role name does not match expected value"
  }

  assert {
    condition     = length(aws_iam_role.this[0].assume_role_policy) > 0
    error_message = "Assume role policy should not be empty"
  }

  assert {
    condition     = can(jsondecode(aws_iam_role.this[0].assume_role_policy))
    error_message = "Assume role policy must be valid JSON"
  }
}

run "test_assume_role_with_custom_conditions" {
  command = apply

  variables {
    create_role                        = true
    role_name                          = "test-assume-role-conditions"
    role_sts_externalid               = ["ExternalId456"]
    trusted_role_actions              = ["sts:AssumeRole"]
    trusted_role_arns                 = ["arn:aws:iam::123456789012:root"]
    create_custom_role_trust_policy    = true
    role_requires_mfa                  = false
    role_requires_session_name         = true
    role_session_name                  = "testSessionName"
  }

  assert {
    condition     = length(aws_iam_role.this) > 0
    error_message = "IAM role should be created"
  }

  assert {
    condition     = aws_iam_role.this[0].name == "test-assume-role-conditions"
    error_message = "IAM role name does not match expected value"
  }

  assert {
    condition     = contains(jsondecode(aws_iam_role.this[0].assume_role_policy).Statement[*].Effect, "Allow")
    error_message = "Policy should contain Allow effect"
  }
}

run "test_assume_role_with_aws_services" {
  command = apply

  variables {
    create_role                         = true
    role_name                          = "test-assume-role-services"
    create_custom_role_trust_policy    = false
    role_requires_mfa                  = false
    trusted_role_services              = [
      "ec2.amazonaws.com",
      "lambda.amazonaws.com",
      "ecs-tasks.amazonaws.com"
    ]
  }

  assert {
    condition     = length(aws_iam_role.this) > 0
    error_message = "IAM role should be created"
  }

  assert {
    condition     = aws_iam_role.this[0].name == "test-assume-role-services"
    error_message = "IAM role name does not match expected value"
  }

  assert {
    condition     = can(regex("ec2.amazonaws.com", aws_iam_role.this[0].assume_role_policy))
    error_message = "EC2 service principal should be in assume role policy"
  }

  assert {
    condition     = can(regex("lambda.amazonaws.com", aws_iam_role.this[0].assume_role_policy))
    error_message = "Lambda service principal should be in assume role policy"
  }
}

run "test_assume_role_with_trusted_arns" {
  command = apply

  variables {
    create_role                        = true
    role_name                          = "test-assume-role-arns"
    trusted_role_arns                  = [
      "arn:aws:iam::123456789012:role/trusted-role-1"
    ]
    trusted_role_actions               = ["sts:AssumeRole"]
    create_custom_role_trust_policy    = true
    role_requires_mfa                  = true
  }

  assert {
    condition     = length(aws_iam_role.this) > 0
    error_message = "IAM role should be created"
  }

  assert {
    condition     = aws_iam_role.this[0].name == "test-assume-role-arns"
    error_message = "IAM role name does not match expected value"
  }

  assert {
    condition     = can(regex("123456789012", aws_iam_role.this[0].assume_role_policy))
    error_message = "Trusted account ID should be in assume role policy"
  }
}

run "test_data_source_assume_role_policy" {
  command = apply

  variables {
    create_role                        = true
    role_name                          = "test-assume-role-datasource"
    create_custom_role_trust_policy    = true
    role_requires_mfa                  = false
    role_sts_externalid               = ["ExternalId789"]
    trusted_role_arns                 = ["arn:aws:iam::123456789012:root"]
    trusted_role_actions              = ["sts:AssumeRole"]
  }

  assert {
    condition     = length(aws_iam_role.this) > 0
    error_message = "IAM role should be created"
  }

  assert {
    condition     = length(data.aws_iam_policy_document.assume_role) > 0
    error_message = "Data source for assume role policy should exist"
  }
}

run "test_explicit_self_role_assumption" {
  command = apply

  variables {
    create_role                     = true
    role_name                       = "test-self-assume-role"
    role_sts_externalid            = []
    create_custom_role_trust_policy = false
    role_requires_mfa               = false
    trusted_role_arns              = ["arn:aws:iam::123456789012:root"]
    trusted_role_actions           = ["sts:AssumeRole"]
  }

  assert {
    condition     = length(aws_iam_role.this) > 0
    error_message = "IAM role should be created"
  }

  assert {
    condition     = aws_iam_role.this[0].name == "test-self-assume-role"
    error_message = "IAM role name does not match expected value"
  }
}

run "test_complex_trust_policy_conditions" {
  command = apply

  variables {
    create_role                        = true
    role_name                          = "test-complex-conditions"
    trusted_role_arns                  = ["arn:aws:iam::123456789012:role/app-role"]
    trusted_role_actions               = ["sts:AssumeRole"]
    role_requires_mfa                  = true
    role_requires_session_name         = true
    role_session_name                  = "requiredSession"
    create_custom_role_trust_policy    = true
  }

  assert {
    condition     = length(aws_iam_role.this) > 0
    error_message = "IAM role should be created"
  }

  assert {
    condition     = aws_iam_role.this[0].name == "test-complex-conditions"
    error_message = "IAM role name does not match expected value"
  }

  assert {
    condition     = length(jsondecode(aws_iam_role.this[0].assume_role_policy).Statement) > 0
    error_message = "Policy should have at least one statement"
  }
}

run "test_custom_trust_policy_document" {
  command = apply

  variables {
    create_role                        = true
    role_name                          = "test-custom-trust-doc"
    create_custom_role_trust_policy    = false
    role_requires_mfa                  = false
    custom_role_trust_policy           = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Principal = {
            AWS = "arn:aws:iam::123456789012:root"
          }
          Action = "sts:AssumeRole"
          Condition = {
            StringEquals = {
              "sts:ExternalId" = "CustomExternalId"
            }
          }
        }
      ]
    })
  }

  assert {
    condition     = length(aws_iam_role.this) > 0
    error_message = "IAM role should be created"
  }

  assert {
    condition     = aws_iam_role.this[0].name == "test-custom-trust-doc"
    error_message = "IAM role name does not match expected value"
  }

  assert {
    condition     = can(regex("CustomExternalId", aws_iam_role.this[0].assume_role_policy))
    error_message = "Custom external ID should be in policy"
  }
}

run "test_aws_partition_integration" {
  command = apply

  variables {
    create_role                     = true
    role_name                       = "test-partition-integration"
    create_custom_role_trust_policy = false
    role_requires_mfa               = false
    trusted_role_arns              = ["arn:aws:iam::123456789012:root"]
    trusted_role_actions           = ["sts:AssumeRole"]
  }

  assert {
    condition     = length(aws_iam_role.this) > 0
    error_message = "IAM role should be created"
  }

  assert {
    condition     = data.aws_caller_identity.current != null
    error_message = "AWS caller identity data source should be available"
  }

  assert {
    condition     = data.aws_partition.current != null
    error_message = "AWS partition data source should be available"
  }

  assert {
    condition     = data.aws_caller_identity.current.account_id != ""
    error_message = "Account ID should not be empty"
  }
}


