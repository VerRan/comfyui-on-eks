
prepare_code_dependency() {
    echo "==== Preparing code dependencies ===="
    if [[ ! -d "$CDK_DIR" ]]; then
        echo "CDK directory $CDK_DIR does not exist."
        exit 1
    fi
    
    cd "$CDK_DIR" || exit 1
    npm install --force
    npm list
    
    # Bootstrap CDK and list stacks
    cdk bootstrap
    cdk list
    
    # Update PROJECT_NAME if provided
    if [[ -n "$PROJECT_NAME" ]]; then
        if [[ "$OS_TYPE" == "macos" ]]; then
            sed -i '' "s/export const PROJECT_NAME =.*/export const PROJECT_NAME = '${PROJECT_NAME}'/g" "$CDK_DIR/env.ts"
        else
            sed -i "s/export const PROJECT_NAME =.*/export const PROJECT_NAME = '${PROJECT_NAME}'/g" "$CDK_DIR/env.ts"
        fi
        echo "Stacks after updating PROJECT_NAME: $PROJECT_NAME"
        cdk list
    else
        echo "PROJECT_NAME is not provided, using default empty value."
    fi
}