# IAM Role Integration Testing

This directory contains Terraform test files for IAM role integration testing using the native Terraform testing framework.

## Files

- `iam_role_test.tftest.hcl` - Integration test file with comprehensive test cases
- `iam_role_example.tf` - Example IAM role configuration to test against
- `README.md` - This file

## Prerequisites

- Terraform v1.6.0 or later (native test command support)
- AWS credentials configured
- Appropriate IAM permissions to create/delete IAM roles and policies

## Test Coverage

The test file includes 15 comprehensive test scenarios:

1. **create_iam_role** - Verifies basic IAM role creation
2. **verify_assume_role_policy** - Validates assume role policy JSON structure
3. **verify_policy_attachment** - Checks managed policy attachment
4. **verify_inline_policy** - Validates inline policy configuration
5. **verify_role_tags** - Ensures proper tagging
6. **verify_role_description** - Checks role description exists
7. **verify_max_session_duration** - Validates session duration limits
8. **verify_idempotency** - Ensures no changes on second apply
9. **verify_trusted_entities** - Confirms trusted service principals
10. **verify_role_path** - Validates IAM path format
11. **destroy_resources** - Tests clean resource teardown
12. **verify_permissions_boundary** - Checks permissions boundary if set
13. **verify_force_detach_policies** - Validates force detach setting
14. **verify_policy_permissions** - Tests policy action configuration
15. **verify_unique_id** - Confirms AWS unique ID generation

## Running the Tests

### Run all tests
```bash
terraform test
```

### Run specific test file
```bash
terraform test -filter=iam_role_test.tftest.hcl
```

### Run tests with verbose output
```bash
terraform test -verbose
```

### Run tests without cleanup (for debugging)
```bash
terraform test -no-cleanup
```

### Run specific test case
```bash
terraform test -filter=tests/iam_role_test.tftest.hcl -verbose -filter-run=create_iam_role
```

## Test Variables

You can override test variables by creating a `terraform.tfvars` file:

```hcl
role_name = "my-custom-role"
environment = "staging"
assume_role_services = ["ec2.amazonaws.com", "lambda.amazonaws.com"]
```

## Expected Test Output

```
iam_role_test.tftest.hcl... in progress
  run "create_iam_role"... pass
  run "verify_assume_role_policy"... pass
  run "verify_policy_attachment"... pass
  run "verify_inline_policy"... pass
  run "verify_role_tags"... pass
  run "verify_role_description"... pass
  run "verify_max_session_duration"... pass
  run "verify_idempotency"... pass
  run "verify_trusted_entities"... pass
  run "verify_role_path"... pass
  run "destroy_resources"... pass
  run "verify_permissions_boundary"... pass
  run "verify_force_detach_policies"... pass
  run "verify_policy_permissions"... pass
  run "verify_unique_id"... pass
iam_role_test.tftest.hcl... tearing down
iam_role_test.tftest.hcl... pass

Success! 15 passed, 0 failed.
```

## Customizing Tests

### Add Custom Assertions

Add new `assert` blocks within existing `run` blocks:

```hcl
run "create_iam_role" {
  command = apply

  assert {
    condition     = aws_iam_role.this.name == var.role_name
    error_message = "IAM role name does not match expected value"
  }
  
  # Add your custom assertion
  assert {
    condition     = length(aws_iam_role.this.name) <= 64
    error_message = "IAM role name must be 64 characters or less"
  }
}
```

### Add New Test Cases

Add new `run` blocks to test additional scenarios:

```hcl
run "verify_custom_behavior" {
  command = apply

  variables {
    custom_var = "custom_value"
  }

  assert {
    condition     = # your condition
    error_message = "Your error message"
  }
}
```

## Integration with CI/CD

### GitHub Actions Example

```yaml
name: Terraform Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v2
        with:
          terraform_version: 1.6.0
      
      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1
      
      - name: Terraform Init
        run: terraform init
      
      - name: Terraform Test
        run: terraform test -verbose
```

### Harness CI Example

```yaml
pipeline:
  name: IAM Role Terraform Tests
  identifier: iam_role_terraform_tests
  stages:
    - stage:
        name: Test
        identifier: test
        type: CI
        spec:
          execution:
            steps:
              - step:
                  type: Run
                  name: Terraform Test
                  identifier: terraform_test
                  spec:
                    shell: Bash
                    command: |
                      terraform init
                      terraform test -verbose
```

## Troubleshooting

### Common Issues

**Issue**: Tests fail with "resource not found"
- **Solution**: Ensure you have proper AWS credentials configured

**Issue**: Tests timeout
- **Solution**: Increase AWS API rate limits or add retry logic

**Issue**: Idempotency test fails
- **Solution**: Check for computed values that change between applies

## Best Practices

1. Always test both `apply` and `plan` commands
2. Include a destroy test to ensure clean teardown
3. Test edge cases and failure scenarios
4. Use variables to make tests reusable
5. Add descriptive error messages to all assertions
6. Group related assertions in the same `run` block
7. Test idempotency to ensure stability

## Additional Resources

- [Terraform Testing Documentation](https://developer.hashicorp.com/terraform/language/tests)
- [AWS IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
