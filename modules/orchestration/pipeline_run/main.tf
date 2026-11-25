# ==========================================
# One pipeline run, fully in AWS:
#
#   EventBridge Scheduler (rate) -> Step Functions:
#
#   CheckRunning ── another run busy? ──> SkipBusy
#        │
#   RawToBronze  (trigger Lambda {"drain": true}: SQS queue of new Raw files
#        │        -> catalog_manager -> Athena INSERT INTO Bronze Iceberg)
#   MoreRaw?  ── Lambda stopped early (time) ──> RawToBronze again (max_drain_loops)
#        │
#   NewBronze? ── nothing loaded ──> NoNewData (Spark task not started = $0)
#        │
#   BronzeToSilver (ECS Fargate runTask.sync: Spark job, dedup -> DQ ->
#        │          MERGE Silver Iceberg / bad rows -> quarantine bucket)
#   SilverExitCode? ── Spark exited non-zero ──> BronzeToSilverFailed
#        │
#   SilverToGold (ECS Fargate runTask.sync: `dbt build` -> 4 Gold Iceberg
#        │        tables through Athena + dbt tests)
#   GoldExitCode? ── a model or test failed ──> SilverToGoldFailed
#        │
#   RawFailures? ── some Raw files failed ──> RawFilesFailed (execution FAILED,
#        │          files retry next run, DLQ after max_receive_count)
#   Done
#
# Cost: Scheduler + Step Functions stay inside the always-free tier at this
# rate; Fargate is billed only for runs that had new data.
# ==========================================

resource "aws_sfn_state_machine" "pipeline" {
  name     = var.state_machine_name
  role_arn = aws_iam_role.sfn.arn

  # role must already have its permissions (events managed rule for ecs:runTask.sync)
  depends_on = [aws_iam_role_policy.sfn]

  definition = jsonencode({
    Comment = "Raw -> Bronze (Lambda + Athena) -> Silver (Spark on ECS Fargate + DQ + Iceberg MERGE) -> Gold (dbt-athena on ECS Fargate)"
    StartAt = "CheckRunning"
    States = {

      # ---------- 1 run at a time: two runs would load + MERGE the same data ----------
      CheckRunning = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:sfn:listExecutions"
        Parameters = {
          "StateMachineArn.$" = "$$.StateMachine.Id"
          StatusFilter        = "RUNNING"
        }
        ResultSelector = {
          "running.$" = "States.ArrayLength($.Executions)"
        }
        ResultPath = "$.check"
        Next       = "AlreadyRunning"
      }

      # this execution counts itself -> more than 1 = another one is busy
      AlreadyRunning = {
        Type = "Choice"
        Choices = [{
          Variable           = "$.check.running"
          NumericGreaterThan = 1
          Next               = "SkipBusy"
        }]
        Default = "InitCounters"
      }

      SkipBusy = {
        Type    = "Succeed"
        Comment = "previous run still busy; the next schedule picks up the new data"
      }

      InitCounters = {
        Type = "Pass"
        Result = {
          loaded = 0
          failed = 0
          loops  = 0
        }
        ResultPath = "$.totals"
        Next       = "RawToBronze"
      }

      # ---------- Stage 1: Raw -> Bronze ----------
      RawToBronze = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = var.raw_to_bronze_function_arn
          Payload      = { drain = true }
        }
        ResultSelector = {
          "loaded.$" = "$.Payload.loaded"
          "failed.$" = "$.Payload.failed"
          "more.$"   = "$.Payload.more"
        }
        ResultPath = "$.raw"
        Retry = [{
          ErrorEquals     = ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException", "Lambda.TooManyRequestsException"]
          IntervalSeconds = 5
          MaxAttempts     = 3
          BackoffRate     = 2
        }]
        Catch = [{
          ErrorEquals = ["States.ALL"]
          ResultPath  = "$.error"
          Next        = "RawToBronzeFailed"
        }]
        Next = "AddTotals"
      }

      AddTotals = {
        Type = "Pass"
        Parameters = {
          "loaded.$" = "States.MathAdd($.totals.loaded, $.raw.loaded)"
          "failed.$" = "States.MathAdd($.totals.failed, $.raw.failed)"
          "loops.$"  = "States.MathAdd($.totals.loops, 1)"
        }
        ResultPath = "$.totals"
        Next       = "MoreRaw"
      }

      # Lambda stopped because time ran short -> call it again (bounded)
      MoreRaw = {
        Type = "Choice"
        Choices = [{
          And = [
            { Variable = "$.raw.more", BooleanEquals = true },
            { Variable = "$.totals.loops", NumericLessThan = var.max_drain_loops },
          ]
          Next = "RawToBronze"
        }]
        Default = "NewBronze"
      }

      # ---------- Stage 2: Bronze -> Silver, only when Bronze got new rows ----------
      NewBronze = {
        Type = "Choice"
        Choices = [
          {
            Variable           = "$.totals.loaded"
            NumericGreaterThan = 0
            Next               = "BronzeToSilver"
          },
          {
            # nothing loaded because every file FAILED -> fail the run
            # (was: NoNewData = green run that hid the errors)
            Variable           = "$.totals.failed"
            NumericGreaterThan = 0
            Next               = "RawFilesFailed"
          },
        ]
        Default = "NoNewData"
      }

      NoNewData = {
        Type    = "Succeed"
        Comment = "no new Raw files -> Spark task not started"
      }

      BronzeToSilver = {
        Type     = "Task"
        Resource = "arn:aws:states:::ecs:runTask.sync"
        # cost cap: Step Functions stops the task when this runs out
        TimeoutSeconds = var.job_timeout_minutes * 60
        Parameters = {
          LaunchType     = "FARGATE"
          Cluster        = var.ecs_cluster_arn
          TaskDefinition = var.ecs_task_definition_arn
          NetworkConfiguration = {
            AwsvpcConfiguration = {
              Subnets        = var.ecs_subnet_ids
              SecurityGroups = [var.ecs_security_group_id]
              # public subnet + public IP instead of a NAT gateway
              AssignPublicIp = "ENABLED"
            }
          }
        }
        # .sync succeeds whenever the task STOPS, even if Spark exited 1 ->
        # keep only the exit code and check it in SilverExitCode
        ResultSelector = {
          "exit_code.$" = "$.Containers[0].ExitCode"
        }
        ResultPath = "$.silver"
        Catch = [{
          ErrorEquals = ["States.ALL"]
          ResultPath  = "$.error"
          Next        = "BronzeToSilverFailed"
        }]
        Next = "SilverExitCode"
      }

      SilverExitCode = {
        Type = "Choice"
        Choices = [{
          Variable      = "$.silver.exit_code"
          NumericEquals = 0
          Next          = "SilverToGold"
        }]
        Default = "BronzeToSilverFailed"
      }

      # ---------- Stage 3: Silver -> Gold, dbt build (models + tests) ----------
      # Runs only after a good Silver run: no new Bronze rows = Gold unchanged.
      SilverToGold = {
        Type           = "Task"
        Resource       = "arn:aws:states:::ecs:runTask.sync"
        TimeoutSeconds = var.dbt_timeout_minutes * 60
        Parameters = {
          LaunchType     = "FARGATE"
          Cluster        = var.ecs_cluster_arn
          TaskDefinition = var.dbt_task_definition_arn
          NetworkConfiguration = {
            AwsvpcConfiguration = {
              Subnets        = var.ecs_subnet_ids
              SecurityGroups = [var.dbt_security_group_id]
              AssignPublicIp = "ENABLED"
            }
          }
        }
        ResultSelector = {
          "exit_code.$" = "$.Containers[0].ExitCode"
        }
        ResultPath = "$.gold"
        Catch = [{
          ErrorEquals = ["States.ALL"]
          ResultPath  = "$.error"
          Next        = "SilverToGoldFailed"
        }]
        Next = "GoldExitCode"
      }

      # dbt exits 1 when a model OR a test (severity error) fails
      GoldExitCode = {
        Type = "Choice"
        Choices = [{
          Variable      = "$.gold.exit_code"
          NumericEquals = 0
          Next          = "RawFailures"
        }]
        Default = "SilverToGoldFailed"
      }

      # Silver ran on what loaded; still flag the Raw files that didn't
      RawFailures = {
        Type = "Choice"
        Choices = [{
          Variable           = "$.totals.failed"
          NumericGreaterThan = 0
          Next               = "RawFilesFailed"
        }]
        Default = "Done"
      }

      Done = {
        Type = "Succeed"
      }

      # ---------- failures ----------
      RawToBronzeFailed = {
        Type  = "Fail"
        Error = "RawToBronzeFailed"
        Cause = "trigger Lambda failed; see its CloudWatch logs"
      }

      RawFilesFailed = {
        Type  = "Fail"
        Error = "RawFilesFailed"
        Cause = "some Raw files failed to load (step=failed in the trigger Lambda logs); they retry next run, then go to the DLQ"
      }

      BronzeToSilverFailed = {
        Type  = "Fail"
        Error = "BronzeToSilverFailed"
        Cause = "Spark task failed, exited non-zero or timed out; logs in CloudWatch log group /ecs/<name> (stream bronze-to-silver/spark/<task id>)"
      }

      SilverToGoldFailed = {
        Type  = "Fail"
        Error = "SilverToGoldFailed"
        Cause = "dbt build failed (model error or failing test) or timed out; logs in CloudWatch log group /ecs/<name> (stream silver-to-gold/dbt/<task id>)"
      }
    }
  })
}

# ==========================================
# Schedule
# ==========================================

resource "aws_scheduler_schedule" "pipeline" {
  name                = "${var.state_machine_name}-schedule"
  schedule_expression = var.schedule_expression
  state               = var.schedule_enabled ? "ENABLED" : "DISABLED"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_sfn_state_machine.pipeline.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({})
  }
}
