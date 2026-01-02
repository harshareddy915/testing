#!/bin/bash
# Setup script to install Flyway, Java, IAM Authenticator, and PostgreSQL client
# This script is designed for Alpine Linux systems
set -e  # Exit on any error

echo "=========================================="
echo "Starting installation process..."
echo "=========================================="

# Update package lists
echo ""
echo "[1/5] Updating package lists..."
apk update

# Install Java (OpenJDK 17)
echo ""
echo "[2/5] Installing Java (OpenJDK 17)..."
if ! command -v java &> /dev/null; then
    apk add --no-cache openjdk17 openjdk17-jre
    echo "Java installed successfully"
else
    echo "Java is already installed"
fi
java -version

# Install PostgreSQL client (psql)
echo ""
echo "[3/5] Installing PostgreSQL client (psql)..."
if ! command -v psql &> /dev/null; then
    apk add --no-cache postgresql-client
    echo "PostgreSQL client installed successfully"
else
    echo "PostgreSQL client is already installed"
fi
psql --version

# Install required dependencies for Flyway
echo ""
echo "[4/5] Installing dependencies (bash, wget, curl)..."
apk add --no-cache bash wget curl

# Install Flyway
echo ""
echo "[5/5] Installing Flyway..."
if ! command -v flyway &> /dev/null; then
    FLYWAY_VERSION="10.21.0"
    echo "Downloading Flyway version ${FLYWAY_VERSION}..."
    
    # Download and extract Flyway
    cd /tmp
    wget -q https://repo1.maven.org/maven2/org/flywaydb/flyway-commandline/${FLYWAY_VERSION}/flyway-commandline-${FLYWAY_VERSION}-linux-x64.tar.gz
    tar -xzf flyway-commandline-${FLYWAY_VERSION}-linux-x64.tar.gz
    
    # Move to /opt and create symlink
    mv flyway-${FLYWAY_VERSION} /opt/flyway
    ln -sf /opt/flyway/flyway /usr/local/bin/flyway
    
    # Clean up
    rm flyway-commandline-${FLYWAY_VERSION}-linux-x64.tar.gz
    
    echo "Flyway installed successfully"
else
    echo "Flyway is already installed"
fi
flyway -v

# Install AWS IAM Authenticator
echo ""
echo "[6/6] Installing AWS IAM Authenticator..."
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
    
    # Download and install
    curl -o /tmp/aws-iam-authenticator "$IAM_AUTH_URL"
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
