#!/usr/bin/env bash
# Removes everything created by aws-bootstrap.sh (run after the IA is graded).
# The GitHub OIDC provider is kept because other repos in the account may use it;
# pass --all to delete it too.
#
# Usage: AWS_PROFILE=<admin-profile> ./infra/aws-teardown.sh [--all]
set -uo pipefail

REGION="${AWS_REGION:-ap-south-1}"
export AWS_REGION="$REGION" AWS_DEFAULT_REGION="$REGION"
APP="chatbot-api"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws lambda delete-function-url-config --function-name "$APP" 2>/dev/null
aws lambda delete-function --function-name "$APP" 2>/dev/null
aws logs delete-log-group --log-group-name "/aws/lambda/$APP" 2>/dev/null
aws ecr delete-repository --repository-name "$APP" --force >/dev/null 2>&1

aws iam delete-role-policy --role-name "$APP-github-deploy" --policy-name deploy-chatbot 2>/dev/null
aws iam delete-role --role-name "$APP-github-deploy" 2>/dev/null
aws iam detach-role-policy --role-name "$APP-lambda-role" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null
aws iam delete-role --role-name "$APP-lambda-role" 2>/dev/null

if [ "${1:-}" = "--all" ]; then
  aws iam delete-open-id-connect-provider \
    --open-id-connect-provider-arn "arn:aws:iam::$ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com" 2>/dev/null
fi
echo "Teardown complete."
