#!/usr/bin/env bash
# One-time AWS setup for the chatbot's deployment target. Safe to re-run.
#
# Creates:
#   - ECR repository (scan-on-push, keeps the last 10 images)
#   - Lambda function running the container image, with a public Function URL
#   - GitHub OIDC identity provider + a least-privilege IAM role that the
#     pipeline assumes, so no long-lived AWS keys are stored in GitHub
#
# Usage: AWS_PROFILE=<admin-profile> ./infra/aws-bootstrap.sh
set -euo pipefail

REGION="${AWS_REGION:-ap-south-1}"
export AWS_REGION="$REGION" AWS_DEFAULT_REGION="$REGION"
APP="chatbot-api"
GITHUB_REPO="${GITHUB_REPO:-ANUJ7MADKE/chatbot-cicd-pipeline}"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGISTRY="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"
ECR_URI="$REGISTRY/$APP"
OIDC_HOST="token.actions.githubusercontent.com"
OIDC_ARN="arn:aws:iam::$ACCOUNT_ID:oidc-provider/$OIDC_HOST"
LAMBDA_ROLE="$APP-lambda-role"
DEPLOY_ROLE="$APP-github-deploy"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

step() { printf '\n==> %s\n' "$*"; }

step "ECR repository: $APP"
if ! aws ecr describe-repositories --repository-names "$APP" >/dev/null 2>&1; then
  aws ecr create-repository --repository-name "$APP" \
    --image-scanning-configuration scanOnPush=true >/dev/null
fi
aws ecr put-lifecycle-policy --repository-name "$APP" --lifecycle-policy-text '{
  "rules": [{
    "rulePriority": 1,
    "description": "Keep only the 10 most recent images",
    "selection": {"tagStatus": "any", "countType": "imageCountMoreThan", "countNumber": 10},
    "action": {"type": "expire"}
  }]
}' >/dev/null

step "Seed image (Lambda needs an image to exist before the function is created)"
if ! aws ecr describe-images --repository-name "$APP" --image-ids imageTag=bootstrap >/dev/null 2>&1; then
  aws ecr get-login-password | docker login --username AWS --password-stdin "$REGISTRY"
  # provenance=false: Lambda only accepts single-platform image manifests
  docker buildx build --platform linux/amd64 --provenance=false \
    -t "$ECR_URI:bootstrap" --push "$SCRIPT_DIR/.."
fi

step "Lambda execution role: $LAMBDA_ROLE"
if ! aws iam get-role --role-name "$LAMBDA_ROLE" >/dev/null 2>&1; then
  aws iam create-role --role-name "$LAMBDA_ROLE" --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{"Effect": "Allow", "Principal": {"Service": "lambda.amazonaws.com"}, "Action": "sts:AssumeRole"}]
  }' >/dev/null
  aws iam attach-role-policy --role-name "$LAMBDA_ROLE" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
fi

step "CloudWatch log group (7-day retention)"
aws logs create-log-group --log-group-name "/aws/lambda/$APP" 2>/dev/null || true
aws logs put-retention-policy --log-group-name "/aws/lambda/$APP" --retention-in-days 7

step "Lambda function: $APP"
if ! aws lambda get-function --function-name "$APP" >/dev/null 2>&1; then
  # Retry while the new IAM role propagates
  for attempt in 1 2 3 4 5 6; do
    if aws lambda create-function --function-name "$APP" --package-type Image \
         --code ImageUri="$ECR_URI:bootstrap" \
         --role "arn:aws:iam::$ACCOUNT_ID:role/$LAMBDA_ROLE" \
         --architectures x86_64 --memory-size 512 --timeout 30 >/dev/null; then
      break
    fi
    echo "   role not ready yet, retrying ($attempt/6)..."; sleep 10
  done
fi
aws lambda wait function-active-v2 --function-name "$APP"

step "Public Function URL"
if ! aws lambda get-function-url-config --function-name "$APP" >/dev/null 2>&1; then
  aws lambda create-function-url-config --function-name "$APP" --auth-type NONE >/dev/null
fi
aws lambda add-permission --function-name "$APP" --statement-id public-url \
  --action lambda:InvokeFunctionUrl --principal "*" --function-url-auth-type NONE >/dev/null 2>&1 || true
FUNCTION_URL=$(aws lambda get-function-url-config --function-name "$APP" --query FunctionUrl --output text)

step "GitHub OIDC identity provider"
if ! aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN" >/dev/null 2>&1; then
  aws iam create-open-id-connect-provider --url "https://$OIDC_HOST" \
    --client-id-list sts.amazonaws.com \
    --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 >/dev/null
fi

step "Pipeline deploy role: $DEPLOY_ROLE (trusted only from $GITHUB_REPO main / production)"
# GitHub's OIDC subject embeds the immutable owner and repository IDs
# (repo:OWNER@OWNER_ID/REPO@REPO_ID:...), so a deleted-and-recreated repo or a
# re-registered username cannot impersonate this one. Trust both the ID form
# and the legacy name-only form, each as an exact string.
REPO_IDS=$(curl -fsS "https://api.github.com/repos/$GITHUB_REPO" \
  | python3 -c 'import json,sys; r=json.load(sys.stdin); print(r["owner"]["login"], r["owner"]["id"], r["name"], r["id"])')
read -r OWNER OWNER_ID REPO_NAME REPO_ID <<<"$REPO_IDS"
ID_REPO="$OWNER@$OWNER_ID/$REPO_NAME@$REPO_ID"
TRUST=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Federated": "$OIDC_ARN"},
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "$OIDC_HOST:aud": "sts.amazonaws.com",
        "$OIDC_HOST:sub": [
          "repo:$ID_REPO:ref:refs/heads/main",
          "repo:$ID_REPO:environment:production",
          "repo:$GITHUB_REPO:ref:refs/heads/main",
          "repo:$GITHUB_REPO:environment:production"
        ]
      }
    }
  }]
}
EOF
)
if aws iam get-role --role-name "$DEPLOY_ROLE" >/dev/null 2>&1; then
  aws iam update-assume-role-policy --role-name "$DEPLOY_ROLE" --policy-document "$TRUST"
else
  aws iam create-role --role-name "$DEPLOY_ROLE" --assume-role-policy-document "$TRUST" >/dev/null
fi
aws iam put-role-policy --role-name "$DEPLOY_ROLE" --policy-name deploy-chatbot --policy-document "$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {"Sid": "EcrAuth", "Effect": "Allow", "Action": "ecr:GetAuthorizationToken", "Resource": "*"},
    {"Sid": "EcrPush", "Effect": "Allow", "Resource": "arn:aws:ecr:$REGION:$ACCOUNT_ID:repository/$APP",
     "Action": ["ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart",
                "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:BatchGetImage",
                "ecr:GetDownloadUrlForLayer"]},
    {"Sid": "LambdaDeploy", "Effect": "Allow", "Resource": "arn:aws:lambda:$REGION:$ACCOUNT_ID:function:$APP",
     "Action": ["lambda:UpdateFunctionCode", "lambda:GetFunction",
                "lambda:GetFunctionConfiguration", "lambda:GetFunctionUrlConfig"]}
  ]
}
EOF
)"

cat <<EOF

============================================================
 Done. Add this as a GitHub repository secret:
   AWS_ROLE_ARN = arn:aws:iam::$ACCOUNT_ID:role/$DEPLOY_ROLE
 Live chatbot URL:
   $FUNCTION_URL
============================================================
EOF
