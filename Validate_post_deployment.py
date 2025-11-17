#!/usr/bin/env python3
"""
Post-deployment validation for AWS Security Group
Verifies deployed resources match expected configuration
"""

import json
import os
import sys
from typing import Dict, List, Any, Optional
import boto3
from botocore.exceptions import ClientError


class SecurityGroupPostDeploymentValidator:
    """Validate security group after deployment"""
    
    def __init__(self, security_group_id: str, region: str = "us-east-1"):
        self.security_group_id = security_group_id
        self.region = region
        self.ec2_client = boto3.client('ec2', region_name=region)
        self.sg_details = None
        self.validation_results = {
            'passed': [],
            'failed': [],
            'warnings': []
        }
    
    def fetch_security_group(self) -> bool:
        """Fetch security group details from AWS"""
        try:
            response = self.ec2_client.describe_security_groups(
                GroupIds=[self.security_group_id]
            )
            self.sg_details = response['SecurityGroups'][0]
            print(f"✓ Successfully fetched security group: {self.security_group_id}")
            return True
        except ClientError as e:
            print(f"❌ Failed to fetch security group: {e}")
            return False
    
    def validate_basic_properties(self, expected_config: Dict) -> bool:
        """Validate basic security group properties"""
        print("\n[1/6] Validating Basic Properties...")
        
        # Validate VPC
        if 'vpc_id' in expected_config:
            expected_vpc = expected_config['vpc_id']
            actual_vpc = self.sg_details.get('VpcId')
            
            if expected_vpc == actual_vpc:
                self.validation_results['passed'].append(f"VPC ID matches: {actual_vpc}")
                print(f"  ✓ VPC ID: {actual_vpc}")
            else:
                self.validation_results['failed'].append(
                    f"VPC mismatch - Expected: {expected_vpc}, Got: {actual_vpc}"
                )
                print(f"  ❌ VPC mismatch")
        
        # Validate Name
        if 'security_group_name' in expected_config:
            expected_name = expected_config['security_group_name']
            actual_name = self.sg_details.get('GroupName')
            
            if expected_name in actual_name or actual_name in expected_name:
                self.validation_results['passed'].append(f"Name matches: {actual_name}")
                print(f"  ✓ Name: {actual_name}")
            else:
                self.validation_results['failed'].append(
                    f"Name mismatch - Expected: {expected_name}, Got: {actual_name}"
                )
        
        # Validate Description
        if 'description' in expected_config:
            expected_desc = expected_config['description']
            actual_desc = self.sg_details.get('Description')
            
            if expected_desc == actual_desc:
                self.validation_results['passed'].append("Description matches")
                print(f"  ✓ Description: {actual_desc}")
            else:
                self.validation_results['warnings'].append(
                    f"Description differs - Expected: {expected_desc}, Got: {actual_desc}"
                )
        
        return len(self.validation_results['failed']) == 0
    
    def validate_ingress_rules(self, expected_rules: List[Dict]) -> bool:
        """Validate ingress rules match expected configuration"""
        print("\n[2/6] Validating Ingress Rules...")
        
        actual_rules = self.sg_details.get('IpPermissions', [])
        
        print(f"  Expected {len(expected_rules)} ingress rule(s)")
        print(f"  Found {len(actual_rules)} ingress rule(s)")
        
        # Check each expected rule exists
        for idx, expected_rule in enumerate(expected_rules):
            rule_found = self._find_matching_ingress_rule(expected_rule, actual_rules)
            
            if rule_found:
                self.validation_results['passed'].append(
                    f"Ingress rule {idx+1} found: "
                    f"{expected_rule['protocol']} "
                    f"{expected_rule['from_port']}-{expected_rule['to_port']}"
                )
                print(f"  ✓ Rule {idx+1}: {expected_rule.get('description', 'No description')}")
            else:
                self.validation_results['failed'].append(
                    f"Ingress rule {idx+1} not found: {expected_rule}"
                )
                print(f"  ❌ Rule {idx+1} missing")
        
        # Check for unexpected rules
        if len(actual_rules) > len(expected_rules):
            diff = len(actual_rules) - len(expected_rules)
            self.validation_results['warnings'].append(
                f"{diff} additional ingress rule(s) found"
            )
        
        return len(self.validation_results['failed']) == 0
    
    def _find_matching_ingress_rule(
        self, 
        expected: Dict, 
        actual_rules: List[Dict]
    ) -> bool:
        """Find if expected rule exists in actual rules"""
        for rule in actual_rules:
            # Match protocol
            if rule.get('IpProtocol') != expected.get('protocol'):
                continue
            
            # Match ports
            if rule.get('FromPort') != expected.get('from_port'):
                continue
            if rule.get('ToPort') != expected.get('to_port'):
                continue
            
            # Match CIDR blocks (if specified)
            if 'cidr_blocks' in expected:
                rule_cidrs = [ip['CidrIp'] for ip in rule.get('IpRanges', [])]
                expected_cidrs = expected['cidr_blocks']
                
                if set(rule_cidrs) == set(expected_cidrs):
                    return True
            else:
                return True
        
        return False
    
    def validate_egress_rules(self, expected_rules: List[Dict]) -> bool:
        """Validate egress rules match expected configuration"""
        print("\n[3/6] Validating Egress Rules...")
        
        actual_rules = self.sg_details.get('IpPermissionsEgress', [])
        
        print(f"  Expected {len(expected_rules)} egress rule(s)")
        print(f"  Found {len(actual_rules)} egress rule(s)")
        
        # Check each expected rule exists
        for idx, expected_rule in enumerate(expected_rules):
            rule_found = self._find_matching_egress_rule(expected_rule, actual_rules)
            
            if rule_found:
                self.validation_results['passed'].append(
                    f"Egress rule {idx+1} found"
                )
                print(f"  ✓ Rule {idx+1}: {expected_rule.get('description', 'No description')}")
            else:
                self.validation_results['failed'].append(
                    f"Egress rule {idx+1} not found: {expected_rule}"
                )
                print(f"  ❌ Rule {idx+1} missing")
        
        return len(self.validation_results['failed']) == 0
    
    def _find_matching_egress_rule(
        self, 
        expected: Dict, 
        actual_rules: List[Dict]
    ) -> bool:
        """Find if expected egress rule exists in actual rules"""
        for rule in actual_rules:
            # Match protocol
            if rule.get('IpProtocol') != expected.get('protocol'):
                continue
            
            # Match ports
            if rule.get('FromPort') != expected.get('from_port'):
                continue
            if rule.get('ToPort') != expected.get('to_port'):
                continue
            
            # Match CIDR blocks (if specified)
            if 'cidr_blocks' in expected:
                rule_cidrs = [ip['CidrIp'] for ip in rule.get('IpRanges', [])]
                expected_cidrs = expected['cidr_blocks']
                
                if set(rule_cidrs) == set(expected_cidrs):
                    return True
            else:
                return True
        
        return False
    
    def validate_tags(self, expected_tags: Dict[str, str]) -> bool:
        """Validate tags match expected configuration"""
        print("\n[4/6] Validating Tags...")
        
        actual_tags = {
            tag['Key']: tag['Value'] 
            for tag in self.sg_details.get('Tags', [])
        }
        
        print(f"  Expected {len(expected_tags)} tag(s)")
        print(f"  Found {len(actual_tags)} tag(s)")
        
        for key, expected_value in expected_tags.items():
            actual_value = actual_tags.get(key)
            
            if actual_value == expected_value:
                self.validation_results['passed'].append(f"Tag '{key}' matches")
                print(f"  ✓ {key}: {actual_value}")
            elif actual_value:
                self.validation_results['warnings'].append(
                    f"Tag '{key}' differs - Expected: {expected_value}, Got: {actual_value}"
                )
                print(f"  ⚠ {key}: Expected '{expected_value}', Got '{actual_value}'")
            else:
                self.validation_results['failed'].append(f"Tag '{key}' missing")
                print(f"  ❌ {key}: Missing")
        
        # Check for unexpected tags
        unexpected = set(actual_tags.keys()) - set(expected_tags.keys())
        if unexpected:
            print(f"  ℹ Additional tags: {', '.join(unexpected)}")
        
        return len(self.validation_results['failed']) == 0
    
    def validate_security_best_practices(self) -> bool:
        """Validate security best practices"""
        print("\n[5/6] Validating Security Best Practices...")
        
        passed = True
        
        # Check for overly permissive ingress
        ingress_rules = self.sg_details.get('IpPermissions', [])
        
        for rule in ingress_rules:
            # Check for unrestricted access to sensitive ports
            from_port = rule.get('FromPort')
            to_port = rule.get('ToPort')
            
            sensitive_ports = {
                22: "SSH",
                3389: "RDP",
                3306: "MySQL",
                5432: "PostgreSQL",
                27017: "MongoDB",
                6379: "Redis",
                1433: "MSSQL"
            }
            
            if from_port and to_port:
                for port, service in sensitive_ports.items():
                    if from_port <= port <= to_port:
                        # Check if open to internet
                        for ip_range in rule.get('IpRanges', []):
                            if ip_range['CidrIp'] == '0.0.0.0/0':
                                self.validation_results['warnings'].append(
                                    f"{service} (port {port}) is open to internet"
                                )
                                print(f"  ⚠ {service} exposed to internet")
                                passed = False
        
        # Check for all-protocol rules
        for rule in ingress_rules:
            if rule.get('IpProtocol') == '-1':
                for ip_range in rule.get('IpRanges', []):
                    if ip_range['CidrIp'] == '0.0.0.0/0':
                        self.validation_results['warnings'].append(
                            "All protocols allowed from internet"
                        )
                        print(f"  ⚠ All protocols open to internet")
                        passed = False
        
        if passed:
            self.validation_results['passed'].append("Security best practices validated")
            print("  ✓ No major security concerns detected")
        
        return True
    
    def validate_terraform_outputs(self, outputs_file: str = "outputs.json") -> bool:
        """Validate Terraform outputs match AWS resources"""
        print("\n[6/6] Validating Terraform Outputs...")
        
        if not os.path.exists(outputs_file):
            self.validation_results['warnings'].append(
                f"Outputs file not found: {outputs_file}"
            )
            print(f"  ⚠ {outputs_file} not found, skipping")
            return True
        
        try:
            with open(outputs_file, 'r') as f:
                outputs = json.load(f)
            
            # Validate security_group_id
            output_id = outputs.get('security_group_id', {}).get('value')
            if output_id == self.security_group_id:
                self.validation_results['passed'].append("Output security_group_id matches")
                print(f"  ✓ security_group_id: {output_id}")
            else:
                self.validation_results['failed'].append(
                    f"Output security_group_id mismatch"
                )
                print(f"  ❌ security_group_id mismatch")
            
            # Validate security_group_name
            output_name = outputs.get('security_group_name', {}).get('value')
            actual_name = self.sg_details.get('GroupName')
            if output_name == actual_name:
                self.validation_results['passed'].append("Output security_group_name matches")
                print(f"  ✓ security_group_name: {output_name}")
            else:
                self.validation_results['failed'].append(
                    f"Output security_group_name mismatch"
                )
            
            # Validate security_group_arn
            output_arn = outputs.get('security_group_arn', {}).get('value')
            if output_arn and self.security_group_id in output_arn:
                self.validation_results['passed'].append("Output security_group_arn valid")
                print(f"  ✓ security_group_arn: {output_arn}")
            
        except Exception as e:
            self.validation_results['warnings'].append(f"Error reading outputs: {e}")
            print(f"  ⚠ Error reading outputs: {e}")
        
        return len(self.validation_results['failed']) == 0
    
    def run_all_validations(self, expected_config: Dict) -> bool:
        """Run all validation checks"""
        print("\n" + "="*80)
        print("POST-DEPLOYMENT VALIDATION")
        print("="*80)
        
        if not self.fetch_security_group():
            return False
        
        validations = [
            lambda: self.validate_basic_properties(expected_config),
            lambda: self.validate_ingress_rules(expected_config.get('ingress_rules', [])),
            lambda: self.validate_egress_rules(expected_config.get('egress_rules', [])),
            lambda: self.validate_tags(expected_config.get('tags', {})),
            lambda: self.validate_security_best_practices(),
            lambda: self.validate_terraform_outputs()
        ]
        
        results = [validation() for validation in validations]
        
        self.print_summary()
        
        return all(results)
    
    def print_summary(self):
        """Print validation summary"""
        print("\n" + "="*80)
        print("VALIDATION SUMMARY")
        print("="*80)
        
        total_passed = len(self.validation_results['passed'])
        total_failed = len(self.validation_results['failed'])
        total_warnings = len(self.validation_results['warnings'])
        
        print(f"\nPassed: {total_passed}")
        print(f"Failed: {total_failed}")
        print(f"Warnings: {total_warnings}")
        
        if total_failed > 0:
            print(f"\n❌ FAILURES:")
            for failure in self.validation_results['failed']:
                print(f"  - {failure}")
        
        if total_warnings > 0:
            print(f"\n⚠ WARNINGS:")
            for warning in self.validation_results['warnings']:
                print(f"  - {warning}")
        
        if total_failed == 0 and total_warnings == 0:
            print("\n✅ All validations passed successfully!")
        elif total_failed == 0:
            print("\n✅ All validations passed with warnings")
        else:
            print("\n❌ Validation failed")
        
        print("\n" + "="*80 + "\n")


def load_config_from_tfvars(tfvars_file: str = "terraform.tfvars") -> Dict:
    """Load expected configuration from tfvars file"""
    # This is a simplified parser - in production, use HCL parser
    config = {}
    
    if not os.path.exists(tfvars_file):
        print(f"Warning: {tfvars_file} not found")
        return config
    
    # For JSON tfvars
    if tfvars_file.endswith('.json'):
        with open(tfvars_file, 'r') as f:
            return json.load(f)
    
    return config


def main():
    """Main execution function"""
    import argparse
    
    parser = argparse.ArgumentParser(
        description="Post-deployment validation for AWS Security Group"
    )
    parser.add_argument(
        "--sg-id",
        required=True,
        help="Security Group ID to validate"
    )
    parser.add_argument(
        "--region",
        default="us-east-1",
        help="AWS region (default: us-east-1)"
    )
    parser.add_argument(
        "--config",
        default="terraform.tfvars.json",
        help="Expected configuration file"
    )
    
    args = parser.parse_args()
    
    # Load expected configuration
    expected_config = load_config_from_tfvars(args.config)
    
    # If config not loaded, create minimal config
    if not expected_config:
        expected_config = {
            'ingress_rules': [],
            'egress_rules': [],
            'tags': {}
        }
    
    # Run validation
    validator = SecurityGroupPostDeploymentValidator(
        security_group_id=args.sg_id,
        region=args.region
    )
    
    success = validator.run_all_validations(expected_config)
    
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
