#!/usr/bin/env python3
"""
OpenTofu Integration Test Runner
Searches for test/tests folders and runs tofu test filtered for integrationtest.tftest.hcl
"""

import os
import sys
import subprocess
import argparse
from pathlib import Path
from typing import List, Tuple


class TofuIntegrationTestRunner:
    def __init__(self, root_dir: str, test_file: str = "integrationtest.tftest.hcl", verbose: bool = False):
        self.root_dir = Path(root_dir).resolve()
        self.test_file = test_file
        self.verbose = verbose
        self.results = []
        
    def log(self, message: str):
        """Print message if verbose mode is enabled"""
        if self.verbose:
            print(f"[INFO] {message}")
    
    def find_test_directories(self) -> List[Tuple[Path, Path]]:
        """
        Find all test/tests directories and check for the specified test file
        Returns list of tuples: (module_path, test_directory_path)
        """
        test_dirs_with_file = []
        
        # Walk through all directories
        for root, dirs, files in os.walk(self.root_dir):
            root_path = Path(root)
            
            # Check if current directory is named 'test' or 'tests'
            if root_path.name in ['test', 'tests']:
                # Check if the test file exists in this directory
                test_file_path = root_path / self.test_file
                
                if test_file_path.exists():
                    # Module path is the parent directory
                    module_path = root_path.parent
                    self.log(f"Found {self.test_file} in {root_path}")
                    test_dirs_with_file.append((module_path, root_path))
        
        return test_dirs_with_file
    
    def check_tofu_installed(self) -> bool:
        """Check if tofu command is available"""
        try:
            result = subprocess.run(
                ['tofu', '--version'],
                capture_output=True,
                text=True,
                timeout=5
            )
            return result.returncode == 0
        except (FileNotFoundError, subprocess.TimeoutExpired):
            return False
    
    def run_tofu_test(self, module_path: Path, test_dir: Path) -> Tuple[bool, str, str]:
        """
        Execute 'tofu test' with filter for specific test file
        Returns (success, stdout, stderr)
        """
        self.log(f"Running 'tofu test -filter={self.test_file}' in {module_path.name}")
        
        try:
            # Run tofu test with filter
            cmd = ['tofu', 'test', f'-filter={self.test_file}']
            
            result = subprocess.run(
                cmd,
                cwd=module_path,
                capture_output=True,
                text=True,
                timeout=600  # 10 minute timeout for integration tests
            )
            
            success = result.returncode == 0
            return success, result.stdout, result.stderr
            
        except subprocess.TimeoutExpired:
            return False, "", "Test execution timed out (600s)"
        except Exception as e:
            return False, "", f"Error executing test: {str(e)}"
    
    def run_all_tests(self, fail_fast: bool = False) -> int:
        """
        Run integration tests for all modules with the specified test file
        Returns number of failed tests
        """
        # Check if tofu is installed
        if not self.check_tofu_installed():
            print("ERROR: 'tofu' command not found. Please install OpenTofu.")
            return -1
        
        # Find test directories with the specified test file
        test_locations = self.find_test_directories()
        
        if not test_locations:
            print(f"No '{self.test_file}' found in any test/tests folders under {self.root_dir}")
            return 0
        
        print(f"\nFound {len(test_locations)} module(s) with {self.test_file}")
        print("=" * 70)
        
        failed_count = 0
        
        # Run tests for each module
        for module_path, test_dir in test_locations:
            print(f"\n📦 Testing module: {module_path.name}")
            print(f"   Test location: {test_dir.relative_to(self.root_dir)}")
            print("-" * 70)
            
            success, stdout, stderr = self.run_tofu_test(module_path, test_dir)
            
            # Store result
            self.results.append({
                'module': module_path.name,
                'test_dir': str(test_dir.relative_to(self.root_dir)),
                'success': success,
                'stdout': stdout,
                'stderr': stderr
            })
            
            # Print output
            if stdout:
                print(stdout)
            if stderr:
                print(stderr, file=sys.stderr)
            
            if success:
                print(f"✅ PASSED: {module_path.name}")
            else:
                print(f"❌ FAILED: {module_path.name}")
                failed_count += 1
                
                if fail_fast:
                    print("\nFail-fast enabled. Stopping execution.")
                    break
        
        # Print summary
        self.print_summary(failed_count, len(test_locations))
        
        return failed_count
    
    def print_summary(self, failed_count: int, total_count: int):
        """Print test execution summary"""
        passed_count = total_count - failed_count
        
        print("\n" + "=" * 70)
        print("INTEGRATION TEST SUMMARY")
        print("=" * 70)
        print(f"Test file: {self.test_file}")
        print(f"Total modules tested: {total_count}")
        print(f"✅ Passed: {passed_count}")
        print(f"❌ Failed: {failed_count}")
        
        if failed_count > 0:
            print("\nFailed modules:")
            for result in self.results:
                if not result['success']:
                    print(f"  - {result['module']} ({result['test_dir']})")


def main():
    parser = argparse.ArgumentParser(
        description='Run OpenTofu integration tests filtered by filename across all modules'
    )
    parser.add_argument(
        'directory',
        nargs='?',
        default='.',
        help='Root directory to search for modules (default: current directory)'
    )
    parser.add_argument(
        '-t', '--test-file',
        default='integrationtest.tftest.hcl',
        help='Test file name to filter (default: integrationtest.tftest.hcl)'
    )
    parser.add_argument(
        '-v', '--verbose',
        action='store_true',
        help='Enable verbose output'
    )
    parser.add_argument(
        '-f', '--fail-fast',
        action='store_true',
        help='Stop execution on first test failure'
    )
    
    args = parser.parse_args()
    
    # Validate directory
    if not os.path.isdir(args.directory):
        print(f"ERROR: Directory '{args.directory}' does not exist")
        sys.exit(1)
    
    # Create runner and execute tests
    runner = TofuIntegrationTestRunner(
        args.directory, 
        test_file=args.test_file,
        verbose=args.verbose
    )
    failed_count = runner.run_all_tests(fail_fast=args.fail_fast)
    
    # Exit with appropriate code
    if failed_count == -1:
        sys.exit(2)  # tofu not installed
    elif failed_count > 0:
        sys.exit(1)  # tests failed
    else:
        sys.exit(0)  # all tests passed


if __name__ == '__main__':
    main()
