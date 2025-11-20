#!/bin/bash

ROOT_DIR="${1:-.}"

TOTAL_MODULES=0
TESTED_MODULES=0
FAILED_MODULES=0
SKIPPED_MODULES=0

declare -a TEST_RESULTS

# Try to find tofu in common locations
find_tofu_command() {
    # First check if tofu is in PATH
    if command -v tofu &> /dev/null; then
        TOFU_CMD="tofu"
        return 0
    fi
    
    # Check common installation locations
    local common_paths=(
        "/usr/local/bin/tofu"
        "/usr/bin/tofu"
        "/opt/homebrew/bin/tofu"
        "$HOME/.local/bin/tofu"
        "$HOME/bin/tofu"
        "/snap/bin/tofu"
    )
    
    for path in "${common_paths[@]}"; do
        if [[ -x "$path" ]]; then
            TOFU_CMD="$path"
            echo "Found tofu at: $path"
            return 0
        fi
    done
    
    # Try to find it using which (sometimes works when command -v doesn't)
    if which tofu &> /dev/null; then
        TOFU_CMD=$(which tofu)
        echo "Found tofu using which: $TOFU_CMD"
        return 0
    fi
    
    return 1
}

# Check if a test directory contains integrationtest.tftest.hcl file
has_integration_test() {
    local test_dir=$1
    
    # Debug: Show what we're checking
    echo "  Checking for integrationtest.tftest.hcl in: $test_dir"
    
    # Check for integrationtest.tftest.hcl file specifically
    if [[ -f "$test_dir/integrationtest.tftest.hcl" ]]; then
        echo "  Found integrationtest.tftest.hcl"
        return 0
    fi
    
    # Also check subdirectories for the file
    local found=$(find "$test_dir" -name "integrationtest.tftest.hcl" -type f 2>/dev/null | head -1)
    if [[ -n "$found" ]]; then
        echo "  Found integrationtest.tftest.hcl at: $found"
        return 0
    fi
    
    echo "  No integrationtest.tftest.hcl file found"
    return 1
}

# Get the path to integrationtest.tftest.hcl file
get_integration_test_path() {
    local test_dir=$1
    
    # Check for integrationtest.tftest.hcl file directly in test directory
    if [[ -f "$test_dir/integrationtest.tftest.hcl" ]]; then
        echo "$test_dir/integrationtest.tftest.hcl"
        return 0
    fi
    
    # Check subdirectories for the file
    local found=$(find "$test_dir" -name "integrationtest.tftest.hcl" -type f 2>/dev/null | head -1)
    if [[ -n "$found" ]]; then
        echo "$found"
        return 0
    fi
    
    return 1
}

run_tofu_test() {
    local module_dir=$1
    local module_name=$(basename "$module_dir")
    local test_dir=""
    
    # Determine which test directory exists
    if [[ -d "$module_dir/test" ]]; then
        test_dir="$module_dir/test"
    elif [[ -d "$module_dir/tests" ]]; then
        test_dir="$module_dir/tests"
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Testing module: $module_name"
    echo "Path: $module_dir"
    echo "Test directory: $test_dir"
    
    # Get the integration test file path
    local integration_test_file=""
    if [[ -n "$test_dir" ]]; then
        integration_test_file=$(get_integration_test_path "$test_dir")
        
        if [[ -n "$integration_test_file" ]]; then
            echo "Integration test file found:"
            # Show relative path from module directory
            local rel_path=${integration_test_file#$module_dir/}
            echo "  - $rel_path"
        else
            echo "Warning: No integrationtest.tftest.hcl file found"
            echo "Directory contents:"
            ls -la "$test_dir" | head -10
        fi
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    cd "$module_dir" || {
        echo "Failed to enter directory: $module_dir"
        return 1
    }
    
    echo "Initializing module..."
    if $TOFU_CMD init -upgrade >/dev/null 2>&1; then
        echo "Module initialized successfully"
    else
        echo "Module initialization had warnings or was skipped"
    fi
    
    # Run tofu test with filter for integrationtest.tftest.hcl
    if [[ -n "$integration_test_file" ]]; then
        # Get the relative path of the test file from module directory
        local test_file_rel_path=${integration_test_file#$module_dir/}
        
        echo "Running tests with filter..."
        echo "Command: tofu test -filter=\"$test_file_rel_path\""
        
        if $TOFU_CMD test -filter="$test_file_rel_path"; then
            echo "Tests passed for module: $module_name"
            TEST_RESULTS+=("$module_name: PASSED")
            ((TESTED_MODULES++))
            return 0
        else
            echo "Tests failed for module: $module_name"
            TEST_RESULTS+=("$module_name: FAILED")
            ((FAILED_MODULES++))
            return 1
        fi
    else
        echo "Error: No integration test file to run"
        return 1
    fi
}

find_and_test_modules() {
    local search_dir=$1
    
    echo ""
    echo "Recursively searching for modules with integrationtest.tftest.hcl files"
    echo "Search directory: $search_dir"
    echo ""
    
    # Find all directories with test or tests subdirectories
    echo "Finding all test directories..."
    local test_dirs=$(find "$search_dir" \( -type d -name "test" -o -type d -name "tests" \) 2>/dev/null | grep -v "/\." | grep -v "node_modules" | grep -v ".terraform")
    
    if [[ -z "$test_dirs" ]]; then
        echo "No test or tests directories found"
    else
        echo "Found test directories:"
        echo "$test_dirs"
        echo ""
    fi
    
    # Process each test directory found
    while IFS= read -r test_parent_dir; do
        if [[ -z "$test_parent_dir" ]]; then
            continue
        fi
        
        # Get the parent directory of the test folder
        local module_dir=$(dirname "$test_parent_dir")
        local test_folder_name=$(basename "$test_parent_dir")
        
        echo "Examining: $module_dir"
        echo "  Has test folder: $test_folder_name/"
        
        # Skip if the path contains excluded directories
        if echo "$module_dir" | grep -qE "(^|/)(\.|node_modules|\.git|\.terraform)(/|$)"; then
            echo "  Skipping: Path contains excluded directory"
            continue
        fi
        
        ((TOTAL_MODULES++))
        
        # Check if the test directory has integrationtest.tftest.hcl file
        if has_integration_test "$test_parent_dir"; then
            echo "  Integration test: Yes"
            echo "  ACTION: Will run tests with filter"
            
            local current_dir=$(pwd)
            run_tofu_test "$module_dir"
            cd "$current_dir" || exit 1
        else
            echo "  Integration test: No"
            echo "  ACTION: Skipping - no integrationtest.tftest.hcl file"
            TEST_RESULTS+=("$(basename "$module_dir"): SKIPPED (no integrationtest.tftest.hcl in $test_folder_name/)")
            ((SKIPPED_MODULES++))
        fi
        echo ""
    done <<< "$test_dirs"
    
    # Also check the root directory if it has a test folder
    if [[ -d "$search_dir/test" ]] || [[ -d "$search_dir/tests" ]]; then
        echo "Checking root directory: $search_dir"
        local test_dir=""
        if [[ -d "$search_dir/test" ]]; then
            test_dir="$search_dir/test"
        else
            test_dir="$search_dir/tests"
        fi
        
        echo "  Root has test folder: $(basename "$test_dir")"
        if has_integration_test "$test_dir"; then
            echo "  Root has integrationtest.tftest.hcl"
            ((TOTAL_MODULES++))
            run_tofu_test "$search_dir"
        else
            echo "  Root has no integrationtest.tftest.hcl file"
            ((TOTAL_MODULES++))
            TEST_RESULTS+=("$(basename "$search_dir"): SKIPPED (no integrationtest.tftest.hcl)")
            ((SKIPPED_MODULES++))
        fi
    fi
}

main() {
    # First, try to find the tofu command
    if ! find_tofu_command; then
        echo "Error: 'tofu' command not found in common locations."
        echo ""
        echo "Please ensure tofu is installed and try one of these solutions:"
        echo "1. Add tofu to your PATH:"
        echo "   export PATH=\$PATH:/path/to/tofu/directory"
        echo ""
        echo "2. Create a symlink in a standard location:"
        echo "   sudo ln -s /actual/path/to/tofu /usr/local/bin/tofu"
        echo ""
        echo "3. Pass the tofu path as an environment variable:"
        echo "   TOFU_PATH=/path/to/tofu ./run_tofu_tests.sh"
        echo ""
        echo "To find where tofu is installed, try:"
        echo "   find / -name tofu -type f 2>/dev/null"
        exit 1
    fi
    
    echo "Using tofu command: $TOFU_CMD"
    echo ""

    if [[ ! -d "$ROOT_DIR" ]]; then
        echo "Error: Directory '$ROOT_DIR' does not exist."
        exit 1
    fi

    ROOT_DIR=$(cd "$ROOT_DIR" && pwd)
    
    echo "Starting scan from: $ROOT_DIR"
    echo "Looking specifically for: integrationtest.tftest.hcl files"
    echo "Will use: tofu test -filter=\"path/to/integrationtest.tftest.hcl\""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Use the recursive search
    find_and_test_modules "$ROOT_DIR"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Summary:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "   Total modules found with test directories: $TOTAL_MODULES"
    echo "   Modules tested successfully: $TESTED_MODULES"
    echo "   Modules with failed tests: $FAILED_MODULES"
    echo "   Modules skipped: $SKIPPED_MODULES"
    
    if [[ ${#TEST_RESULTS[@]} -gt 0 ]]; then
        echo ""
        echo "Detailed Results:"
        for result in "${TEST_RESULTS[@]}"; do
            echo "   $result"
        done
    fi

    if [[ $FAILED_MODULES -gt 0 ]]; then
        echo ""
        echo "Some tests failed. Please review the output above."
        exit 1
    elif [[ $TESTED_MODULES -eq 0 ]]; then
        echo ""
        echo "No modules with integrationtest.tftest.hcl files were found."
        echo "Make sure your modules have:"
        echo "  1. A test/ or tests/ directory"
        echo "  2. A file named 'integrationtest.tftest.hcl' inside the test directory"
        echo ""
        echo "Current directory structure:"
        echo "Root: $ROOT_DIR"
        ls -la "$ROOT_DIR" | head -15
        exit 0
    else
        echo ""
        echo "All tests passed successfully!"
        exit 0
    fi
}

# Check if TOFU_PATH environment variable is set
if [[ -n "$TOFU_PATH" ]]; then
    if [[ -x "$TOFU_PATH" ]]; then
        TOFU_CMD="$TOFU_PATH"
        echo "Using tofu from TOFU_PATH environment variable: $TOFU_CMD"
    else
        echo "Warning: TOFU_PATH is set but not executable: $TOFU_PATH"
    fi
fi

main "$@"
