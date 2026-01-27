#!/usr/bin/env bash
set -eo pipefail

# ================= Configuration =================
# Set these environment variables or edit them here
# Default Nexus URL
NEXUS_URL="${NEXUS_URL:-http://localhost:8081}"
# Default Credentials
NEXUS_USER="${NEXUS_USER:-admin}"
NEXUS_PASS="${NEXUS_PASS:-admin123}"

# Repository Names (Check your Nexus configuration)
NPM_REPO="${NPM_REPO:-npm-hosted}"
PYPI_REPO="${PYPI_REPO:-pypi-hosted}"

# Construct Full URLs
NPM_REGISTRY_URL="${NEXUS_URL}/repository/${NPM_REPO}/"
PYPI_REPOSITORY_URL="${NEXUS_URL}/repository/${PYPI_REPO}/"

# Local Directories
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOWNLOADS_DIR="$ROOT_DIR/all-downloads"
NPM_DIR="${DOWNLOADS_DIR}/npm-packages"
PYPI_DIR="${DOWNLOADS_DIR}/python-packages"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ================= Helper Functions =================
log_info() { echo -e "${YELLOW}[INFO] $1${NC}"; }
log_success() { echo -e "${GREEN}[SUCCESS] $1${NC}"; }
log_error() { echo -e "${RED}[ERROR] $1${NC}"; }

check_deps() {
    if ! command -v npm &> /dev/null; then
        log_error "npm is not installed. Please install Node.js/npm."
        exit 1
    fi
    
    if ! command -v twine &> /dev/null; then
        log_info "twine command not found. Attempting to install via pip..."
        if command -v pip &> /dev/null; then
            pip install twine
        elif command -v pip3 &> /dev/null; then
            pip3 install twine
        else
            log_error "Neither twine nor pip/pip3 found. Please install twine manually (pip install twine)."
            exit 1
        fi
    fi
}

# ================= Upload Functions =================
upload_npm() {
    log_info "----------------------------------------"
    log_info "Starting NPM upload to ${NPM_REGISTRY_URL}"
    log_info "----------------------------------------"

    if [ -z "$(ls -A "$NPM_DIR"/*.tgz 2>/dev/null)" ]; then
        log_info "No .tgz files found in $NPM_DIR"
        return
    fi

    # Prepare .npmrc for authentication
    # Remove protocol (http:// or https://) for the config key
    REGISTRY_NO_PROTO=$(echo "${NPM_REGISTRY_URL}" | sed -E 's|https?://||')
    
    # Base64 encode credentials
    AUTH_TOKEN=$(echo -n "${NEXUS_USER}:${NEXUS_PASS}" | base64)

    TEMP_NPMRC="$ROOT_DIR/.npmrc.temp"
    
    # Create temporary .npmrc with auth token
    cat > "$TEMP_NPMRC" <<EOF
registry=${NPM_REGISTRY_URL}
//${REGISTRY_NO_PROTO}:_auth=${AUTH_TOKEN}
email=upload-script@local
always-auth=true
EOF

    log_info "Created temporary .npmrc for authentication"

    local count=0
    local total=$(find "$NPM_DIR" -name "*.tgz" | wc -l)
    local success_count=0
    local skip_count=0
    local fail_count=0

    for pkg in "$NPM_DIR"/*.tgz; do
        ((count++))
        PKG_NAME=$(basename "$pkg")
        
        # log_info "Processing ($count/$total) $PKG_NAME..."
        
        # Capture both stdout and stderr
        OUTPUT=$(npm publish "$pkg" --userconfig "$TEMP_NPMRC" --registry "$NPM_REGISTRY_URL" 2>&1 || true)
        
        if echo "$OUTPUT" | grep -q "+ "; then
            # npm publish outputs "+ <package>@<version>" on success
            log_success "Uploaded: $PKG_NAME"
            ((success_count++))
        elif echo "$OUTPUT" | grep -qE "E403|E400|EPUBLISHCONFLICT|previously published"; then
            # 403 or 400 usually means it already exists or policy forbids overwrite
            log_info "Skipped (Exists/Conflict): $PKG_NAME"
            ((skip_count++))
        else
            log_error "Failed: $PKG_NAME"
            echo "$OUTPUT" | head -n 5 # Show first few lines of error
            ((fail_count++))
        fi
    done

    rm -f "$TEMP_NPMRC"
    
    echo ""
    log_success "NPM Upload Summary: Success: $success_count, Skipped: $skip_count, Failed: $fail_count"
}

upload_pypi() {
    log_info "----------------------------------------"
    log_info "Starting PyPI upload to ${PYPI_REPOSITORY_URL}"
    log_info "----------------------------------------"

    if [ -z "$(ls -A "$PYPI_DIR" 2>/dev/null)" ]; then
        log_info "No files found in $PYPI_DIR"
        return
    fi

    # Check if there are any files to upload
    count=$(find "$PYPI_DIR" -type f | wc -l)
    log_info "Found $count python package files."

    # Twine upload
    # --skip-existing: Continue if package exists
    # --non-interactive: Don't ask for input
    if twine upload \
        --repository-url "${PYPI_REPOSITORY_URL}" \
        -u "${NEXUS_USER}" \
        -p "${NEXUS_PASS}" \
        --skip-existing \
        --non-interactive \
        "$PYPI_DIR"/*; then
        
        log_success "PyPI upload command completed successfully."
    else
        log_error "PyPI upload command reported errors."
    fi
}

# ================= Main =================
main() {
    echo "========================================"
    echo "   Package Upload Script for Nexus"
    echo "========================================"
    echo "NEXUS_URL:  $NEXUS_URL"
    echo "NPM_REPO:   $NPM_REPO"
    echo "PYPI_REPO:  $PYPI_REPO"
    echo "User:       $NEXUS_USER"
    echo "========================================"
    echo ""
    
    check_deps
    
    if [ -d "$NPM_DIR" ]; then
        upload_npm
    else
        log_info "NPM directory not found: $NPM_DIR"
    fi
    
    echo ""
    
    if [ -d "$PYPI_DIR" ]; then
        upload_pypi
    else
        log_info "PyPI directory not found: $PYPI_DIR"
    fi
}

main
