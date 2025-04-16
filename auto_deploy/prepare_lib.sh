prepare_code_dependency() {
    echo "==== Start preparing code ===="
    cd $CDK_DIR && npm install --force && npm list && cdk bootstrap && cdk list
    if [[ $? -ne 0 ]]
    then
        echo "Code preparation failed."
        exit 1
    fi
    if [[ -z $PROJECT_NAME ]]
    then
        echo "PROJECT_NAME is not provided, use default empty."
    else
        sed -i "s/export const PROJECT_NAME =.*/export const PROJECT_NAME = '${PROJECT_NAME}'/g" $CDK_DIR/env.ts
        echo "Stacks after updating PROJECT_NAME: $PROJECT_NAME"
        cd $CDK_DIR && cdk list
    fi
    echo "==== Finish preparing code ===="
}

prepare_code_dependency