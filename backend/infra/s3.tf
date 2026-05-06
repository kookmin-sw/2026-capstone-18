# Sprint 5: encrypted backup bucket + raw-biosignal opt-in bucket.

resource "aws_s3_bucket" "sync" {
  bucket        = "${local.name_prefix}-sync"
  force_destroy = false
}

resource "aws_s3_bucket_versioning" "sync" {
  bucket = aws_s3_bucket.sync.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "sync" {
  bucket                  = aws_s3_bucket.sync.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sync" {
  bucket = aws_s3_bucket.sync.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "sync" {
  bucket = aws_s3_bucket.sync.id
  rule {
    id     = "abort-mpu"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket" "biosignals" {
  bucket        = "${local.name_prefix}-biosignals"
  force_destroy = false
}

resource "aws_s3_bucket_versioning" "biosignals" {
  bucket = aws_s3_bucket.biosignals.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "biosignals" {
  bucket                  = aws_s3_bucket.biosignals.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "biosignals" {
  bucket = aws_s3_bucket.biosignals.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "biosignals" {
  bucket = aws_s3_bucket.biosignals.id
  rule {
    id     = "expire-12mo"
    status = "Enabled"
    filter {}
    expiration {
      days = 365
    }
  }
  rule {
    id     = "abort-mpu"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# IAM policy attached to the ECS task role: object lifecycle on these two
# buckets, nothing else.

data "aws_iam_policy_document" "s3_buckets" {
  statement {
    sid     = "SyncBucketObjectAccess"
    effect  = "Allow"
    actions = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
    resources = [
      "${aws_s3_bucket.sync.arn}/*",
      "${aws_s3_bucket.biosignals.arn}/*",
    ]
  }
  statement {
    sid     = "SyncBucketList"
    effect  = "Allow"
    actions = ["s3:ListBucket"]
    resources = [
      aws_s3_bucket.sync.arn,
      aws_s3_bucket.biosignals.arn,
    ]
  }
}

resource "aws_iam_policy" "s3_buckets" {
  name   = "${local.name_prefix}-s3-buckets"
  policy = data.aws_iam_policy_document.s3_buckets.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_s3" {
  role       = aws_iam_role.ecs_task.name
  policy_arn = aws_iam_policy.s3_buckets.arn
}
