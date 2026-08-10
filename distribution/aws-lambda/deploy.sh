#!/usr/bin/env bash
# One-time setup: creates the DynamoDB table, IAM execution role, Lambda function, and a
# public Function URL for index.mjs — the AWS equivalent of the Cloudflare Worker in
# distribution/cloudflare-worker/. Safe to re-run: skips anything that already exists,
# and updates the function code if the function is already there.
#
# Requires: aws CLI (already authenticated — `aws sts get-caller-identity` should work)
set -euo pipefail

REGION="${AWS_REGION:-ap-south-1}"
TABLE_NAME="${TABLE_NAME:-PulseSipCustomerConfigs}"
FUNCTION_NAME="${FUNCTION_NAME:-pulse-sip-auth}"
ROLE_NAME="${ROLE_NAME:-pulse-sip-auth-lambda-role}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "Account: $ACCOUNT_ID   Region: $REGION"

# --- DynamoDB table ---------------------------------------------------------
if aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$REGION" >/dev/null 2>&1; then
  echo "DynamoDB table $TABLE_NAME already exists — skipping."
else
  echo "Creating DynamoDB table $TABLE_NAME..."
  aws dynamodb create-table \
    --table-name "$TABLE_NAME" \
    --attribute-definitions AttributeName=pk,AttributeType=S \
    --key-schema AttributeName=pk,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$REGION" >/dev/null
  aws dynamodb wait table-exists --table-name "$TABLE_NAME" --region "$REGION"
  aws dynamodb update-time-to-live \
    --table-name "$TABLE_NAME" \
    --time-to-live-specification "Enabled=true,AttributeName=ttl" \
    --region "$REGION" >/dev/null
fi

# --- IAM execution role ------------------------------------------------------
if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  echo "IAM role $ROLE_NAME already exists — skipping."
else
  echo "Creating IAM role $ROLE_NAME..."
  TRUST_POLICY='{
    "Version": "2012-10-17",
    "Statement": [{"Effect": "Allow", "Principal": {"Service": "lambda.amazonaws.com"}, "Action": "sts:AssumeRole"}]
  }'
  aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document "$TRUST_POLICY" >/dev/null
  aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
  aws iam put-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-name pulse-sip-auth-dynamodb \
    --policy-document "$(jq -n --arg tableArn "arn:aws:dynamodb:$REGION:$ACCOUNT_ID:table/$TABLE_NAME" \
      '{Version: "2012-10-17", Statement: [{Effect: "Allow", Action: ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"], Resource: $tableArn}]}')"
  echo "Waiting for IAM role to propagate..."
  sleep 10
fi

ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)

# --- Lambda function ---------------------------------------------------------
echo "Installing Lambda dependencies..."
(cd "$SCRIPT_DIR" && npm install --omit=dev --silent)

ZIP_PATH="$SCRIPT_DIR/function.zip"
rm -f "$ZIP_PATH"
(cd "$SCRIPT_DIR" && zip -q -r "$ZIP_PATH" index.mjs node_modules)

if aws lambda get-function --function-name "$FUNCTION_NAME" --region "$REGION" >/dev/null 2>&1; then
  echo "Lambda function $FUNCTION_NAME already exists — updating code..."
  aws lambda update-function-code \
    --function-name "$FUNCTION_NAME" \
    --zip-file "fileb://$ZIP_PATH" \
    --region "$REGION" >/dev/null
else
  echo "Creating Lambda function $FUNCTION_NAME..."
  aws lambda create-function \
    --function-name "$FUNCTION_NAME" \
    --runtime nodejs20.x \
    --handler index.handler \
    --role "$ROLE_ARN" \
    --zip-file "fileb://$ZIP_PATH" \
    --environment "Variables={TABLE_NAME=$TABLE_NAME}" \
    --timeout 10 \
    --region "$REGION" >/dev/null
  aws lambda wait function-active --function-name "$FUNCTION_NAME" --region "$REGION"
fi
rm -f "$ZIP_PATH"

# --- Public Function URL ------------------------------------------------------
if FUNCTION_URL=$(aws lambda get-function-url-config --function-name "$FUNCTION_NAME" --region "$REGION" --query FunctionUrl --output text 2>/dev/null); then
  echo "Function URL already configured."
else
  echo "Creating public Function URL..."
  FUNCTION_URL=$(aws lambda create-function-url-config \
    --function-name "$FUNCTION_NAME" \
    --auth-type NONE \
    --region "$REGION" \
    --query FunctionUrl --output text)
  aws lambda add-permission \
    --function-name "$FUNCTION_NAME" \
    --statement-id FunctionURLAllowPublicAccess \
    --action lambda:InvokeFunctionUrl \
    --principal "*" \
    --function-url-auth-type NONE \
    --region "$REGION" >/dev/null
fi

echo ""
echo "Deployed. Your baseUrl for PulseSipSdk.registerWithCredentials() is:"
echo "  ${FUNCTION_URL%/}"
