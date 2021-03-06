data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
}

resource "aws_iam_role" "cloudkeyrotator_role" {
  name = "CloudKeyRotatorRole"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_policy" "ckr_log_policy" {
  name        = "CloudKeyRotatorLogPolicy"
  path        = "/"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": [
                "arn:aws:logs:eu-west-1:${var.account_id}:log-stream:*:*:*",
                "arn:aws:logs:eu-west-1:${var.account_id}:log-group:/aws/lambda/cloud-key-*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": "logs:CreateLogGroup",
            "Resource": "arn:aws:logs:eu-west-1:${var.account_id}:*"
        }
    ]
}
EOF
}


resource "aws_iam_policy" "ckr_ssm_policy" {
  name        = "CloudKeyRotatorSsmPolicy"
  path        = "/"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ssm:PutParameter"
            ],
            "Resource": [
                "arn:aws:ssm:eu-west-1:${var.account_id}:parameter/*"
            ]
        }

    ]
}
EOF
}


resource "aws_iam_role_policy_attachment" "attach-ckr-log-policy" {
  role       = aws_iam_role.cloudkeyrotator_role.name
  policy_arn = aws_iam_policy.ckr_log_policy.arn
}

resource "aws_iam_role_policy_attachment" "attach-ckr-iam-policy" {
  role       = aws_iam_role.cloudkeyrotator_role.name
  policy_arn = "arn:aws:iam::aws:policy/IAMFullAccess"
}
resource "aws_iam_role_policy_attachment" "attach-ckr-secret-policy" {
  role       = aws_iam_role.cloudkeyrotator_role.name
  policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
}

resource "aws_iam_role_policy_attachment" "attach-ckr-ssm-policy" {
  role       = aws_iam_role.cloudkeyrotator_role.name
  policy_arn = aws_iam_policy.ckr_ssm_policy.arn
}

resource "aws_lambda_function" "cloud_key_rotator" {

  filename = "latest.zip"
  function_name = "cloud-key-rotator"
  role          = aws_iam_role.cloudkeyrotator_role.arn
  handler       = "cloud-key-rotator"
  timeout = 300
  runtime = "go1.x"
}

resource "aws_cloudwatch_event_rule" "cloud-key-rotator-trigger" {
    name = "cloud-key-rotator-trigger"
    description = "Daily at 10am"
    schedule_expression = "cron(0 10 ? * MON-FRI *)"
}

resource "aws_cloudwatch_event_target" "check_every_five_minutes" {
    rule = aws_cloudwatch_event_rule.cloud-key-rotator-trigger.name
    target_id = "cloud_key_rotator"
    arn = aws_lambda_function.cloud_key_rotator.arn
}

resource "aws_secretsmanager_secret" "ckr-config-secret" {
  name = "ckr-config"
  description = "Config for cloud-key-rotator running in 'rotation' mode" 
}

resource "aws_secretsmanager_secret_version" "ckr-config-json" {
  secret_id     = aws_secretsmanager_secret.ckr-config-secret.id
  secret_string = file(var.config_file_path)
}
