data "aws_caller_identity" "current" {}

# ==========================================
# Step Functions role
# ==========================================

resource "aws_iam_role" "sfn" {
  # destroy also detaches policies attached outside Terraform
  force_detach_policies = true

  name = "${var.state_machine_name}-sfn-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "sfn" {
  name = "${var.state_machine_name}-sfn-policy"
  role = aws_iam_role.sfn.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "RawToBronze"
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = [var.raw_to_bronze_function_arn, "${var.raw_to_bronze_function_arn}:*"]
      },
      {
        Sid    = "BronzeToSilver"
        Effect = "Allow"
        Action = ["emr-serverless:StartJobRun", "emr-serverless:GetJobRun", "emr-serverless:CancelJobRun"]
        Resource = [
          var.emr_application_arn,
          "${var.emr_application_arn}/jobruns/*",
        ]
      },
      {
        Sid      = "PassEmrJobRole"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = var.emr_job_role_arn
        Condition = {
          StringEquals = { "iam:PassedToService" = "emr-serverless.amazonaws.com" }
        }
      },
      {
        # .sync: Step Functions creates this managed rule to hear when the job ends
        Sid      = "EmrSyncRule"
        Effect   = "Allow"
        Action   = ["events:PutTargets", "events:PutRule", "events:DescribeRule"]
        Resource = "arn:aws:events:${var.aws_region}:${data.aws_caller_identity.current.account_id}:rule/StepFunctionsGetEventsForEMRServerlessJobRule"
      },
      {
        Sid      = "CheckRunning"
        Effect   = "Allow"
        Action   = "states:ListExecutions"
        Resource = aws_sfn_state_machine.pipeline.arn
      },
    ]
  })
}

# ==========================================
# Scheduler role: may only start this state machine
# ==========================================

resource "aws_iam_role" "scheduler" {
  # destroy also detaches policies attached outside Terraform
  force_detach_policies = true

  name = "${var.state_machine_name}-scheduler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "scheduler" {
  name = "${var.state_machine_name}-scheduler-policy"
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "states:StartExecution"
      Resource = aws_sfn_state_machine.pipeline.arn
    }]
  })
}
