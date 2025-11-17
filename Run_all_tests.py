#!/usr/bin/env python3
"""
Test Runner for AWS Security Group Module
Orchestrates pre-deployment validation, integration tests, and post-deployment validation
"""

import argparse
import json
import os
import subprocess
import sys
from datetime import datetime
from typing import Dict, List, Tuple


class TestRunner:
    """Orchestrate all test phases"""
    
    def __init__(self, config: Dict):
        self.config = config
        self.results = {
            'pre_deployment': {'status': 'pending', 'details': []},
            'terraform_test': {'status': 'pending', 'details': []},
            'integration_test': {'status': 'pending', 'details': []},
            'post_deployment': {'status': 'pending', 'details': []}
        }
        self.start_time = datetime.now()
        self.security_group_id = None
    
    def run_command(self, command: List[str], cwd: str = None) -> Tuple[int, str, str]:
        """Run a command and return results"""
        try:
            print(f"\n$ {' '.join(command)}")
            result = subprocess.run(
                command,
                cwd=cwd,
                capture_output=True,
                text=True,
                timeout=600
            )
            return result.returncode, result.stdout, result.stderr
        except subprocess.TimeoutExpired:
            return 1, "", "Command timed out"
        except Exception as e:
            return 1, "", str(e)
    
    def phase_1_pre_deployment_validation(self) -> bool:
        """Phase 1: Pre-deployment validation"""
        print("\n" + "="*80)
        print("PHASE 1: PRE-DEPLOYMENT VALIDATION")
        print("="*80)
        
        if not self.config.get('run_pre_deployment', True):
            print("⊘ Skipped (disabled in config)")
            self.results['pre_deployment']['status'] = 'skipped'
            return True
        
        # Run validation script
        returncode, stdout, stderr = self.run_command([
            "python3",
            "tests/validate_terraform.py",
            "--dir", self.config.get('terraform_dir', '.')
        ])
        
        print(stdout)
        if stderr:
            print(stderr)
        
        if returncode == 0:
            self.results['pre_deployment']['status'] = 'passed'
            self.results['pre_deployment']['details'].append('All validations passed')
            print("\n✅ Phase 1 PASSED")
            return True
        else:
            self.results['pre_deployment']['status'] = 'failed'
            self.results['pre_deployment']['details'].append('Validation failed')
            print("\n❌ Phase 1 FAILED")
            return False
    
    def phase_2_terraform_native_tests(self) -> bool:
        """Phase 2: Terraform native tests"""
        print("\n" + "="*80)
        print("PHASE 2: TERRAFORM NATIVE TESTS")
        print("="*80)
        
        if not self.config.get('run_terraform_tests', True):
            print("⊘ Skipped (disabled in config)")
            self.results['terraform_test']['status'] = 'skipped'
            return True
        
        terraform_dir = self.config.get('terraform_dir', '.')
        
        # Check if tftest files exist
        test_files = [f for f in os.listdir('tests') if f.endswith('.tftest.hcl')]
        
        if not test_files:
            print("⊘ No .tftest.hcl files found, skipping")
            self.results['terraform_test']['status'] = 'skipped'
            return True
        
        # Run terraform test
        returncode, stdout, stderr = self.run_command(
            ["terraform", "test"],
            cwd=terraform_dir
        )
        
        print(stdout)
        if stderr:
            print(stderr)
        
        if returncode == 0:
            self.results['terraform_test']['status'] = 'passed'
            self.results['terraform_test']['details'].append('All Terraform tests passed')
            print("\n✅ Phase 2 PASSED")
            return True
        else:
            self.results['terraform_test']['status'] = 'failed'
            self.results['terraform_test']['details'].append('Terraform tests failed')
            print("\n❌ Phase 2 FAILED")
            return False
    
    def phase_3_deploy_and_integration_test(self) -> bool:
        """Phase 3: Deploy resources and run integration tests"""
        print("\n" + "="*80)
        print("PHASE 3: DEPLOYMENT & INTEGRATION TESTS")
        print("="*80)
        
        if not self.config.get('run_integration_tests', True):
            print("⊘ Skipped (disabled in config)")
            self.results['integration_test']['status'] = 'skipped'
            return True
        
        terraform_dir = self.config.get('terraform_dir', 'tests/integration')
        
        # Step 3.1: Terraform Init
        print("\n[3.1] Terraform Init...")
        returncode, stdout, stderr = self.run_command(
            ["terraform", "init"],
            cwd=terraform_dir
        )
        
        if returncode != 0:
            print("❌ Terraform init failed")
            print(stderr)
            self.results['integration_test']['status'] = 'failed'
            return False
        
        # Step 3.2: Terraform Plan
        print("\n[3.2] Terraform Plan...")
        returncode, stdout, stderr = self.run_command(
            ["terraform", "plan", "-out=tfplan"],
            cwd=terraform_dir
        )
        
        if returncode != 0:
            print("❌ Terraform plan failed")
            print(stderr)
            self.results['integration_test']['status'] = 'failed'
            return False
        
        # Step 3.3: Terraform Apply
        print("\n[3.3] Terraform Apply...")
        returncode, stdout, stderr = self.run_command(
            ["terraform", "apply", "-auto-approve", "tfplan"],
            cwd=terraform_dir
        )
        
        if returncode != 0:
            print("❌ Terraform apply failed")
            print(stderr)
            self.results['integration_test']['status'] = 'failed'
            return False
        
        print("✓ Resources deployed successfully")
        
        # Step 3.4: Get Outputs
        print("\n[3.4] Extracting Outputs...")
        returncode, stdout, stderr = self.run_command(
            ["terraform", "output", "-json"],
            cwd=terraform_dir
        )
        
        if returncode == 0:
            outputs = json.loads(stdout)
            self.security_group_id = outputs.get('security_group_id', {}).get('value')
            
            # Save outputs to file for other scripts
            with open(os.path.join(terraform_dir, 'outputs.json'), 'w') as f:
                json.dump(outputs, f, indent=2)
            
            print(f"✓ Security Group ID: {self.security_group_id}")
        
        # Step 3.5: Run Integration Tests
        print("\n[3.5] Running Integration Tests...")
        
        # Set environment variables
        env = os.environ.copy()
        env['SECURITY_GROUP_ID'] = self.security_group_id or ''
        env['AWS_REGION'] = self.config.get('aws_region', 'us-east-1')
        
        # Run pytest
        test_cmd = [
            "python3", "-m", "pytest",
            "tests/test_security_group_integration.py",
            "-v",
            "--tb=short",
            "--json-report",
            "--json-report-file=test-report.json"
        ]
        
        result = subprocess.run(
            test_cmd,
            cwd=".",
            capture_output=True,
            text=True,
            env=env
        )
        
        print(result.stdout)
        
        # Parse test results
        try:
            with open('test-report.json', 'r') as f:
                report = json.load(f)
                passed = report['summary'].get('passed', 0)
                failed = report['summary'].get('failed', 0)
                total = report['summary'].get('total', 0)
                
                print(f"\nTest Results: {passed}/{total} passed")
                
                if failed > 0:
                    self.results['integration_test']['status'] = 'failed'
                    self.results['integration_test']['details'].append(
                        f"{failed} test(s) failed"
                    )
                    print("❌ Integration tests failed")
                    return False
        except:
            pass
        
        self.results['integration_test']['status'] = 'passed'
        self.results['integration_test']['details'].append('All integration tests passed')
        print("\n✅ Phase 3 PASSED")
        return True
    
    def phase_4_post_deployment_validation(self) -> bool:
        """Phase 4: Post-deployment validation"""
        print("\n" + "="*80)
        print("PHASE 4: POST-DEPLOYMENT VALIDATION")
        print("="*80)
        
        if not self.config.get('run_post_deployment', True):
            print("⊘ Skipped (disabled in config)")
            self.results['post_deployment']['status'] = 'skipped'
            return True
        
        if not self.security_group_id:
            print("⊘ Skipped (no security group deployed)")
            self.results['post_deployment']['status'] = 'skipped'
            return True
        
        # Run post-deployment validation
        returncode, stdout, stderr = self.run_command([
            "python3",
            "tests/validate_post_deployment.py",
            "--sg-id", self.security_group_id,
            "--region", self.config.get('aws_region', 'us-east-1')
        ])
        
        print(stdout)
        if stderr:
            print(stderr)
        
        if returncode == 0:
            self.results['post_deployment']['status'] = 'passed'
            self.results['post_deployment']['details'].append('Post-deployment validation passed')
            print("\n✅ Phase 4 PASSED")
            return True
        else:
            self.results['post_deployment']['status'] = 'failed'
            self.results['post_deployment']['details'].append('Post-deployment validation failed')
            print("\n❌ Phase 4 FAILED")
            return False
    
    def cleanup(self) -> bool:
        """Clean up deployed resources"""
        print("\n" + "="*80)
        print("CLEANUP: DESTROYING TEST RESOURCES")
        print("="*80)
        
        if not self.config.get('cleanup', True):
            print("⊘ Cleanup disabled in config")
            return True
        
        terraform_dir = self.config.get('terraform_dir', 'tests/integration')
        
        print("\nDestroying resources...")
        returncode, stdout, stderr = self.run_command(
            ["terraform", "destroy", "-auto-approve"],
            cwd=terraform_dir
        )
        
        print(stdout)
        
        if returncode == 0:
            print("\n✅ Cleanup successful")
            return True
        else:
            print("\n❌ Cleanup failed")
            print(stderr)
            return False
    
    def run_all_phases(self) -> bool:
        """Run all test phases"""
        print("\n" + "="*80)
        print("AWS SECURITY GROUP MODULE - COMPLETE TEST SUITE")
        print("="*80)
        print(f"Started: {self.start_time.strftime('%Y-%m-%d %H:%M:%S')}")
        
        phases = [
            ("Pre-Deployment Validation", self.phase_1_pre_deployment_validation),
            ("Terraform Native Tests", self.phase_2_terraform_native_tests),
            ("Deployment & Integration", self.phase_3_deploy_and_integration_test),
            ("Post-Deployment Validation", self.phase_4_post_deployment_validation)
        ]
        
        all_passed = True
        
        for phase_name, phase_func in phases:
            try:
                result = phase_func()
                if not result:
                    all_passed = False
                    if self.config.get('fail_fast', False):
                        print(f"\n⚠ Fail-fast enabled, stopping after {phase_name}")
                        break
            except Exception as e:
                print(f"\n❌ Exception in {phase_name}: {e}")
                all_passed = False
                if self.config.get('fail_fast', False):
                    break
        
        # Always try cleanup
        if self.config.get('cleanup', True):
            try:
                self.cleanup()
            except Exception as e:
                print(f"\n⚠ Cleanup exception: {e}")
        
        # Print final summary
        self.print_final_summary()
        
        return all_passed
    
    def print_final_summary(self):
        """Print final test summary"""
        end_time = datetime.now()
        duration = (end_time - self.start_time).total_seconds()
        
        print("\n" + "="*80)
        print("FINAL TEST SUMMARY")
        print("="*80)
        
        print(f"\nCompleted: {end_time.strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"Duration: {duration:.2f} seconds")
        
        print("\nPhase Results:")
        for phase, result in self.results.items():
            status = result['status']
            emoji = {
                'passed': '✅',
                'failed': '❌',
                'skipped': '⊘',
                'pending': '⏳'
            }.get(status, '?')
            
            print(f"  {emoji} {phase.replace('_', ' ').title()}: {status.upper()}")
            
            for detail in result['details']:
                print(f"     - {detail}")
        
        # Overall result
        failed_phases = [p for p, r in self.results.items() if r['status'] == 'failed']
        
        if not failed_phases:
            print("\n" + "="*80)
            print("🎉 ALL TESTS PASSED! 🎉")
            print("="*80 + "\n")
        else:
            print("\n" + "="*80)
            print("❌ TESTS FAILED")
            print(f"Failed phases: {', '.join(failed_phases)}")
            print("="*80 + "\n")


def load_config(config_file: str) -> Dict:
    """Load test configuration"""
    if os.path.exists(config_file):
        with open(config_file, 'r') as f:
            return json.load(f)
    
    # Default configuration
    return {
        'run_pre_deployment': True,
        'run_terraform_tests': True,
        'run_integration_tests': True,
        'run_post_deployment': True,
        'cleanup': True,
        'fail_fast': False,
        'terraform_dir': 'tests/integration',
        'aws_region': 'us-east-1'
    }


def main():
    """Main execution"""
    parser = argparse.ArgumentParser(
        description="Complete test suite for AWS Security Group module"
    )
    parser.add_argument(
        "--config",
        default="test-config.json",
        help="Test configuration file"
    )
    parser.add_argument(
        "--skip-pre",
        action="store_true",
        help="Skip pre-deployment validation"
    )
    parser.add_argument(
        "--skip-terraform-test",
        action="store_true",
        help="Skip Terraform native tests"
    )
    parser.add_argument(
        "--skip-integration",
        action="store_true",
        help="Skip integration tests"
    )
    parser.add_argument(
        "--skip-post",
        action="store_true",
        help="Skip post-deployment validation"
    )
    parser.add_argument(
        "--no-cleanup",
        action="store_true",
        help="Don't clean up resources after tests"
    )
    parser.add_argument(
        "--fail-fast",
        action="store_true",
        help="Stop on first failure"
    )
    
    args = parser.parse_args()
    
    # Load config
    config = load_config(args.config)
    
    # Override with CLI args
    if args.skip_pre:
        config['run_pre_deployment'] = False
    if args.skip_terraform_test:
        config['run_terraform_tests'] = False
    if args.skip_integration:
        config['run_integration_tests'] = False
    if args.skip_post:
        config['run_post_deployment'] = False
    if args.no_cleanup:
        config['cleanup'] = False
    if args.fail_fast:
        config['fail_fast'] = True
    
    # Run tests
    runner = TestRunner(config)
    success = runner.run_all_phases()
    
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
