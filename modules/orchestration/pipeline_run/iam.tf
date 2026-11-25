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
        Sid      = "RunTasks"
        Effect   = "Allow"
        Action   = "ecs:RunTask"
        Resource = ["${var.ecs_task_definition_family_arn}:*", "${var.dbt_task_definition_family_arn}:*"]
      },
      {
        # .sync polls the task and stops it on timeout / execution abort
        Sid      = "BronzeToSilverWatch"
        Effect   = "Allow"
        Action   = ["ecs:DescribeTasks", "ecs:StopTask"]
        Resource = "*"
        Condition = {
          ArnEquals = { "ecs:cluster" = var.ecs_cluster_arn }
        }
      },
      {
        Sid      = "PassTaskRoles"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = [var.ecs_task_role_arn, var.ecs_execution_role_arn, var.dbt_task_role_arn, var.dbt_execution_role_arn]
        Condition = {
          StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" }
        }
      },
      {
        # .sync: Step Functions creates this managed rule to hear when the task stops
        Sid      = "EcsSyncRule"
        Effect   = "Allow"
        Action   = ["events:PutTargets", "events:PutRule", "events:DescribeRule"]
        Resource = "arn:aws:events:${var.aws_region}:${data.aws_caller_identity.current.account_id}:rule/StepFunctionsGetEventsForECSTaskRule"
      },
      {
        Sid    = "CheckRunning"
        Effect = "Allow"
        Action = "states:ListExecutions"
        # ARN built from the name (not the resource) so this policy exists BEFORE
        # the state machine: CreateStateMachine checks the role can create the
        # .sync managed rule, and fails "not authorized to create managed-rule" otherwise
        Resource = "arn:aws:states:${var.aws_region}:${data.aws_caller_identity.current.account_id}:stateMachine:${var.state_machine_name}"
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
