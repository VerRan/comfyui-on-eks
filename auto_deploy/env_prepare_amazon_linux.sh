#!/bin/bash

source ./env.sh

install_dependencies() {
    echo "==== Installing basic dependencies ===="
    sudo yum update -y
    sudo yum install -y unzip curl wget git
}

install_awscli() {
    echo "==== Start installing AWS CLI ===="
    curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -q awscliv2.zip
    if ! command -v aws &> /dev/null; then
        echo "AWS CLI not found, installing..."
        sudo ./aws/install
    else
        echo "AWS CLI is already installed, updating..."
        sudo ./aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update
    fi
    rm -rf awscliv2.zip aws
    aws --version
    if [[ $? -ne 0 ]]; then
        echo "AWS CLI installation failed."
        exit 1
    fi
    iam_entity=$(aws sts get-caller-identity --query 'Arn' --output text --no-cli-pager)
    if [[ $? -ne 0 ]]; then
        # Get user input for choosing 1. aws configure 2. Add iam role later
        echo "AWS CLI is not configured. Please choose one of the following options:"
        echo "1. Run 'aws configure' to configure AWS CLI"
        echo "2. Add IAM role later"
        read -p "Enter your choice (1/2): " choice
        if [[ $choice -eq 1 ]]; then
            aws configure
        fi
    else
        echo "Make sure current IAM entity '$iam_entity' has necessary permissions to create resources."
    fi
    echo "==== Finish installing AWS CLI ===="
}

install_eksctl() {
    echo "==== Start installing eksctl ===="
    ARCH=amd64
    PLATFORM=$(uname -s)_$ARCH
    curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
    tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
    sudo mv /tmp/eksctl /usr/local/bin
    eksctl version
    if [[ $? -ne 0 ]]; then
        echo "eksctl installation failed."
        exit 1
    fi
    echo "==== Finish installing eksctl ===="
}

install_kubectl() {
    echo "==== Start installing kubectl ===="
    curl -sLO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm kubectl
    kubectl version --client
    if [[ $? -ne 0 ]]; then
        echo "kubectl installation failed."
        exit 1
    fi
    echo "==== Finish installing kubectl ===="
}

install_docker() {
    echo "==== Start installing Docker ===="
    # Amazon Linux specific Docker installation
    if grep -q "Amazon Linux 2" /etc/os-release; then
        # Amazon Linux 2
        sudo amazon-linux-extras install -y docker
    else
        # Amazon Linux 2023
        sudo yum install -y docker
    fi
    
    # Start and enable Docker service
    sudo systemctl start docker
    sudo systemctl enable docker
    
    # Add current user to docker group
    sudo usermod -aG docker $USER
    echo "NOTE: You may need to log out and log back in for docker group changes to take effect"
    
    # Verify installation
    sudo docker --version
    if [[ $? -ne 0 ]]; then
        echo "Docker installation failed."
        exit 1
    fi
    echo "==== Finish installing Docker ===="
}

install_npm() {
    echo "==== Start installing npm ===="

    # Install nvm
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
    
    # Verify nvm installation
    command -v nvm
    if [[ $? -ne 0 ]]; then
        echo "NVM installation failed. Trying to source NVM manually..."
        source ~/.bashrc
        command -v nvm
        if [[ $? -ne 0 ]]; then
            echo "Failed to install NVM. Please install manually."
            exit 1
        fi
    fi

    # Install lts version of node
    nvm install --lts
    nvm use --lts
    if [[ $? -ne 0 ]]; then
        echo "Node.js installation failed."
        exit 1
    fi
    echo "Node version: $(node -v)"
    echo "NPM version: $(npm -v)"
    echo "==== Finish installing npm ===="
}

install_cdk() {
    echo "==== Start installing AWS CDK ===="
    npm install -g aws-cdk@2.177.0
    cdk --version
    if [[ $? -ne 0 ]]; then
        echo "AWS CDK installation failed."
        exit 1
    fi
    echo "==== Finish installing AWS CDK ===="
}

prepare_code_dependency() {
    echo "==== Start preparing code ===="
    cd $CDK_DIR && npm install --force && npm list && cdk bootstrap && cdk list
    if [[ $? -ne 0 ]]; then
        echo "Code preparation failed."
        exit 1
    fi
    if [[ -z $PROJECT_NAME ]]; then
        echo "PROJECT_NAME is not provided, use default empty."
    else
        sed -i "s/export const PROJECT_NAME =.*/export const PROJECT_NAME = '${PROJECT_NAME}'/g" $CDK_DIR/env.ts
        echo "Stacks after updating PROJECT_NAME: $PROJECT_NAME"
        cd $CDK_DIR && cdk list
    fi
    echo "==== Finish preparing code ===="
}

main() {
    echo "Starting environment preparation for Amazon Linux..."
    install_dependencies
    install_awscli
    install_eksctl
    install_kubectl
    install_docker
    install_npm
    install_cdk
    prepare_code_dependency
    echo "Environment preparation completed successfully!"
    echo "NOTE: You may need to log out and log back in for some changes to take effect."
}

main