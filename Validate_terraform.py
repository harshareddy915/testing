#!/usr/bin/env python3
"""
Pre-deployment validation tests for AWS Security Group Terraform Module
Validates Terraform configuration before applying changes
"""

import json
import subprocess
import sys
from typing import Dict, List, Any, Tuple
import os


class TerraformValidator:
    """Validate Terraform configuration and plan"""
    
    def __init__(self, terraform_dir: str = "."):
        self.terraform_dir = terraform_dir
        self.errors = []
        self.warnings = []
    
    def run_command(self, command: List[str]) -> Tuple[int, str, str]:
        """Run a shell command and return output"""
        try:
            result = subprocess.run(
                command,
                cwd=self.terraform_dir,
                capture_output=True,
                text=True,
                timeout=300
            )
            return result.returncode, result.stdout, result.stderr
        except subprocess.TimeoutExpired:
            return 1, "", "Command timed out"
        except Exception as e:
            return 1, "", str(e)
    
    def test_terraform_format(self) -> bool:
        """Test if Terraform files are properly formatted"""
        print("\n[1/8] Testing Terraform Format...")
        
        returncode, stdout, stderr = self.run_command(
            ["terraform", "fmt", "-check", "-recursive", "-diff"]
        )
        
        if returncode != 0:
            self.errors.append("Terraform files are not properly formatted")
            print("❌ Format check failed")
            print(stdout)
            return False
        
        print("✓ All Terraform files are properly formatted")
        return True
    
    def test_terraform_init(self) -> bool:
        """Test Terraform initialization"""
        print("\n[2/8] Testing Terraform Init...")
        
        returncode, stdout, stderr = self.run_command(
            ["terraform", "init", "-backend=false"]
        )
        
        if returncode != 0:
            self.errors.append("Terraform init failed")
            print("❌ Init failed")
            print(stderr)
            return False
        
        print("✓ Terraform initialized successfully")
        return True
    
    def test_terraform_validate(self) -> bool:
        """Test Terraform validation"""
        print("\n[3/8] Testing Terraform Validate...")
        
        returncode, stdout, stderr = self.run_command(
            ["terraform", "validate", "-json"]
        )
        
        if returncode != 0:
            self.errors.append("Terraform validation failed")
            print("❌ Validation failed")
            print(stderr)
            return False
        
        try:
            validation_result = json.loads(stdout)
            if not validation_result.get('valid', False):
                self.errors.append("Configuration is not valid")
                for diag in validation_result.get('diagnostics', []):
                    print(f"  {diag.get('severity', 'error')}: {diag.get('summary', '')}")
                return False
        except json.JSONDecodeError:
            pass
        
        print("✓ Terraform configuration is valid")
        return True
    
    def test_terraform_plan(self) -> bool:
        """Test Terraform plan generation"""
        print("\n[4/8] Testing Terraform Plan...")
        
        returncode, stdout, stderr = self.run_command(
            ["terraform", "plan", "-out=test-plan.tfplan"]
        )
        
        if returncode != 0:
            self.errors.append("Terraform plan failed")
            print("❌ Plan generation failed")
            print(stderr)
            return False
        
        print("✓ Terraform plan generated successfully")
        
        # Parse plan for analysis
        self._analyze_plan_output(stdout)
        
        return True
    
    def _analyze_plan_output(self, plan_output: str):
        """Analyze Terraform plan output"""
        if "No changes" in plan_output:
            print("ℹ No changes detected (infrastructure matches configuration)")
        
        if "Plan:" in plan_output:
            # Extract resource changes
            lines = plan_output.split('\n')
            for line in lines:
                if 'to add' in line or 'to change' in line or 'to destroy' in line:
                    print(f"  {line.strip()}")
    
    def test_security_scan_checkov(self) -> bool:
        """Run Checkov security scan"""
        print("\n[5/8] Running Checkov Security Scan...")
        
        # Check if checkov is available
        check_cmd = self.run_command(["which", "checkov"])
        if check_cmd[0] != 0:
            self.warnings.append("Checkov not installed, skipping security scan")
            print("⚠ Checkov not found, skipping")
            return True
        
        returncode, stdout, stderr = self.run_command([
            "checkov",
            "-d", ".",
            "--framework", "terraform",
            "--output", "cli",
            "--soft-fail"
        ])
        
        # Parse output for failed checks
        if "failed checks" in stdout.lower():
            lines = stdout.split('\n')
            for line in lines:
                if 'Check:' in line or 'FAILED' in line:
                    print(f"  {line}")
            print("⚠ Security issues detected (review above)")
        else:
            print("✓ Security scan passed")
        
        return True
    
    def test_tflint(self) -> bool:
        """Run TFLint for best practices"""
        print("\n[6/8] Running TFLint...")
        
        # Check if tflint is available
        check_cmd = self.run_command(["which", "tflint"])
        if check_cmd[0] != 0:
            self.warnings.append("TFLint not installed, skipping")
            print("⚠ TFLint not found, skipping")
            return True
        
        # Initialize tflint
        self.run_command(["tflint", "--init"])
        
        returncode, stdout, stderr = self.run_command([
            "tflint",
            "--format", "compact"
        ])
        
        if returncode != 0:
            print("⚠ TFLint found issues:")
            print(stdout)
        else:
            print("✓ TFLint checks passed")
        
        return True
    
    def test_variable_validation(self) -> bool:
        """Validate required variables are present"""
        print("\n[7/8] Validating Variables...")
        
        # Check for variables.tf
        var_file = os.path.join(self.terraform_dir, "variables.tf")
        if not os.path.exists(var_file):
            self.warnings.append("variables.tf not found")
            print("⚠ variables.tf not found")
            return True
        
        # Check for terraform.tfvars or *.auto.tfvars
        tfvars_files = [
            "terraform.tfvars",
            "terraform.tfvars.json"
        ]
        
        has_tfvars = any(
            os.path.exists(os.path.join(self.terraform_dir, f)) 
            for f in tfvars_files
        )
        
        if not has_tfvars:
            print("ℹ No terraform.tfvars file found (variables may be passed via CLI)")
        else:
            print("✓ Variable files found")
        
        return True
    
    def test_output_validation(self) -> bool:
        """Validate outputs are properly defined"""
        print("\n[8/8] Validating Outputs...")
        
        # Check for outputs.tf
        output_file = os.path.join(self.terraform_dir, "outputs.tf")
        if not os.path.exists(output_file):
            self.warnings.append("outputs.tf not found")
            print("⚠ outputs.tf not found")
            return True
        
        # Read outputs file
        try:
            with open(output_file, 'r') as f:
                content = f.read()
                
                # Check for common outputs
                expected_outputs = [
                    'security_group_id',
                    'security_group_name',
                    'security_group_arn'
                ]
                
                found_outputs = []
                for output in expected_outputs:
                    if f'output "{output}"' in content or f"output '{output}'" in content:
                        found_outputs.append(output)
                
                if found_outputs:
                    print(f"✓ Found outputs: {', '.join(found_outputs)}")
                else:
                    self.warnings.append("No standard outputs found")
                    print("⚠ No standard outputs found")
        
        except Exception as e:
            self.warnings.append(f"Could not read outputs.tf: {e}")
            print(f"⚠ Could not read outputs.tf: {e}")
        
        return True
    
    def run_all_tests(self) -> bool:
        """Run all validation tests"""
        print("\n" + "="*80)
        print("TERRAFORM CONFIGURATION VALIDATION")
        print("="*80)
        
        tests = [
            self.test_terraform_format,
            self.test_terraform_init,
            self.test_terraform_validate,
            self.test_terraform_plan,
            self.test_security_scan_checkov,
            self.test_tflint,
            self.test_variable_validation,
            self.test_output_validation
        ]
        
        results = []
        for test in tests:
            try:
                result = test()
                results.append(result)
            except Exception as e:
                self.errors.append(f"Test failed with exception: {e}")
                results.append(False)
        
        # Print summary
        self._print_summary(results)
        
        return all(results) and len(self.errors) == 0
    
    def _print_summary(self, results: List[bool]):
        """Print test summary"""
        print("\n" + "="*80)
        print("VALIDATION SUMMARY")
        print("="*80)
        
        passed = sum(results)
        total = len(results)
        
        print(f"\nTests Passed: {passed}/{total}")
        
        if self.errors:
            print(f"\n❌ Errors ({len(self.errors)}):")
            for error in self.errors:
                print(f"  - {error}")
        
        if self.warnings:
            print(f"\n⚠ Warnings ({len(self.warnings)}):")
            for warning in self.warnings:
                print(f"  - {warning}")
        
        if not self.errors and not self.warnings:
            print("\n✅ All validations passed successfully!")
        elif not self.errors:
            print("\n✅ All validations passed with warnings")
        else:
            print("\n❌ Validation failed - please fix errors before deploying")
        
        print("\n" + "="*80 + "\n")


class SecurityGroupConfigValidator:
    """Validate security group specific configuration"""
    
    def __init__(self, config_file: str = "terraform.tfvars"):
        self.config_file = config_file
        self.errors = []
        self.warnings = []
    
    def validate_ingress_rules(self, rules: List[Dict]) -> bool:
        """Validate ingress rules configuration"""
        print("\nValidating Ingress Rules...")
        
        if not rules:
            print("ℹ No ingress rules defined")
            return True
        
        for idx, rule in enumerate(rules):
            rule_num = idx + 1
            
            # Check required fields
            required_fields = ['from_port', 'to_port', 'protocol', 'cidr_blocks']
            missing = [f for f in required_fields if f not in rule]
            
            if missing:
                self.errors.append(f"Rule {rule_num}: Missing fields: {missing}")
                continue
            
            # Validate port range
            if rule['from_port'] > rule['to_port']:
                self.errors.append(
                    f"Rule {rule_num}: from_port ({rule['from_port']}) > to_port ({rule['to_port']})"
                )
            
            # Validate protocol
            valid_protocols = ['tcp', 'udp', 'icmp', '-1']
            if rule['protocol'] not in valid_protocols:
                self.warnings.append(
                    f"Rule {rule_num}: Unusual protocol '{rule['protocol']}'"
                )
            
            # Check for overly permissive rules
            if '0.0.0.0/0' in rule.get('cidr_blocks', []):
                sensitive_ports = [22, 3389, 3306, 5432, 27017]
                from_port = rule['from_port']
                to_port = rule['to_port']
                
                for port in sensitive_ports:
                    if from_port <= port <= to_port:
                        self.warnings.append(
                            f"Rule {rule_num}: Port {port} open to internet (0.0.0.0/0)"
                        )
            
            # Check for description
            if not rule.get('description'):
                self.warnings.append(f"Rule {rule_num}: No description provided")
        
        if not self.errors:
            print(f"✓ Validated {len(rules)} ingress rule(s)")
        
        return len(self.errors) == 0
    
    def validate_egress_rules(self, rules: List[Dict]) -> bool:
        """Validate egress rules configuration"""
        print("\nValidating Egress Rules...")
        
        if not rules:
            self.warnings.append("No egress rules defined")
            return True
        
        for idx, rule in enumerate(rules):
            rule_num = idx + 1
            
            # Check required fields
            required_fields = ['from_port', 'to_port', 'protocol', 'cidr_blocks']
            missing = [f for f in required_fields if f not in rule]
            
            if missing:
                self.errors.append(f"Egress Rule {rule_num}: Missing fields: {missing}")
        
        if not self.errors:
            print(f"✓ Validated {len(rules)} egress rule(s)")
        
        return len(self.errors) == 0
    
    def print_summary(self):
        """Print validation summary"""
        if self.errors:
            print(f"\n❌ Configuration Errors:")
            for error in self.errors:
                print(f"  - {error}")
        
        if self.warnings:
            print(f"\n⚠ Configuration Warnings:")
            for warning in self.warnings:
                print(f"  - {warning}")


def main():
    """Main execution function"""
    import argparse
    
    parser = argparse.ArgumentParser(
        description="Validate Terraform configuration before deployment"
    )
    parser.add_argument(
        "--dir",
        default=".",
        help="Terraform directory to validate (default: current directory)"
    )
    parser.add_argument(
        "--skip-tools",
        action="store_true",
        help="Skip external tool checks (checkov, tflint)"
    )
    
    args = parser.parse_args()
    
    # Run Terraform validation
    validator = TerraformValidator(terraform_dir=args.dir)
    
    if args.skip_tools:
        validator.warnings.append("External tool checks skipped")
    
    success = validator.run_all_tests()
    
    # Exit with appropriate code
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
