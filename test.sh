#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if we're on main/master branch (optional in Harness)
check_main_branch() {
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "HEAD")
    
    # In Harness, we might be in detached HEAD state
    if [[ "$current_branch" == "HEAD" ]]; then
        print_warning "In detached HEAD state (common in CI/CD). Checking branch from environment..."
        # Try to get branch from Harness environment variables
        current_branch="${DRONE_SOURCE_BRANCH:-${DRONE_TARGET_BRANCH:-unknown}}"
    fi
    
    # If SKIP_BRANCH_CHECK is set, skip the branch validation
    if [[ "${SKIP_BRANCH_CHECK:-false}" == "true" ]]; then
        print_warning "Branch check skipped (SKIP_BRANCH_CHECK=true)"
        return 0
    fi
    
    if [[ "$current_branch" != "main" && "$current_branch" != "master" ]]; then
        print_error "Not on main/master branch. Current branch: $current_branch"
        print_info "Changelog generation is only allowed on main/master branch."
        print_info "Set SKIP_BRANCH_CHECK=true to override this check."
        exit 1
    fi
    
    print_success "Branch validated: $current_branch"
}

# Function to setup git configuration for Harness
setup_git_config() {
    print_info "Setting up git configuration for Harness CI..."
    
    # Ensure we have full git history
    if git rev-parse --is-shallow-repository 2>/dev/null | grep -q "true"; then
        print_warning "Shallow clone detected. Fetching full history..."
        git fetch --unshallow --tags || git fetch --depth=1000 --tags
    else
        print_info "Fetching tags..."
        git fetch --tags || true
    fi
    
    # Set git user if not already set (required for some git operations)
    if [[ -z "$(git config user.name)" ]]; then
        git config user.name "${GIT_USER_NAME:-Harness CI}"
        git config user.email "${GIT_USER_EMAIL:-ci@harness.io}"
        print_info "Git user configured: $(git config user.name)"
    fi
}

# Function to get release tags
get_release_tags() {
    print_info "Fetching release tags..."
    
    # If specific tags are provided via environment variables
    if [[ -n "${LATEST_TAG}" && -n "${PREVIOUS_TAG}" ]]; then
        print_info "Using tags from environment variables"
        print_info "Latest release: $LATEST_TAG"
        print_info "Previous release: $PREVIOUS_TAG"
        return
    fi
    
    local tags
    tags=$(git tag --sort=-version:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+' | head -2)
    
    if [[ -z "$tags" ]]; then
        print_error "No release tags found. Please ensure you have at least one release tag."
        print_info "You can also set LATEST_TAG and PREVIOUS_TAG environment variables."
        exit 1
    fi
    
    local tag_count
    tag_count=$(echo "$tags" | wc -l)
    
    if [[ $tag_count -lt 2 ]]; then
        print_warning "Only one release tag found. Generating changelog from first commit."
        LATEST_TAG=$(echo "$tags" | head -1)
        PREVIOUS_TAG=$(git rev-list --max-parents=0 HEAD)
    else
        LATEST_TAG=$(echo "$tags" | head -1)
        PREVIOUS_TAG=$(echo "$tags" | sed -n '2p')
    fi
    
    print_info "Latest release: $LATEST_TAG"
    print_info "Previous release: $PREVIOUS_TAG"
}

# Function to get repository information
get_repo_info() {
    # Try to get repo info from environment or git remote
    if [[ -n "${REPO_OWNER}" && -n "${REPO_NAME}" ]]; then
        GITHUB_REPO_OWNER="${REPO_OWNER}"
        GITHUB_REPO_NAME="${REPO_NAME}"
    else
        local remote_url
        remote_url=$(git config --get remote.origin.url || echo "")
        
        if [[ "$remote_url" =~ github.com[:/]([^/]+)/([^/.]+) ]]; then
            GITHUB_REPO_OWNER="${BASH_REMATCH[1]}"
            GITHUB_REPO_NAME="${BASH_REMATCH[2]}"
        else
            # Fallback defaults
            GITHUB_REPO_OWNER="${REPO_OWNER:-terraform-aws-modules}"
            GITHUB_REPO_NAME="${REPO_NAME:-terraform-aws-iam}"
        fi
    fi
    
    print_info "Repository: $GITHUB_REPO_OWNER/$GITHUB_REPO_NAME"
}

# Function to categorize commits
categorize_commit() {
    local commit_msg="$1"
    local commit_hash="$2"
    
    # Skip release commits
    if [[ "$commit_msg" =~ ^chore\(release\): ]]; then
        return
    fi
    
    # Categorize based on conventional commit format
    if [[ "$commit_msg" =~ ^feat(\(.+\))?: ]]; then
        FEATURES+=("$commit_hash|$commit_msg")
    elif [[ "$commit_msg" =~ ^fix(\(.+\))?: ]]; then
        FIXES+=("$commit_hash|$commit_msg")
    elif [[ "$commit_msg" =~ ^docs(\(.+\))?: ]]; then
        DOCS+=("$commit_hash|$commit_msg")
    elif [[ "$commit_msg" =~ ^chore(\(.+\))?: ]]; then
        CHORES+=("$commit_hash|$commit_msg")
    elif [[ "$commit_msg" =~ ^refactor(\(.+\))?: ]]; then
        REFACTOR+=("$commit_hash|$commit_msg")
    elif [[ "$commit_msg" =~ ^test(\(.+\))?: ]]; then
        TESTS+=("$commit_hash|$commit_msg")
    elif [[ "$commit_msg" =~ ^perf(\(.+\))?: ]]; then
        PERFORMANCE+=("$commit_hash|$commit_msg")
    elif [[ "$commit_msg" =~ ^style(\(.+\))?: ]]; then
        STYLE+=("$commit_hash|$commit_msg")
    elif [[ "$commit_msg" =~ ^ci(\(.+\))?: ]]; then
        CI+=("$commit_hash|$commit_msg")
    else
        OTHER+=("$commit_hash|$commit_msg")
    fi
}

# Function to parse commits between releases
parse_commits() {
    print_info "Parsing commits between $PREVIOUS_TAG and $LATEST_TAG..."
    
    # Initialize arrays for different commit categories
    FEATURES=()
    FIXES=()
    DOCS=()
    CHORES=()
    REFACTOR=()
    TESTS=()
    PERFORMANCE=()
    STYLE=()
    CI=()
    OTHER=()
    
    # Get commits between releases
    local commits
    commits=$(git log --pretty=format:"%h|%s" "$PREVIOUS_TAG..$LATEST_TAG" --reverse)
    
    if [[ -z "$commits" ]]; then
        print_warning "No commits found between $PREVIOUS_TAG and $LATEST_TAG"
        return
    fi
    
    local commit_count=0
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            local hash
            local msg
            hash=$(echo "$line" | cut -d'|' -f1)
            msg=$(echo "$line" | cut -d'|' -f2-)
            categorize_commit "$msg" "$hash"
            ((commit_count++))
        fi
    done <<< "$commits"
    
    print_info "Processed $commit_count commits"
}

# Function to format commit entry
format_commit() {
    local commit_info="$1"
    local hash
    local msg
    hash=$(echo "$commit_info" | cut -d'|' -f1)
    msg=$(echo "$commit_info" | cut -d'|' -f2-)
    
    # Extract PR number if present
    local pr_number=""
    if [[ "$msg" =~ \(\#([0-9]+)\) ]]; then
        pr_number=" ([#${BASH_REMATCH[1]}](https://github.com/${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}/pull/${BASH_REMATCH[1]}))"
    fi
    
    # Clean up the message (remove scope if present)
    local clean_msg
    if [[ "$msg" =~ ^[a-z]+(\(.+\))?: ]]; then
        clean_msg=$(echo "$msg" | sed 's/^[a-z]*(\([^)]*\)): //' | sed 's/^[a-z]*: //')
    else
        clean_msg="$msg"
    fi
    
    echo "- $clean_msg ([${hash}](https://github.com/${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}/commit/${hash}))$pr_number"
}

# Function to generate changelog content
generate_changelog() {
    local changelog_content=""
    local release_date
    release_date=$(git log -1 --format=%ai "$LATEST_TAG" 2>/dev/null | cut -d' ' -f1 || date +%Y-%m-%d)
    
    changelog_content+="# Changelog\n\n"
    changelog_content+="## [$LATEST_TAG](https://github.com/${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}/compare/$PREVIOUS_TAG...$LATEST_TAG) ($release_date)\n\n"
    
    # Add features
    if [[ ${#FEATURES[@]} -gt 0 ]]; then
        changelog_content+="### ✨ Features\n\n"
        for feature in "${FEATURES[@]}"; do
            changelog_content+="$(format_commit "$feature")\n"
        done
        changelog_content+="\n"
    fi
    
    # Add fixes
    if [[ ${#FIXES[@]} -gt 0 ]]; then
        changelog_content+="### 🐛 Bug Fixes\n\n"
        for fix in "${FIXES[@]}"; do
            changelog_content+="$(format_commit "$fix")\n"
        done
        changelog_content+="\n"
    fi
    
    # Add performance improvements
    if [[ ${#PERFORMANCE[@]} -gt 0 ]]; then
        changelog_content+="### ⚡ Performance Improvements\n\n"
        for perf in "${PERFORMANCE[@]}"; do
            changelog_content+="$(format_commit "$perf")\n"
        done
        changelog_content+="\n"
    fi
    
    # Add refactoring
    if [[ ${#REFACTOR[@]} -gt 0 ]]; then
        changelog_content+="### ♻️ Code Refactoring\n\n"
        for refactor in "${REFACTOR[@]}"; do
            changelog_content+="$(format_commit "$refactor")\n"
        done
        changelog_content+="\n"
    fi
    
    # Add documentation
    if [[ ${#DOCS[@]} -gt 0 ]]; then
        changelog_content+="### 📖 Documentation\n\n"
        for doc in "${DOCS[@]}"; do
            changelog_content+="$(format_commit "$doc")\n"
        done
        changelog_content+="\n"
    fi
    
    # Add tests
    if [[ ${#TESTS[@]} -gt 0 ]]; then
        changelog_content+="### 🧪 Tests\n\n"
        for test in "${TESTS[@]}"; do
            changelog_content+="$(format_commit "$test")\n"
        done
        changelog_content+="\n"
    fi
    
    # Add CI/CD changes
    if [[ ${#CI[@]} -gt 0 ]]; then
        changelog_content+="### 👷 CI/CD\n\n"
        for ci in "${CI[@]}"; do
            changelog_content+="$(format_commit "$ci")\n"
        done
        changelog_content+="\n"
    fi
    
    # Add chores
    if [[ ${#CHORES[@]} -gt 0 ]]; then
        changelog_content+="### 🔧 Chores\n\n"
        for chore in "${CHORES[@]}"; do
            changelog_content+="$(format_commit "$chore")\n"
        done
        changelog_content+="\n"
    fi
    
    # Add style changes
    if [[ ${#STYLE[@]} -gt 0 ]]; then
        changelog_content+="### 💄 Style Changes\n\n"
        for style in "${STYLE[@]}"; do
            changelog_content+="$(format_commit "$style")\n"
        done
        changelog_content+="\n"
    fi
    
    # Add other changes
    if [[ ${#OTHER[@]} -gt 0 ]]; then
        changelog_content+="### 📦 Other Changes\n\n"
        for other in "${OTHER[@]}"; do
            changelog_content+="$(format_commit "$other")\n"
        done
        changelog_content+="\n"
    fi
    
    echo -e "$changelog_content"
}

# Function to write changelog to file
write_changelog() {
    local output_file="${1:-CHANGELOG.md}"
    local changelog_content
    changelog_content=$(generate_changelog)
    
    print_info "Writing changelog to $output_file..."
    
    if [[ -f "$output_file" ]]; then
        # Prepend to existing changelog
        local temp_file
        temp_file=$(mktemp)
        echo -e "$changelog_content" > "$temp_file"
        echo "" >> "$temp_file"
        tail -n +1 "$output_file" >> "$temp_file"
        mv "$temp_file" "$output_file"
        print_success "Changelog prepended to existing $output_file"
    else
        # Create new changelog
        echo -e "$changelog_content" > "$output_file"
        print_success "New changelog created: $output_file"
    fi
    
    # Set output variable for Harness
    if [[ -n "${HARNESS_OUTPUT_FILE:-}" ]]; then
        echo "CHANGELOG_FILE=$output_file" >> "$HARNESS_OUTPUT_FILE"
        echo "LATEST_TAG=$LATEST_TAG" >> "$HARNESS_OUTPUT_FILE"
        echo "PREVIOUS_TAG=$PREVIOUS_TAG" >> "$HARNESS_OUTPUT_FILE"
        print_info "Output variables set for Harness"
    fi
}

# Function to display statistics
display_stats() {
    print_info "=========================================="
    print_info "Changelog Statistics:"
    print_info "=========================================="
    print_info "Features:           ${#FEATURES[@]}"
    print_info "Bug Fixes:          ${#FIXES[@]}"
    print_info "Performance:        ${#PERFORMANCE[@]}"
    print_info "Refactoring:        ${#REFACTOR[@]}"
    print_info "Documentation:      ${#DOCS[@]}"
    print_info "Tests:              ${#TESTS[@]}"
    print_info "CI/CD:              ${#CI[@]}"
    print_info "Chores:             ${#CHORES[@]}"
    print_info "Style:              ${#STYLE[@]}"
    print_info "Other:              ${#OTHER[@]}"
    print_info "=========================================="
}

# Main function
main() {
    print_info "Starting changelog generation for Harness CI/CD..."
    
    # Check if we're in a git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        print_error "Not in a git repository!"
        exit 1
    fi
    
    # Setup git configuration for Harness
    setup_git_config
    
    # Get repository information
    get_repo_info
    
    # Check if we're on main branch (optional in Harness)
    check_main_branch
    
    # Get release tags
    get_release_tags
    
    # Parse commits
    parse_commits
    
    # Display statistics
    display_stats
    
    # Generate and write changelog
    local output_file="${OUTPUT_FILE:-${1:-CHANGELOG.md}}"
    write_changelog "$output_file"
    
    print_success "Changelog generation completed!"
    print_info "Generated changelog for release $LATEST_TAG"
    print_info "File: $output_file"
    
    # Display preview of changelog
    if [[ "${SHOW_PREVIEW:-false}" == "true" ]]; then
        print_info "=========================================="
        print_info "Changelog Preview:"
        print_info "=========================================="
        head -n 50 "$output_file"
        print_info "=========================================="
    fi
}

# Help function
show_help() {
    echo "Usage: $0 [output_file]"
    echo ""
    echo "Generate a changelog comparing the latest release with the previous release."
    echo "Designed to work in Harness CI/CD pipelines."
    echo ""
    echo "Arguments:"
    echo "  output_file    Optional. Output file name (default: CHANGELOG.md)"
    echo ""
    echo "Environment Variables:"
    echo "  LATEST_TAG              Latest release tag (auto-detected if not set)"
    echo "  PREVIOUS_TAG            Previous release tag (auto-detected if not set)"
    echo "  REPO_OWNER              GitHub repository owner (auto-detected)"
    echo "  REPO_NAME               GitHub repository name (auto-detected)"
    echo "  OUTPUT_FILE             Output file name (default: CHANGELOG.md)"
    echo "  SKIP_BRANCH_CHECK       Skip branch validation (default: false)"
    echo "  SHOW_PREVIEW            Show changelog preview (default: false)"
    echo "  GIT_USER_NAME           Git user name for CI (default: Harness CI)"
    echo "  GIT_USER_EMAIL          Git user email for CI (default: ci@harness.io)"
    echo "  HARNESS_OUTPUT_FILE     File to write Harness output variables"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Generate CHANGELOG.md"
    echo "  $0 RELEASE_NOTES.md                   # Generate RELEASE_NOTES.md"
    echo "  OUTPUT_FILE=NOTES.md $0               # Using environment variable"
    echo "  SKIP_BRANCH_CHECK=true $0             # Skip branch validation"
    echo ""
    echo "Harness Pipeline Example:"
    echo "  - step:"
    echo "      type: Run"
    echo "      name: Generate Changelog"
    echo "      identifier: generate_changelog"
    echo "      spec:"
    echo "        shell: Bash"
    echo "        command: |"
    echo "          chmod +x generate-changelog-harness.sh"
    echo "          export SKIP_BRANCH_CHECK=true"
    echo "          export SHOW_PREVIEW=true"
    echo "          ./generate-changelog-harness.sh"
    echo "        outputVariables:"
    echo "          - name: CHANGELOG_FILE"
    echo "          - name: LATEST_TAG"
    echo "          - name: PREVIOUS_TAG"
}

# Parse command line arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac
