#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# Trace execution (uncomment for debugging)
# set -x

# Source environment variables
if [[ -f ./env.sh ]]; then
    source ./env.sh
else
    echo "Error: env.sh not found in current directory"
    exit 1
fi

# Log function for consistent output
log() {
    local level=$1
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] $*"
}

# Check if a command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Check if we're running as root and exit if we are
check_not_root() {
    if [[ $EUID -eq 0 ]]; then
        log "ERROR" "This script should not be run as root"
        exit 1
    fi
}

# Detect OS and set variables accordingly
detect_os() {
    log "INFO" "Detecting operating system..."
    
    if [[ "$(uname)" == "Darwin" ]]; then
        OS="macos"
        log "INFO" "macOS detected"
    elif [[ "$(uname)" == "Linux" ]]; then
        OS="linux"
        if [[ -f /etc/os-release ]]; then
            source /etc/os-release
            if [[ "$ID" == "ubuntu" || "$ID" == "debian" ]]; then
                PACKAGE_MANAGER="apt-get"
                log "INFO" "Debian/Ubuntu Linux detected"
            elif [[ "$ID" == "amzn" ]]; then
                PACKAGE_MANAGER="yum"
                log "INFO" "Amazon Linux detected"
            elif [[ "$ID" == "centos" || "$ID" == "rhel" || "$ID" == "fedora" ]]; then
                PACKAGE_MANAGER="yum"
                log "INFO" "CentOS/RHEL/Fedora Linux detected"
            else
                log "WARNING" "Unsupported Linux distribution: $ID"
                log "WARNING" "Attempting to proceed with apt-get"
                PACKAGE_MANAGER="apt-get"
            fi
        else
            log "WARNING" "Could not determine Linux distribution"
            log "WARNING" "Attempting to proceed with apt-get"
            PACKAGE_MANAGER="apt-get"
        fi
    else
        log "ERROR" "Unsupported operating system: $(uname)"
        exit 1
    fi
}

# Install dependencies based on detected OS
install_dependencies() {
    log "INFO" "Installing basic dependencies..."
    
    if [[ "$PACKAGE_MANAGER" == "apt-get" ]]; then
        sudo apt-get update || { log "ERROR" "Failed to update package lists"; exit 1; }
        sudo apt-get install -yy unzip curl ca-certificates gnupg lsb-release || { 
            log "ERROR" "Failed to install dependencies"; 
            exit 1; 
        }
    elif [[ "$PACKAGE_MANAGER" == "yum" ]]; then
        sudo yum update -y || { log "ERROR" "Failed to update package lists"; exit 1; }
        sudo yum install -y unzip curl ca-certificates gnupg || { 
            log "ERROR" "Failed to install dependencies"; 
            exit 1; 
        }
    elif [[ "$OS" == "macos" ]]; then
        if ! command_exists brew; then
            log "ERROR" "Homebrew not found. Please install Homebrew first."
            exit 1
        fi
        brew install curl unzip || { log "ERROR" "Failed to install dependencies"; exit 1; }
    fi
    
    log "INFO" "Basic dependencies installed successfully"
}

# Install AWS CLI with proper error handling
install_awscli() {
    log "INFO" "Installing AWS CLI..."
    
    if command_exists aws; then
        aws_version=$(aws --version 2>&1)
        log "INFO" "AWS CLI is already installed: $aws_version"
        
        # Check if we need to update
        if [[ "$aws_version" == *"aws-cli/1."* ]]; then
            log "INFO" "Upgrading from AWS CLI v1 to v2..."
        else
            log "INFO" "AWS CLI v2 is already installed, checking for updates..."
        fi
    else
        log "INFO" "AWS CLI not found, installing..."
    fi
    
    # Download and install AWS CLI v2
    local temp_dir=$(mktemp -d)
    pushd "$temp_dir" > /dev/null
    
    if [[ "$OS" == "macos" ]]; then
        curl -s "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg" || {
            log "ERROR" "Failed to download AWS CLI package"
            popd > /dev/null
            rm -rf "$temp_dir"
            exit 1
        }
        sudo installer -pkg AWSCLIV2.pkg -target / || {
            log "ERROR" "Failed to install AWS CLI"
            popd > /dev/null
            rm -rf "$temp_dir"
            exit 1
        }
    else
        curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" || {
            log "ERROR" "Failed to download AWS CLI"
            popd > /dev/null
            rm -rf "$temp_dir"
            exit 1
        }
        unzip -q awscliv2.zip || {
            log "ERROR" "Failed to unzip AWS CLI package"
            popd > /dev/null
            rm -rf "$temp_dir"
            exit 1
        }
        
        if command_exists aws; then
            sudo ./aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update || {
                log "ERROR" "Failed to update AWS CLI"
                popd > /dev/null
                rm -rf "$temp_dir"
                exit 1
            }
        else
            sudo ./aws/install || {
                log "ERROR" "Failed to install AWS CLI"
                popd > /dev/null
                rm -rf "$temp_dir"
                exit 1
            }
        fi
    fi
    
    popd > /dev/null
    rm -rf "$temp_dir"
    
    # Verify installation
    if ! command_exists aws; then
        log "ERROR" "AWS CLI installation failed"
        exit 1
    fi
    
    aws_version=$(aws --version 2>&1)
    log "INFO" "AWS CLI installed successfully: $aws_version"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity --query 'Arn' --output text --no-cli-pager &> /dev/null; then
        log "WARNING" "AWS CLI is not configured with valid credentials"
        
        echo "Please choose one of the following options:"
        echo "1. Run 'aws configure' to configure AWS CLI"
        echo "2. Add IAM role later"
        read -p "Enter your choice (1/2): " choice
        
        if [[ "$choice" == "1" ]]; then
            aws configure
            
            # Verify configuration worked
            if ! aws sts get-caller-identity --query 'Arn' --output text --no-cli-pager &> /dev/null; then
                log "WARNING" "AWS credentials still not configured correctly"
                log "WARNING" "Continuing anyway, but you'll need to configure AWS credentials later"
            else
                iam_entity=$(aws sts get-caller-identity --query 'Arn' --output text --no-cli-pager)
                log "INFO" "AWS credentials configured successfully for: $iam_entity"
            fi
        else
            log "WARNING" "Continuing without AWS credentials"
        fi
    else
        iam_entity=$(aws sts get-caller-identity --query 'Arn' --output text --no-cli-pager)
        log "INFO" "Using AWS credentials for: $iam_entity"
        log "INFO" "Make sure this IAM entity has necessary permissions to create resources"
    fi
}

# Install eksctl with proper error handling
install_eksctl() {
    log "INFO" "Installing eksctl..."
    
    if command_exists eksctl; then
        eksctl_version=$(eksctl version 2>&1)
        log "INFO" "eksctl is already installed: $eksctl_version"
    else
        local temp_dir=$(mktemp -d)
        pushd "$temp_dir" > /dev/null
        
        ARCH=$(uname -m)
        [[ "$ARCH" == "x86_64" ]] && ARCH="amd64"
        PLATFORM=$(uname -s)_$ARCH
        
        log "INFO" "Downloading eksctl for $PLATFORM..."
        curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz" || {
            log "ERROR" "Failed to download eksctl"
            popd > /dev/null
            rm -rf "$temp_dir"
            exit 1
        }
        
        tar -xzf eksctl_$PLATFORM.tar.gz || {
            log "ERROR" "Failed to extract eksctl"
            popd > /dev/null
            rm -rf "$temp_dir"
            exit 1
        }
        
        sudo mv eksctl /usr/local/bin || {
            log "ERROR" "Failed to install eksctl to /usr/local/bin"
            popd > /dev/null
            rm -rf "$temp_dir"
            exit 1
        }
        
        popd > /dev/null
        rm -rf "$temp_dir"
    fi
    
    # Verify installation
    if ! command_exists eksctl; then
        log "ERROR" "eksctl installation failed"
        exit 1
    fi
    
    eksctl_version=$(eksctl version)
    log "INFO" "eksctl installed successfully: $eksctl_version"
}

# Install kubectl with proper error handling
install_kubectl() {
    log "INFO" "Installing kubectl..."
    
    if command_exists kubectl; then
        kubectl_version=$(kubectl version --client -o json | grep -o '"gitVersion": "[^"]*"' | head -1)
        log "INFO" "kubectl is already installed: $kubectl_version"
    else
        local temp_dir=$(mktemp -d)
        pushd "$temp_dir" > /dev/null
        
        ARCH=$(uname -m)
        [[ "$ARCH" == "x86_64" ]] && ARCH="amd64"
        
        if [[ "$OS" == "macos" ]]; then
            PLATFORM="darwin"
        else
            PLATFORM="linux"
        fi
        
        # Get the latest stable version
        KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
        log "INFO" "Downloading kubectl $KUBECTL_VERSION for $PLATFORM/$ARCH..."
        
        curl -sLO "https://dl.k8s.io/release/$KUBECTL_VERSION/bin/$PLATFORM/$ARCH/kubectl" || {
            log "ERROR" "Failed to download kubectl"
            popd > /dev/null
            rm -rf "$temp_dir"
            exit 1
        }
        
        chmod +x kubectl
        sudo mv kubectl /usr/local/bin/ || {
            log "ERROR" "Failed to install kubectl to /usr/local/bin"
            popd > /dev/null
            rm -rf "$temp_dir"
            exit 1
        }
        
        popd > /dev/null
        rm -rf "$temp_dir"
    fi
    
    # Verify installation
    if ! command_exists kubectl; then
        log "ERROR" "kubectl installation failed"
        exit 1
    fi
    
    kubectl_version=$(kubectl version --client -o json 2>/dev/null | grep -o '"gitVersion": "[^"]*"' | head -1)
    log "INFO" "kubectl installed successfully: $kubectl_version"
}

# Install Docker with proper error handling
install_docker() {
    log "INFO" "Installing Docker..."
    
    if command_exists docker; then
        docker_version=$(docker --version)
        log "INFO" "Docker is already installed: $docker_version"
        return 0
    fi
    
    if [[ "$OS" == "macos" ]]; then
        log "WARNING" "Docker Desktop for Mac should be installed manually"
        log "WARNING" "Please download and install from https://www.docker.com/products/docker-desktop"
        return 0
    fi
    
    if [[ "$PACKAGE_MANAGER" == "apt-get" ]]; then
        # Install Docker on Debian/Ubuntu
        log "INFO" "Installing Docker using apt..."
        
        # Remove old versions if they exist
        sudo apt-get remove -y docker docker-engine docker.io containerd runc || true
        
        # Add Docker's official GPG key
        sudo apt-get update
        sudo apt-get install -y ca-certificates curl gnupg
        sudo install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        sudo chmod a+r /etc/apt/keyrings/docker.gpg
        
        # Add the repository to Apt sources
        echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        # Install Docker Engine
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    elif [[ "$PACKAGE_MANAGER" == "yum" ]]; then
        # Install Docker on Amazon Linux/RHEL/CentOS
        log "INFO" "Installing Docker using yum..."
        
        # Remove old versions if they exist
        sudo yum remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine || true
        
        # Set up the repository
        sudo yum install -y yum-utils
        sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        
        # Install Docker Engine
        sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        
        # Start Docker
        sudo systemctl start docker
        sudo systemctl enable docker
    else
        log "ERROR" "Unsupported package manager for Docker installation"
        exit 1
    fi
    
    # Add current user to docker group
    sudo usermod -aG docker "$USER"
    log "INFO" "Added $USER to the docker group"
    log "WARNING" "You may need to log out and back in for group changes to take effect"
    
    # Verify installation
    if ! command_exists docker; then
        log "ERROR" "Docker installation failed"
        exit 1
    fi
    
    docker_version=$(docker --version)
    log "INFO" "Docker installed successfully: $docker_version"
}

# Install Node.js and npm with proper error handling
install_nodejs() {
    log "INFO" "Installing Node.js and npm..."
    
    # Install nvm (Node Version Manager)
    if [[ ! -d "$HOME/.nvm" ]]; then
        log "INFO" "Installing nvm..."
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash || {
            log "ERROR" "Failed to install nvm"
            exit 1
        }
    else
        log "INFO" "nvm is already installed"
    fi
    
    # Load nvm
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
    
    # Verify nvm installation
    if ! command_exists nvm; then
        log "ERROR" "nvm installation failed or nvm command not available"
        log "INFO" "Attempting to continue with system Node.js if available"
    else
        log "INFO" "Installing LTS version of Node.js..."
        nvm install --lts || {
            log "ERROR" "Failed to install Node.js LTS version"
            exit 1
        }
        nvm use --lts || {
            log "ERROR" "Failed to use Node.js LTS version"
            exit 1
        }
    fi
    
    # Verify Node.js and npm installation
    if ! command_exists node || ! command_exists npm; then
        log "ERROR" "Node.js or npm installation failed"
        exit 1
    fi
    
    node_version=$(node -v)
    npm_version=$(npm -v)
    log "INFO" "Node.js installed successfully: $node_version"
    log "INFO" "npm installed successfully: $npm_version"
}

# Install AWS CDK with proper error handling
install_cdk() {
    log "INFO" "Installing AWS CDK..."
    
    if command_exists cdk; then
        cdk_version=$(cdk --version)
        log "INFO" "AWS CDK is already installed: $cdk_version"
        
        # Check if we need to install a specific version
        if [[ "$cdk_version" != *"2.177.0"* ]]; then
            log "INFO" "Installing specific AWS CDK version 2.177.0..."
            npm install -g aws-cdk@2.177.0 || {
                log "ERROR" "Failed to install AWS CDK version 2.177.0"
                exit 1
            }
        fi
    else
        log "INFO" "Installing AWS CDK version 2.177.0..."
        npm install -g aws-cdk@2.177.0 || {
            log "ERROR" "Failed to install AWS CDK"
            exit 1
        }
    fi
    
    # Verify installation
    if ! command_exists cdk; then
        log "ERROR" "AWS CDK installation failed"
        exit 1
    fi
    
    cdk_version=$(cdk --version)
    log "INFO" "AWS CDK installed successfully: $cdk_version"
}

# Prepare code dependencies with proper error handling
prepare_code_dependency() {
    log "INFO" "Preparing code dependencies..."
    
    # Check if CDK_DIR is defined and exists
    if [[ -z "$CDK_DIR" ]]; then
        log "ERROR" "CDK_DIR is not defined in env.sh"
        exit 1
    fi
    
    if [[ ! -d "$CDK_DIR" ]]; then
        log "ERROR" "CDK directory does not exist: $CDK_DIR"
        exit 1
    fi
    
    # Navigate to CDK directory and install dependencies
    log "INFO" "Installing npm dependencies in $CDK_DIR..."
    pushd "$CDK_DIR" > /dev/null
    
    npm install --force || {
        log "ERROR" "Failed to install npm dependencies"
        popd > /dev/null
        exit 1
    }
    
    # Bootstrap CDK
    log "INFO" "Bootstrapping CDK..."
    cdk bootstrap || {
        log "ERROR" "Failed to bootstrap CDK"
        popd > /dev/null
        exit 1
    }
    
    # List CDK stacks
    log "INFO" "Listing CDK stacks..."
    cdk list || {
        log "ERROR" "Failed to list CDK stacks"
        popd > /dev/null
        exit 1
    }
    
    # Update PROJECT_NAME if provided
    if [[ -z "$PROJECT_NAME" ]]; then
        log "INFO" "PROJECT_NAME is not provided, using default empty value"
    else
        log "INFO" "Updating PROJECT_NAME to: $PROJECT_NAME"
        
        # Check if env.ts exists
        if [[ ! -f "$CDK_DIR/env.ts" ]]; then
            log "ERROR" "env.ts file not found in $CDK_DIR"
            popd > /dev/null
            exit 1
        }
        
        # Update PROJECT_NAME in env.ts
        sed -i.bak "s/export const PROJECT_NAME =.*/export const PROJECT_NAME = '${PROJECT_NAME}'/g" "$CDK_DIR/env.ts" || {
            log "ERROR" "Failed to update PROJECT_NAME in env.ts"
            popd > /dev/null
            exit 1
        }
        
        log "INFO" "Stacks after updating PROJECT_NAME:"
        cdk list || {
            log "ERROR" "Failed to list CDK stacks after updating PROJECT_NAME"
            popd > /dev/null
            exit 1
        }
    fi
    
    popd > /dev/null
    log "INFO" "Code dependencies prepared successfully"
}

# Main function to orchestrate the installation process
main() {
    log "INFO" "Starting environment preparation..."
    
    check_not_root
    detect_os
    install_dependencies
    install_awscli
    install_eksctl
    install_kubectl
    install_docker
    install_nodejs
    install_cdk
    prepare_code_dependency
    
    log "INFO" "Environment preparation completed successfully"
    
    # Remind user about Docker group
    if [[ "$OS" == "linux" ]]; then
        log "REMINDER" "You may need to log out and back in for Docker group changes to take effect"
        log "REMINDER" "Alternatively, run: newgrp docker"
    fi
}

# Execute main function
main "$@"
