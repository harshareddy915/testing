#!/bin/bash
# Setup script to install Flyway, Java, IAM Authenticator, and PostgreSQL client
# This script is designed for Alpine Linux systems with SSL workaround
set -e  # Exit on any error

echo "=========================================="
echo "Starting installation process..."
echo "=========================================="

# Update package lists
echo ""
echo "[1/7] Updating package lists..."
apk update

# Install CA certificates and OpenSSL
echo ""
echo "[2/7] Installing CA certificates and OpenSSL..."
apk add --no-cache ca-certificates ca-certificates-bundle openssl wget curl bash
update-ca-certificates
echo "Certificates installed"

# Install Java (OpenJDK 17)
echo ""
echo "[3/7] Installing Java (OpenJDK 17)..."
if ! command -v java &> /dev/null; then
    apk add --no-cache openjdk17 openjdk17-jre
    echo "Java installed successfully"
else
    echo "Java is already installed"
fi
java -version

# Install PostgreSQL client (psql)
echo ""
echo "[4/7] Installing PostgreSQL client (psql)..."
if ! command -v psql &> /dev/null; then
    apk add --no-cache postgresql-client
    echo "PostgreSQL client installed successfully"
else
    echo "PostgreSQL client is already installed"
fi
psql --version

# Install Flyway
echo ""
echo "[5/7] Installing Flyway..."
if ! command -v flyway &> /dev/null; then
    FLYWAY_VERSION="10.21.0"
    FLYWAY_URL="https://repo1.maven.org/maven2/org/flywaydb/flyway-commandline/${FLYWAY_VERSION}/flyway-commandline-${FLYWAY_VERSION}-linux-x64.tar.gz"
    echo "Downloading Flyway version ${FLYWAY_VERSION}..."
    
    cd /tmp
    
    # Method 1: Try curl with full SSL verification
    echo "Attempting download with curl (secure)..."
    if curl -fsSL --connect-timeout 30 -o flyway-commandline.tar.gz "$FLYWAY_URL" 2>/dev/null; then
        echo "✓ Downloaded successfully with secure connection"
    # Method 2: Try curl with insecure flag as fallback
    elif curl -fsSLk --connect-timeout 30 -o flyway-commandline.tar.gz "$FLYWAY_URL" 2>/dev/null; then
        echo "✓ Downloaded with insecure mode (SSL verification bypassed)"
    # Method 3: Try wget with insecure flag
    elif wget --no-check-certificate --timeout=30 -O flyway-commandline.tar.gz "$FLYWAY_URL" 2>/dev/null; then
        echo "✓ Downloaded with wget (SSL verification bypassed)"
    else
        echo "✗ All download methods failed"
        echo ""
        echo "Debugging information:"
        echo "====================="
        echo "Testing basic connectivity..."
        ping -c 2 8.8.8.8 || echo "No internet connection"
        echo ""
        echo "Testing DNS resolution..."
        nslookup repo1.maven.org || echo "DNS resolution failed"
        echo ""
        echo "Testing SSL connection..."
        openssl s_client -connect repo1.maven.org:443 -brief 2>&1 | head -10 || echo "SSL connection failed"
        exit 1
    fi
    
    # Verify download
    if [ ! -f flyway-commandline.tar.gz ] || [ ! -s flyway-commandline.tar.gz ]; then
        echo "Error: Downloaded file is missing or empty"
        exit 1
    fi
    
    # Extract Flyway
    echo "Extracting Flyway..."
    tar -xzf flyway-commandline.tar.gz
    
    # Move to /opt and create symlink
    mv flyway-${FLYWAY_VERSION} /opt/flyway
    ln -sf /opt/flyway/flyway /usr/local/bin/flyway
    
    # Clean up
    rm flyway-commandline.tar.gz
    
    echo "Flyway installed successfully"
else
    echo "Flyway is already installed"
fi
flyway -v

# Install AWS IAM Authenticator
echo ""
echo "[6/7] Installing AWS IAM Authenticator..."
if ! command -v aws-iam-authenticator &> /dev/null; then
    echo "Downloading AWS IAM Authenticator..."
    
    # Determine architecture
    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then
        IAM_AUTH_URL="https://amazon-eks.s3.us-west-2.amazonaws.com/1.21.2/2021-07-05/bin/linux/amd64/aws-iam-authenticator"
    elif [ "$ARCH" = "aarch64" ]; then
        IAM_AUTH_URL="https://amazon-eks.s3.us-west-2.amazonaws.com/1.21.2/2021-07-05/bin/linux/arm64/aws-iam-authenticator"
    else
        echo "Unsupported architecture: $ARCH"
        exit 1
    fi
    
    # Download with fallback
    if curl -fsSL --connect-timeout 30 -o /tmp/aws-iam-authenticator "$IAM_AUTH_URL" 2>/dev/null; then
        echo "✓ Downloaded successfully"
    elif curl -fsSLk --connect-timeout 30 -o /tmp/aws-iam-authenticator "$IAM_AUTH_URL" 2>/dev/null; then
        echo "✓ Downloaded with insecure mode"
    else
        echo "✗ Failed to download AWS IAM Authenticator"
        exit 1
    fi
    
    chmod +x /tmp/aws-iam-authenticator
    mv /tmp/aws-iam-authenticator /usr/local/bin/
    
    echo "AWS IAM Authenticator installed successfully"
else
    echo "AWS IAM Authenticator is already installed"
fi
aws-iam-authenticator version

echo ""
echo "=========================================="
echo "Installation completed successfully!"
echo "=========================================="
echo ""
echo "Installed versions:"
echo "-------------------"
java -version 2>&1 | head -n 1
psql --version
flyway -v | head -n 1
aws-iam-authenticator version

echo ""
echo "All tools are ready to use!"
