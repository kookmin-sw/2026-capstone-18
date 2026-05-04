#!/usr/bin/env bash
set -euo pipefail

export AWS_PROFILE="${AWS_PROFILE:-little-signals-staging}"
export AWS_REGION="${AWS_REGION:-ap-northeast-2}"

STATE_BUCKET="${STATE_BUCKET:-little-signals-tfstate-apne2}"
LOCK_TABLE="${LOCK_TABLE:-little-signals-terraform-locks}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

BUCKET_ERROR="$TMP_DIR/create-bucket.err"
if aws s3api create-bucket \
  --bucket "$STATE_BUCKET" \
  --region "$AWS_REGION" \
  --create-bucket-configuration LocationConstraint="$AWS_REGION" \
  2>"$BUCKET_ERROR"; then
  :
else
  status=$?
  if grep -q "BucketAlreadyOwnedByYou" "$BUCKET_ERROR"; then
    echo "Terraform state bucket already exists: $STATE_BUCKET"
  else
    cat "$BUCKET_ERROR" >&2
    exit "$status"
  fi
fi

aws s3api put-bucket-versioning \
  --bucket "$STATE_BUCKET" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket "$STATE_BUCKET" \
  --server-side-encryption-configuration '{
    "Rules": [
      {
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        }
      }
    ]
  }'

TABLE_ERROR="$TMP_DIR/create-table.err"
if aws dynamodb create-table \
  --table-name "$LOCK_TABLE" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$AWS_REGION" \
  2>"$TABLE_ERROR"; then
  :
else
  status=$?
  if grep -q "ResourceInUseException" "$TABLE_ERROR"; then
    echo "Terraform lock table already exists: $LOCK_TABLE"
  else
    cat "$TABLE_ERROR" >&2
    exit "$status"
  fi
fi

aws dynamodb wait table-exists \
  --table-name "$LOCK_TABLE" \
  --region "$AWS_REGION"

echo "Terraform state bucket: $STATE_BUCKET"
echo "Terraform lock table: $LOCK_TABLE"
