# =============================================================================
# modules/security/iam.tf
# IAM role + instance profile pour les EC2 Nextcloud.
# Policies scopees : Secrets Manager + KMS Decrypt.
# (La policy S3 scope sur le bucket primary est declaree dans envs/dev/main.tf
#  pour eviter la dependance circulaire entre data et security.)
# =============================================================================
# Ressources a declarer :
#
#   - aws_iam_role             "app"   (assume_role_policy pour ec2.amazonaws.com)
#   - aws_iam_role_policy      "app_secrets"  (Allow secretsmanager:GetSecretValue
#                                              sur les 2 secrets ARN)
#   - aws_iam_role_policy      "app_kms"      (Allow kms:Decrypt + kms:DescribeKey
#                                              sur var.kms_key_arn — celle de ce module)
#   - aws_iam_role_policy_attachment "app_ssm"        (bonus, pour SSM Session Manager)
#   - aws_iam_role_policy_attachment "app_cloudwatch" (bonus, pour CW Agent)
#   - aws_iam_instance_profile "app"   (role = aws_iam_role.app.name)
#
# Pattern assume_role_policy :
#   data "aws_iam_policy_document" "assume_ec2" {
#     statement {
#       actions = ["sts:AssumeRole"]
#       principals {
#         type        = "Service"
#         identifiers = ["ec2.amazonaws.com"]
#       }
#     }
#   }
#
# Pattern policy inline :
#   resource "aws_iam_role_policy" "app_secrets" {
#     name = "..."
#     role = aws_iam_role.app.id
#     policy = jsonencode({
#       Version = "2012-10-17"
#       Statement = [{
#         Effect   = "Allow"
#         Action   = ["secretsmanager:GetSecretValue"]
#         Resource = [aws_secretsmanager_secret.db_password.arn,
#                     aws_secretsmanager_secret.admin_password.arn]
#       }]
#     })
#   }
# =============================================================================

resource "aws_iam_role" "app" {
  name = "${local.name_prefix}-app"

  permissions_boundary = "arn:aws:iam::039497794217:policy/formation-permissions-boundary-paris"

  assume_role_policy = data.aws_iam_policy_document.app_assume_role.json
}

data "aws_iam_policy_document" "app_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}
resource "aws_iam_instance_profile" "app" {
  name = "${local.name_prefix}-app"
  role = aws_iam_role.app.name
}
locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
