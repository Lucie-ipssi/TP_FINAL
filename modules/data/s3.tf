# =============================================================================
# modules/data/s3.tf
# 2 buckets S3 :
#   - primary : stockage des fichiers Nextcloud (chiffre KMS, versioning)
#   - logs    : logs d acces ALB (SSE-AES256 obligatoire — ALB refuse SSE-KMS)
# =============================================================================
# Pour CHAQUE bucket, declarer :
#
#   - aws_s3_bucket                               (le bucket)
#   - aws_s3_bucket_versioning                    (enabled)          [primary uniquement]
#   - aws_s3_bucket_server_side_encryption_configuration
#   - aws_s3_bucket_public_access_block           (les 4 a true)
#   - aws_s3_bucket_policy                        (deny non-TLS + specifique ALB pour logs)
#
# Pour le bucket "logs" uniquement : aws_s3_bucket_lifecycle_configuration
#   - transition vers GLACIER_IR a 30 jours
#   - expiration a 90 jours
# =============================================================================

# -----------------------------------------------------------------------------
# BUCKET PRIMARY (stockage fichiers Nextcloud)
# -----------------------------------------------------------------------------

# TODO(role-4) : aws_s3_bucket "primary"
#   bucket = "${local.name_prefix}-nextcloud-${random_id.suffix.hex}"
#   force_destroy = true    (dev uniquement — permet destroy meme si bucket non-vide)
resource "aws_s3_bucket" "primary" {
  bucket        = "${local.name_prefix}-nextcloud-${random_id.suffix.hex}"
  force_destroy = true
}
# TODO(role-4) : aws_s3_bucket_versioning "primary"
#   versioning_configuration { status = "Enabled" }
resource "aws_s3_bucket_versioning" "primary" {
  bucket = aws_s3_bucket.primary.id
  versioning_configuration {
    status = "Enabled"
  }
}
# TODO(role-4) : aws_s3_bucket_server_side_encryption_configuration "primary"
#   rule {
#     apply_server_side_encryption_by_default {
#       sse_algorithm     = "aws:kms"
#       kms_master_key_id = var.kms_key_arn
#     }
#     bucket_key_enabled = true
#   }
resource "aws_s3_bucket_server_side_encryption_configuration" "primary" {
  bucket = aws_s3_bucket.primary.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}
# TODO(role-4) : aws_s3_bucket_public_access_block "primary"
#   block_public_acls       = true
#   block_public_policy     = true
#   ignore_public_acls      = true
#   restrict_public_buckets = true
resource "aws_s3_bucket_public_access_block" "primary" {
  bucket = aws_s3_bucket.primary.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
# TODO(role-4) : aws_s3_bucket_policy "primary"
#   policy : deny si aws:SecureTransport = false
resource "aws_s3_bucket_policy" "primary" {
  bucket = aws_s3_bucket.primary.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnforceTLSRequestsOnly"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.primary.arn,
          "${aws_s3_bucket.primary.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}
# -----------------------------------------------------------------------------
# BUCKET LOGS (access logs ALB)
# -----------------------------------------------------------------------------

# 🟡 ATTENTION : l ALB ne sait pas ecrire dans un bucket chiffre SSE-KMS
#   (limitation AWS documentee). On utilise SSE-AES256 pour ce bucket uniquement.

# TODO(role-4) : aws_s3_bucket "logs"
resource "aws_s3_bucket" "logs" {
  bucket        = "${local.name_prefix}-logs-${random_id.suffix.hex}"
  force_destroy = true
}
# TODO(role-4) : aws_s3_bucket_server_side_encryption_configuration "logs"
#   avec sse_algorithm = "AES256" (pas KMS !)
resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
# TODO(role-4) : aws_s3_bucket_public_access_block "logs"
resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
# TODO(role-4) : aws_s3_bucket_policy "logs"
#   Doit autoriser data.aws_elb_service_account.main.arn a PutObject.
#   Pattern :
#     data "aws_iam_policy_document" "alb_logs" {
#       statement {
#         principals {
#           type        = "AWS"
#           identifiers = [data.aws_elb_service_account.main.arn]
#         }
#         actions   = ["s3:PutObject"]
#         resources = ["${aws_s3_bucket.logs.arn}/*"]
#       }
#       # + statement deny non-TLS
#     }
data "aws_iam_policy_document" "alb_logs" {
  statement {
    sid    = "AllowALBPutObject"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.main.arn]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.logs.arn}/*"]
  }

  statement {
    sid    = "EnforceTLSRequestsOnly"
    effect = "Deny"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.logs.arn,
      "${aws_s3_bucket.logs.arn}/*"
    ]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = data.aws_iam_policy_document.alb_logs.json
}
# TODO(role-4) : aws_s3_bucket_lifecycle_configuration "logs"
#   rule {
#     id     = "archive-30d-expire-90d"
#     status = "Enabled"
#     transition { days = 30  storage_class = "GLACIER_IR" }
#     expiration { days = 90 }
#   }
resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "archive-30d-expire-90d"
    status = "Enabled"

    filter {}

    transition {
      days          = 30
      storage_class = "GLACIER_IR"
    }

    expiration {
      days = 90
    }
  }
}