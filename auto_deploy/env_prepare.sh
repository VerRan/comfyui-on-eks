#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status

source ./env.sh

# Detect OS for cross-platform compatibility
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        export OS_TYPE="linux"
        export PACKAGE_MANAGER="apt-get"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        export OS_TYPE="macos"
        export PACKAGE_MANAGER="brew"
    else
        echo "Unsupported OS: $OSTYPE"
        exit 1
    fi
    
    # Detect architecture
    if [[ $(uname -m) == "x86_64" ]]; then
        export ARCH="amd64"
    elif [[ $(uname -m) == "arm64" ]]; then
        export ARCH="arm64"
    else
        export ARCH="amd64"  # Default to amd64
    fi
    
    echo "Detected OS: $OS_TYPE, Architecture: $ARCH"
}

# Check if a command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Install basic dependencies based on OS
install_dependencies() {
    echo "==== Installing basic dependencies ===="
    if [[ "$OS_TYPE" == "linux" ]]; then
        sudo $PACKAGE_MANAGER update
        sudo $PACKAGE_MANAGER install -yy unzip curl ca-certificates
    elif [[ "$OS_TYPE" == "macos" ]]; then
        if ! command_exists brew; then
            echo "Homebrew not found. Installing..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        fi
        brew install curl unzip
    fi
}

install_awscli() {
    echo "==== Installing AWS CLI ===="
    if command_exists aws; then
        echo "AWS CLI is already installed: $(aws --version)"
    else
        echo "Installing AWS CLI..."
        if [[ "$OS_TYPE" == "linux" ]]; then
            curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
            unzip -q awscliv2.zip
            sudo ./aws/install
            rm -rf awscliv2.zip aws
        elif [[ "$OS_TYPE" == "macos" ]]; then
            curl -s "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
            sudo installer -pkg AWSCLIV2.pkg -target /
            rm -f AWSCLIV2.pkg
        fi
    fi
    
    # Verify installation
    if ! aws --version; then
        echo "AWS CLI installation failed."
        exit 1
    fi
    
    # Check AWS credentials
    if ! iam_entity=$(aws sts get-caller-identity --query 'Arn' --output text --no-cli-pager 2>/dev/null); then
        echo "AWS CLI is not configured. Please choose one of the following options:"
        echo "1. Run 'aws configure' to configure AWS CLI"
        echo "2. Add IAM role later"
        read -p "Enter your choice (1/2): " choice
        if [[ $choice -eq 1 ]]; then
            aws configure
        fi
    else
        echo "Using IAM entity: $iam_entity"
        echo "Make sure this entity has necessary permissions to create resources."
    fi
}

install_eksctl() {
    echo "==== Installing eksctl ===="
    if command_exists eksctl; then
        echo "eksctl is already installed: $(eksctl version)"
        return
    fi
    
    PLATFORM=$(uname -s)_$ARCH
    echo "Downloading eksctl for $PLATFORM..."
    curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
    tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
    
    if [[ "$OS_TYPE" == "linux" ]]; then
        sudo mv /tmp/eksctl /usr/local/bin
    elif [[ "$OS_TYPE" == "macos" ]]; then
        sudo mv /tmp/eksctl /usr/local/bin
    fi
    
    if ! eksctl version; then
        echo "eksctl installation failed."
        exit 1
    fi
}

install_kubectl() {
    echo "==== Installing kubectl ===="
    if command_exists kubectl; then
        echo "kubectl is already installed: $(kubectl version --client)"
        return
    fi
    
    KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
    
    if [[ "$OS_TYPE" == "linux" ]]; then
        curl -sLO "https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/$ARCH/kubectl"
        sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
        rm -f kubectl
    elif [[ "$OS_TYPE" == "macos" ]]; then
        curl -sLO "https://dl.k8s.io/release/$KUBECTL_VERSION/bin/darwin/$ARCH/kubectl"
        chmod +x kubectl
        sudo mv kubectl /usr/local/bin/
    fi
    
    if ! kubectl version --client; then
        echo "kubectl installation failed."
        exit 1
    fi
}

install_docker() {
    echo "==== Installing Docker ===="
    if command_exists docker; then
        echo "Docker is already installed: $(docker --version)"
        return
    fi
    
    if [[ "$OS_TYPE" == "linux" ]]; then
        # Add Docker's official GPG key
        sudo $PACKAGE_MANAGER update
        sudo $PACKAGE_MANAGER install -yy ca-certificates curl
        sudo install -m 0755 -d /etc/apt/keyrings
        sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
        sudo chmod a+r /etc/apt/keyrings/docker.asc

        # Add the repository to Apt sources
        echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        sudo $PACKAGE_MANAGER update
        sudo $PACKAGE_MANAGER install -yy docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        sudo usermod -aG docker $USER
        echo "Docker installed. You may need to log out and back in for group changes to take effect."
    elif [[ "$OS_TYPE" == "macos" ]]; then
        echo "For macOS, please install Docker Desktop from https://www.docker.com/products/docker-desktop/"
        echo "After installation, press any key to continue..."
        read -n 1
    fi
    
    # Verify docker installation
    if ! docker --version; then
        echo "Docker installation verification failed."
        exit 1
    fi
}

install_node() {
    echo "==== Installing Node.js and npm ===="
    if command_exists node && command_exists npm; then
        echo "Node.js ($(node -v)) and npm ($(npm -v)) are already installed."
        return
    fi
    
    # Install nvm
    if ! command_exists nvm; then
        echo "Installing nvm..."
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # Load nvm
        [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # Load nvm bash_completion
    fi
    sudo apt install -y nodejs 
    
    # Install LTS version of Node.js
    nvm install --lts
    nvm use --lts
    
    echo "Node version: $(node -v)"
    echo "NPM version: $(npm -v)"
}

install_cdk() {
    echo "==== Installing AWS CDK ===="
    if command_exists cdk; then
        echo "AWS CDK is already installed: $(cdk --version)"
        return
    fi
    
    npm install -g aws-cdk@2.177.0
    
    if ! cdk --version; then
        echo "AWS CDK installation failed."
        exit 1
    fi
}


main() {
    detect_os
    install_dependencies
    install_awscli
    install_eksctl
    install_kubectl
    install_docker
    install_node
    install_cdk
    # prepare_code_dependency
    
    echo "==== Environment preparation completed successfully ===="
}

main
