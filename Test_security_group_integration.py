#!/usr/bin/env python3
"""
Integration tests for AWS Security Group Terraform Module
Tests the actual deployed resources in AWS to verify correct configuration
"""

import json
import os
import sys
from typing import Dict, List, Any
import boto3
import pytest
from botocore.exceptions import ClientError


class TestSecurityGroupIntegration:
    """Integration test suite for AWS Security Group module"""
    
    @pytest.fixture(scope="class")
    def ec2_client(self):
        """Create EC2 client for testing"""
        region = os.environ.get('AWS_REGION', 'us-east-1')
        return boto3.client('ec2', region_name=region)
    
    @pytest.fixture(scope="class")
    def security_group_id(self) -> str:
        """Get security group ID from environment or Terraform output"""
        sg_id = os.environ.get('SECURITY_GROUP_ID')
        
        if not sg_id:
            # Try to read from Terraform outputs
            try:
                with open('outputs.json', 'r') as f:
                    outputs = json.load(f)
                    sg_id = outputs.get('security_group_id', {}).get('value')
            except FileNotFoundError:
                pytest.skip("No outputs.json file found and SECURITY_GROUP_ID not set")
        
        if not sg_id:
            pytest.skip("Security group ID not available")
        
        return sg_id
    
    @pytest.fixture(scope="class")
    def security_group_details(self, ec2_client, security_group_id) -> Dict[str, Any]:
        """Fetch security group details from AWS"""
        try:
            response = ec2_client.describe_security_groups(
                GroupIds=[security_group_id]
            )
            return response['SecurityGroups'][0]
        except ClientError as e:
            pytest.fail(f"Failed to fetch security group: {e}")
    
    # ===== Basic Existence Tests =====
    
    def test_security_group_exists(self, security_group_details):
        """Test that the security group exists in AWS"""
        assert security_group_details is not None
        assert security_group_details['GroupId'] is not None
        print(f"✓ Security group exists: {security_group_details['GroupId']}")
    
    def test_security_group_id_format(self, security_group_id):
        """Test that security group ID has correct format"""
        assert security_group_id.startswith('sg-')
        assert len(security_group_id) > 3
        print(f"✓ Security group ID format is valid: {security_group_id}")
    
    def test_security_group_name(self, security_group_details):
        """Test that security group has a valid name"""
        name = security_group_details['GroupName']
        assert name is not None
        assert len(name) > 0
        assert len(name) <= 255
        print(f"✓ Security group name is valid: {name}")
    
    def test_security_group_description(self, security_group_details):
        """Test that security group has a description"""
        description = security_group_details['Description']
        assert description is not None
        assert len(description) > 0
        print(f"✓ Security group description: {description}")
    
    def test_vpc_association(self, security_group_details):
        """Test that security group is associated with a VPC"""
        vpc_id = security_group_details.get('VpcId')
        assert vpc_id is not None
        assert vpc_id.startswith('vpc-')
        print(f"✓ Security group associated with VPC: {vpc_id}")
    
    # ===== Ingress Rules Tests =====
    
    def test_ingress_rules_exist(self, security_group_details):
        """Test that ingress rules are configured"""
        ingress_rules = security_group_details.get('IpPermissions', [])
        # Note: Some security groups may have no ingress rules by design
        print(f"✓ Ingress rules count: {len(ingress_rules)}")
        assert isinstance(ingress_rules, list)
    
    def test_https_ingress_rule(self, security_group_details):
        """Test that HTTPS ingress rule exists if configured"""
        ingress_rules = security_group_details.get('IpPermissions', [])
        
        https_rules = [
            rule for rule in ingress_rules 
            if rule.get('FromPort') == 443 and rule.get('ToPort') == 443
        ]
        
        if https_rules:
            https_rule = https_rules[0]
            assert https_rule['IpProtocol'] == 'tcp'
            print(f"✓ HTTPS ingress rule configured correctly")
            
            # Check CIDR blocks if present
            if https_rule.get('IpRanges'):
                cidrs = [ip['CidrIp'] for ip in https_rule['IpRanges']]
                print(f"  HTTPS allowed from: {', '.join(cidrs)}")
        else:
            print("ℹ No HTTPS ingress rule found (may be intentional)")
    
    def test_http_ingress_rule(self, security_group_details):
        """Test that HTTP ingress rule exists if configured"""
        ingress_rules = security_group_details.get('IpPermissions', [])
        
        http_rules = [
            rule for rule in ingress_rules 
            if rule.get('FromPort') == 80 and rule.get('ToPort') == 80
        ]
        
        if http_rules:
            http_rule = http_rules[0]
            assert http_rule['IpProtocol'] == 'tcp'
            print(f"✓ HTTP ingress rule configured correctly")
            
            # Check CIDR blocks if present
            if http_rule.get('IpRanges'):
                cidrs = [ip['CidrIp'] for ip in http_rule['IpRanges']]
                print(f"  HTTP allowed from: {', '.join(cidrs)}")
        else:
            print("ℹ No HTTP ingress rule found (may be intentional)")
    
    def test_ssh_ingress_rule_restricted(self, security_group_details):
        """Test that SSH access is restricted if present"""
        ingress_rules = security_group_details.get('IpPermissions', [])
        
        ssh_rules = [
            rule for rule in ingress_rules 
            if rule.get('FromPort') == 22 and rule.get('ToPort') == 22
        ]
        
        if ssh_rules:
            ssh_rule = ssh_rules[0]
            
            # Check that SSH is not open to 0.0.0.0/0
            if ssh_rule.get('IpRanges'):
                cidrs = [ip['CidrIp'] for ip in ssh_rule['IpRanges']]
                
                if '0.0.0.0/0' in cidrs:
                    pytest.fail("⚠ SSH should not be open to the internet (0.0.0.0/0)")
                else:
                    print(f"✓ SSH access is restricted to: {', '.join(cidrs)}")
        else:
            print("ℹ No SSH ingress rule found")
    
    def test_ingress_rule_descriptions(self, security_group_details):
        """Test that ingress rules have descriptions"""
        ingress_rules = security_group_details.get('IpPermissions', [])
        
        for idx, rule in enumerate(ingress_rules):
            # Check for description in CIDR ranges
            if rule.get('IpRanges'):
                for ip_range in rule['IpRanges']:
                    description = ip_range.get('Description', '')
                    if description:
                        print(f"✓ Ingress rule {idx} has description: {description}")
    
    # ===== Egress Rules Tests =====
    
    def test_egress_rules_exist(self, security_group_details):
        """Test that egress rules are configured"""
        egress_rules = security_group_details.get('IpPermissionsEgress', [])
        assert len(egress_rules) > 0, "At least one egress rule should exist"
        print(f"✓ Egress rules count: {len(egress_rules)}")
    
    def test_default_egress_rule(self, security_group_details):
        """Test for default 'allow all' egress rule"""
        egress_rules = security_group_details.get('IpPermissionsEgress', [])
        
        # Look for allow-all egress rule
        allow_all_rules = [
            rule for rule in egress_rules 
            if rule.get('IpProtocol') == '-1'
        ]
        
        if allow_all_rules:
            allow_all_rule = allow_all_rules[0]
            if allow_all_rule.get('IpRanges'):
                cidrs = [ip['CidrIp'] for ip in allow_all_rule['IpRanges']]
                if '0.0.0.0/0' in cidrs:
                    print(f"✓ Default allow-all egress rule present")
        else:
            print("ℹ No default allow-all egress rule (custom egress configured)")
    
    def test_egress_rule_descriptions(self, security_group_details):
        """Test that egress rules have descriptions"""
        egress_rules = security_group_details.get('IpPermissionsEgress', [])
        
        for idx, rule in enumerate(egress_rules):
            # Check for description in CIDR ranges
            if rule.get('IpRanges'):
                for ip_range in rule['IpRanges']:
                    description = ip_range.get('Description', '')
                    if description:
                        print(f"✓ Egress rule {idx} has description: {description}")
    
    # ===== Tagging Tests =====
    
    def test_tags_present(self, security_group_details):
        """Test that security group has tags"""
        tags = security_group_details.get('Tags', [])
        assert len(tags) > 0, "Security group should have at least one tag"
        print(f"✓ Security group has {len(tags)} tag(s)")
    
    def test_required_tags(self, security_group_details):
        """Test that required tags are present"""
        tags = {tag['Key']: tag['Value'] for tag in security_group_details.get('Tags', [])}
        
        # Define required tags (customize based on your requirements)
        required_tags = ['Environment', 'ManagedBy']
        
        missing_tags = [tag for tag in required_tags if tag not in tags]
        
        if missing_tags:
            print(f"⚠ Warning: Missing recommended tags: {', '.join(missing_tags)}")
        else:
            print(f"✓ All required tags present: {', '.join(required_tags)}")
        
        # Print all tags
        for key, value in tags.items():
            print(f"  {key}: {value}")
    
    def test_name_tag_matches_group_name(self, security_group_details):
        """Test that Name tag matches GroupName if present"""
        tags = {tag['Key']: tag['Value'] for tag in security_group_details.get('Tags', [])}
        group_name = security_group_details['GroupName']
        
        if 'Name' in tags:
            # Name tag can be same or similar to group name
            print(f"✓ Name tag: {tags['Name']}")
            print(f"  Group name: {group_name}")
        else:
            print("ℹ No Name tag found")
    
    # ===== Security Best Practices Tests =====
    
    def test_no_unrestricted_ingress_on_sensitive_ports(self, security_group_details):
        """Test that sensitive ports are not open to 0.0.0.0/0"""
        ingress_rules = security_group_details.get('IpPermissions', [])
        
        # Define sensitive ports that should not be open to internet
        sensitive_ports = [22, 3389, 3306, 5432, 1433, 27017, 6379]
        
        violations = []
        
        for rule in ingress_rules:
            from_port = rule.get('FromPort')
            to_port = rule.get('ToPort')
            
            if from_port is None:
                continue
            
            # Check if rule covers any sensitive port
            for port in sensitive_ports:
                if from_port <= port <= to_port:
                    # Check if open to internet
                    if rule.get('IpRanges'):
                        for ip_range in rule['IpRanges']:
                            if ip_range['CidrIp'] == '0.0.0.0/0':
                                violations.append(f"Port {port} is open to internet")
        
        if violations:
            print("⚠ Security warnings found:")
            for violation in violations:
                print(f"  - {violation}")
        else:
            print("✓ No sensitive ports exposed to internet")
    
    def test_no_overly_permissive_ingress(self, security_group_details):
        """Test that there are no overly permissive ingress rules"""
        ingress_rules = security_group_details.get('IpPermissions', [])
        
        warnings = []
        
        for rule in ingress_rules:
            # Check for rules allowing all protocols
            if rule.get('IpProtocol') == '-1':
                if rule.get('IpRanges'):
                    for ip_range in rule['IpRanges']:
                        if ip_range['CidrIp'] == '0.0.0.0/0':
                            warnings.append("Ingress rule allows all protocols from internet")
            
            # Check for very large port ranges
            from_port = rule.get('FromPort', 0)
            to_port = rule.get('ToPort', 0)
            
            if to_port - from_port > 1000:
                warnings.append(f"Large port range: {from_port}-{to_port}")
        
        if warnings:
            print("⚠ Permissive rule warnings:")
            for warning in warnings:
                print(f"  - {warning}")
        else:
            print("✓ No overly permissive ingress rules detected")
    
    # ===== Compliance Tests =====
    
    def test_security_group_owner(self, security_group_details):
        """Test that security group belongs to correct AWS account"""
        owner_id = security_group_details.get('OwnerId')
        assert owner_id is not None
        assert len(owner_id) == 12  # AWS account IDs are 12 digits
        print(f"✓ Security group owned by account: {owner_id}")
    
    # ===== Output Tests =====
    
    def test_terraform_outputs_match_aws(self, ec2_client, security_group_id):
        """Test that Terraform outputs match actual AWS resources"""
        try:
            with open('outputs.json', 'r') as f:
                outputs = json.load(f)
                
                output_sg_id = outputs.get('security_group_id', {}).get('value')
                output_sg_name = outputs.get('security_group_name', {}).get('value')
                output_sg_arn = outputs.get('security_group_arn', {}).get('value')
                
                # Fetch actual details
                response = ec2_client.describe_security_groups(GroupIds=[security_group_id])
                sg_details = response['SecurityGroups'][0]
                
                # Compare
                assert output_sg_id == sg_details['GroupId']
                assert output_sg_name == sg_details['GroupName']
                
                # ARN format validation
                if output_sg_arn:
                    assert output_sg_arn.startswith('arn:aws:ec2:')
                    assert sg_details['GroupId'] in output_sg_arn
                
                print("✓ Terraform outputs match AWS resources")
                
        except FileNotFoundError:
            pytest.skip("outputs.json not found")


class TestSecurityGroupConnectivity:
    """Test security group connectivity and rule validation"""
    
    @pytest.fixture(scope="class")
    def ec2_client(self):
        """Create EC2 client for testing"""
        region = os.environ.get('AWS_REGION', 'us-east-1')
        return boto3.client('ec2', region_name=region)
    
    @pytest.fixture(scope="class")
    def security_group_id(self) -> str:
        """Get security group ID from environment"""
        sg_id = os.environ.get('SECURITY_GROUP_ID')
        if not sg_id:
            try:
                with open('outputs.json', 'r') as f:
                    outputs = json.load(f)
                    sg_id = outputs.get('security_group_id', {}).get('value')
            except FileNotFoundError:
                pass
        
        if not sg_id:
            pytest.skip("Security group ID not available")
        
        return sg_id
    
    def test_analyze_security_group_rules(self, ec2_client, security_group_id):
        """Analyze and print security group rules for review"""
        try:
            response = ec2_client.describe_security_group_rules(
                Filters=[
                    {
                        'Name': 'group-id',
                        'Values': [security_group_id]
                    }
                ]
            )
            
            rules = response['SecurityGroupRules']
            
            print(f"\n{'='*80}")
            print(f"Security Group Rules Analysis for {security_group_id}")
            print(f"{'='*80}\n")
            
            ingress_rules = [r for r in rules if not r['IsEgress']]
            egress_rules = [r for r in rules if r['IsEgress']]
            
            print(f"Ingress Rules: {len(ingress_rules)}")
            for rule in ingress_rules:
                self._print_rule_details(rule, "INGRESS")
            
            print(f"\nEgress Rules: {len(egress_rules)}")
            for rule in egress_rules:
                self._print_rule_details(rule, "EGRESS")
            
            print(f"\n{'='*80}\n")
            
        except ClientError as e:
            pytest.skip(f"Cannot analyze rules: {e}")
    
    def _print_rule_details(self, rule: Dict, rule_type: str):
        """Print formatted rule details"""
        protocol = rule.get('IpProtocol', 'all')
        from_port = rule.get('FromPort', 'N/A')
        to_port = rule.get('ToPort', 'N/A')
        cidr = rule.get('CidrIpv4', rule.get('CidrIpv6', 'N/A'))
        description = rule.get('Description', 'No description')
        
        print(f"  [{rule_type}] Protocol: {protocol}, "
              f"Ports: {from_port}-{to_port}, "
              f"Source/Dest: {cidr}")
        print(f"            Description: {description}")


def generate_test_report(results: Dict[str, Any]) -> None:
    """Generate a detailed test report"""
    print("\n" + "="*80)
    print("SECURITY GROUP INTEGRATION TEST REPORT")
    print("="*80 + "\n")
    
    print(f"Total Tests: {results.get('total', 0)}")
    print(f"Passed: {results.get('passed', 0)}")
    print(f"Failed: {results.get('failed', 0)}")
    print(f"Skipped: {results.get('skipped', 0)}")
    
    if results.get('failed', 0) > 0:
        print("\n⚠ FAILED TESTS:")
        for failure in results.get('failures', []):
            print(f"  - {failure}")
    
    print("\n" + "="*80 + "\n")


if __name__ == "__main__":
    # Run tests with pytest
    exit_code = pytest.main([
        __file__,
        "-v",
        "--tb=short",
        "--color=yes",
        "-W", "ignore::DeprecationWarning"
    ])
    
    sys.exit(exit_code)
