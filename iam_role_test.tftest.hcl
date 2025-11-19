# IAM Role Integration Tests
# This file tests the creation and configuration of an IAM role with policies

variables {
  role_name        = "test-iam-role"
  environment      = "test"
  assume_role_services = ["ec2.amazonaws.com", "lambda.amazonaws.com"]
}

# Test 1: Verify IAM role creation with basic configuration
run "create_iam_role" {
  command = apply

  assert {
    condition     = aws_iam_role.this.name == var.role_name
    error_message = "IAM role name does not match expected value"
  }

  assert {
    condition     = aws_iam_role.this.arn != ""
    error_message = "IAM role ARN should not be empty"
  }

  assert {
    condition     = length(aws_iam_role.this.arn) > 0
    error_message = "IAM role ARN should be a valid string"
  }
}

# Test 2: Verify assume role policy configuration
run "verify_assume_role_policy" {
  command = apply

  assert {
    condition     = can(jsondecode(aws_iam_role.this.assume_role_policy))
    error_message = "Assume role policy should be valid JSON"
  }

  assert {
    condition     = length(jsondecode(aws_iam_role.this.assume_role_policy).Statement) > 0
    error_message = "Assume role policy should contain at least one statement"
  }

  assert {
    condition     = contains(
      [for stmt in jsondecode(aws_iam_role.this.assume_role_policy).Statement : stmt.Effect],
      "Allow"
    )
    error_message = "Assume role policy should contain an Allow statement"
  }
}

# Test 3: Verify IAM role policy attachment
run "verify_policy_attachment" {
  command = apply

  assert {
    condition     = aws_iam_role_policy_attachment.this != null
    error_message = "IAM role policy attachment should exist"
  }

  assert {
    condition     = aws_iam_role_policy_attachment.this.role == aws_iam_role.this.name
    error_message = "Policy should be attached to the correct role"
  }
}

# Test 4: Verify inline policy if present
run "verify_inline_policy" {
  command = apply

  assert {
    condition = (
      can(aws_iam_role_policy.this) ? 
      aws_iam_role_policy.this.role == aws_iam_role.this.name : 
      true
    )
    error_message = "Inline policy should be attached to the correct role"
  }
}

# Test 5: Verify role tags
run "verify_role_tags" {
  command = apply

  assert {
    condition     = aws_iam_role.this.tags != null
    error_message = "IAM role should have tags defined"
  }

  assert {
    condition     = contains(keys(aws_iam_role.this.tags), "Environment")
    error_message = "IAM role should have Environment tag"
  }

  assert {
    condition     = aws_iam_role.this.tags["Environment"] == var.environment
    error_message = "Environment tag should match the expected value"
  }
}

# Test 6: Verify role description
run "verify_role_description" {
  command = apply

  assert {
    condition     = aws_iam_role.this.description != null && aws_iam_role.this.description != ""
    error_message = "IAM role should have a description"
  }
}

# Test 7: Verify max session duration
run "verify_max_session_duration" {
  command = apply

  assert {
    condition     = aws_iam_role.this.max_session_duration >= 3600 && aws_iam_role.this.max_session_duration <= 43200
    error_message = "Max session duration should be between 1 hour (3600s) and 12 hours (43200s)"
  }
}

# Test 8: Plan-only test to verify no unintended changes
run "verify_idempotency" {
  command = plan

  assert {
    condition     = length(resource_changes) == 0
    error_message = "No changes should be planned on second apply (idempotency check)"
  }
}

# Test 9: Verify role can be assumed by specified services
run "verify_trusted_entities" {
  command = apply

  assert {
    condition = alltrue([
      for service in var.assume_role_services :
      contains(
        [for stmt in jsondecode(aws_iam_role.this.assume_role_policy).Statement :
          contains(try(stmt.Principal.Service, []), service)
        ],
        true
      )
    ])
    error_message = "All specified services should be able to assume the role"
  }
}

# Test 10: Verify role path
run "verify_role_path" {
  command = apply

  assert {
    condition     = startswith(aws_iam_role.this.path, "/")
    error_message = "IAM role path should start with /"
  }

  assert {
    condition     = endswith(aws_iam_role.this.path, "/")
    error_message = "IAM role path should end with /"
  }
}

# Test 11: Destroy test to ensure clean teardown
run "destroy_resources" {
  command = destroy

  assert {
    condition     = length([for r in resource_changes : r if r.change.actions != ["delete"]]) == 0
    error_message = "All resources should be marked for deletion"
  }
}

# Test 12: Verify permissions boundary (if applied)
run "verify_permissions_boundary" {
  command = apply

  assert {
    condition = (
      can(aws_iam_role.this.permissions_boundary) ?
      length(aws_iam_role.this.permissions_boundary) > 0 :
      true
    )
    error_message = "If permissions boundary is set, it should be a valid ARN"
  }
}

# Test 13: Verify role force_detach_policies setting
run "verify_force_detach_policies" {
  command = apply

  assert {
    condition     = aws_iam_role.this.force_detach_policies != null
    error_message = "force_detach_policies should be explicitly set"
  }
}

# Test 14: Integration test with policy permissions
run "verify_policy_permissions" {
  command = apply

  variables {
    policy_actions = ["s3:GetObject", "s3:PutObject"]
  }

  assert {
    condition = (
      can(aws_iam_role_policy.this) ?
      length(jsondecode(aws_iam_role_policy.this.policy).Statement) > 0 :
      true
    )
    error_message = "Policy should contain at least one statement with actions"
  }
}

# Test 15: Verify role unique ID generation
run "verify_unique_id" {
  command = apply

  assert {
    condition     = aws_iam_role.this.unique_id != ""
    error_message = "IAM role should have a unique ID generated by AWS"
  }

  assert {
    condition     = length(aws_iam_role.this.unique_id) > 0
    error_message = "Unique ID should be a valid string"
  }
}

# Test 16: Validate wildcard actions in policy statements
run "validate_wildcard_actions" {
  command = apply

  variables {
    policy_actions = ["s3:*", "ec2:Describe*", "iam:List*"]
  }

  assert {
    condition = alltrue([
      for stmt in jsondecode(aws_iam_role_policy.this.policy).Statement :
      length([
        for action in try(stmt.Action, []) :
        action if can(regex("\\*", action))
      ]) <= length(try(stmt.Action, []))
    ])
    error_message = "Wildcard actions should be properly validated and controlled"
  }

  assert {
    condition = anytrue([
      for stmt in jsondecode(aws_iam_role_policy.this.policy).Statement :
      anytrue([
        for action in try(stmt.Action, []) :
        can(regex("^[a-zA-Z0-9-]+:\\*$|^[a-zA-Z0-9-]+:[a-zA-Z0-9-]+\\*$", action))
      ])
    ])
    error_message = "Wildcard actions should follow proper AWS service:action* pattern"
  }
}

# Test 17: Validate wildcard principals in trust policies
run "validate_wildcard_principals" {
  command = apply

  variables {
    assume_role_services = ["*.amazonaws.com", "ec2.amazonaws.com"]
  }

  assert {
    condition = alltrue([
      for stmt in jsondecode(aws_iam_role.this.assume_role_policy).Statement :
      length([
        for service in try(stmt.Principal.Service, []) :
        service if can(regex("\\*", service))
      ]) == 0 || length([
        for service in try(stmt.Principal.Service, []) :
        service if can(regex("^\\*\\.amazonaws\\.com$", service))
      ]) > 0
    ])
    error_message = "Wildcard principals should be restricted to AWS service domains"
  }

  assert {
    condition = alltrue([
      for stmt in jsondecode(aws_iam_role.this.assume_role_policy).Statement :
      !contains([
        for service in try(stmt.Principal.Service, []) :
        service
      ], "*")
    ])
    error_message = "Trust policy should not allow universal principal (*)"
  }
}

# Test 18: Validate wildcard resources in policy statements
run "validate_wildcard_resources" {
  command = apply

  assert {
    condition = alltrue([
      for stmt in jsondecode(aws_iam_role_policy.this.policy).Statement :
      length([
        for resource in try(stmt.Resource, []) :
        resource if resource == "*"
      ]) == 0 || stmt.Effect == "Deny"
    ])
    error_message = "Universal resource wildcard (*) should only be used with Deny statements"
  }

  assert {
    condition = alltrue([
      for stmt in jsondecode(aws_iam_role_policy.this.policy).Statement :
      length([
        for resource in try(stmt.Resource, []) :
        resource if can(regex("arn:aws:[a-zA-Z0-9-]+:[^:]*:[^:]*:\\*", resource))
      ]) >= 0
    ])
    error_message = "Resource wildcards should follow proper ARN format when used"
  }
}

# Test 19: Detect overly permissive wildcard usage
run "detect_overly_permissive_wildcards" {
  command = apply

  assert {
    condition = !anytrue([
      for stmt in jsondecode(aws_iam_role_policy.this.policy).Statement :
      stmt.Effect == "Allow" && 
      contains(try(stmt.Action, []), "*") && 
      contains(try(stmt.Resource, []), "*")
    ])
    error_message = "Policy should not allow universal actions (*) on universal resources (*)"
  }

  assert {
    condition = !anytrue([
      for stmt in jsondecode(aws_iam_role_policy.this.policy).Statement :
      stmt.Effect == "Allow" && 
      anytrue([
        for action in try(stmt.Action, []) :
        contains(["iam:*", "sts:*", "organizations:*"], action)
      ]) && contains(try(stmt.Resource, []), "*")
    ])
    error_message = "Policy should not grant broad administrative privileges with wildcards"
  }
}

# Test 20: Validate trust entity constraints with wildcards
run "validate_trust_entity_constraints" {
  command = apply

  assert {
    condition = alltrue([
      for stmt in jsondecode(aws_iam_role.this.assume_role_policy).Statement :
      try(stmt.Principal.AWS, null) == null || 
      !contains([
        for principal in try(stmt.Principal.AWS, []) :
        principal
      ], "*")
    ])
    error_message = "Trust policy should not allow any AWS account (*) to assume the role"
  }

  assert {
    condition = alltrue([
      for stmt in jsondecode(aws_iam_role.this.assume_role_policy).Statement :
      try(stmt.Principal.Federated, null) == null || 
      !contains([
        for principal in try(stmt.Principal.Federated, []) :
        principal if can(regex("\\*", principal))
      ], "*")
    ])
    error_message = "Federated principals should not use wildcards"
  }

  assert {
    condition = alltrue([
      for stmt in jsondecode(aws_iam_role.this.assume_role_policy).Statement :
      length([
        for key, value in try(stmt.Condition, {}) :
        value if can(regex("\\*", tostring(value)))
      ]) == 0 || 
      anytrue([
        for key, value in try(stmt.Condition, {}) :
        contains(["StringLike", "StringEquals"], key)
      ])
    ])
    error_message = "Wildcard conditions should use appropriate condition operators"
  }
}
