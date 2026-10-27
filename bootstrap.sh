#!/bin/bash
set -e

REGION=${1:-ap-southeast-2}
BUCKET="research-agent-tfstate-vaipal"
TABLE="research-agent-tf-locks-vaipal"

echo "Creating S3 bucket: $BUCKET in region: $REGION"

if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "Bucket already exists in your account — skipping create."
else
  echo "Bucket not found in your account — creating..."
  if [ "$REGION" = "us-east-1" ]; then
    CREATE_CMD=(aws s3api create-bucket --bucket "$BUCKET" --region "$REGION")
  else
    CREATE_CMD=(aws s3api create-bucket --bucket "$BUCKET" --region "$REGION"
      --create-bucket-configuration "LocationConstraint=$REGION")
  fi
  if ! "${CREATE_CMD[@]}"; then
    echo ""
    echo "ERROR: Could not create S3 bucket '$BUCKET'."
    echo "  - If AccessDenied / SCP: your AWS Organization may block s3:CreateBucket."
    echo "    Use a personal AWS account, ask your admin for a state bucket, or skip deploy (GitHub only)."
    echo "  - If BucketAlreadyExists: the name is taken globally — change BUCKET in bootstrap.sh and terraform/main.tf."
    exit 1
  fi
  echo "Bucket created."
fi

echo "Enabling versioning on S3 bucket..."
aws s3api put-bucket-versioning \
  --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled

echo "Blocking public access on S3 bucket..."
aws s3api put-public-access-block \
  --bucket "$BUCKET" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

echo "Enabling server-side encryption on S3 bucket..."
aws s3api put-bucket-encryption \
  --bucket "$BUCKET" \
  --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

echo "Creating DynamoDB table for Terraform state locking: $TABLE"
if aws dynamodb describe-table --table-name "$TABLE" --region "$REGION" 2>/dev/null; then
  echo "DynamoDB table already exists — skipping create."
else
  aws dynamodb create-table \
    --table-name "$TABLE" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$REGION"
  echo "DynamoDB table created."
fi

echo ""
echo "Bootstrap complete."
echo "  S3 bucket  : $BUCKET (versioned, encrypted, private)"
echo "  DynamoDB   : $TABLE (state locking)"
echo ""
echo "Next step: cd terraform && terraform init && terraform apply"
