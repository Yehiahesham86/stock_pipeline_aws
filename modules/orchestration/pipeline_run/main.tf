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
#   NewBronze? ── nothing loaded ──> NoNewData (EMR not started = $0)
#        │
#   BronzeToSilver (EMR Serverless startJobRun.sync: dedup -> DQ ->
#        │          MERGE Silver Iceberg / bad rows -> quarantine bucket)
#   RawFailures? ── some Raw files failed ──> RawFilesFailed (execution FAILED,
#        │          files retry next run, DLQ after max_receive_count)
#   Done
#
# Cost: Scheduler + Step Functions stay inside the always-free tier at this
# rate; EMR is billed only for runs that had new data.
# ==========================================

resource "aws_sfn_state_machine" "pipeline" {
  name     = var.state_machine_name
  role_arn = aws_iam_role.sfn.arn

  definition = jsonencode({
    Comment = "Raw -> Bronze (Lambda + Athena) -> Silver (EMR Serverless + DQ + Iceberg MERGE)"
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
        Choices = [{
          Variable           = "$.totals.loaded"
          NumericGreaterThan = 0
          Next               = "BronzeToSilver"
        }]
        Default = "NoNewData"
      }

      NoNewData = {
        Type    = "Succeed"
        Comment = "no new Raw files -> EMR not started"
      }

      BronzeToSilver = {
        Type     = "Task"
        Resource = "arn:aws:states:::emr-serverless:startJobRun.sync"
        Parameters = {
          ApplicationId           = var.emr_application_id
          ExecutionRoleArn        = var.emr_job_role_arn
          "Name.$"                = "States.Format('bronze-to-silver-{}', $$.Execution.Name)"
          ExecutionTimeoutMinutes = var.job_timeout_minutes
          JobDriver = {
            SparkSubmit = {
              EntryPoint            = var.emr_entry_point
              EntryPointArguments   = var.emr_entry_point_arguments
              SparkSubmitParameters = var.emr_spark_submit_parameters
            }
          }
          ConfigurationOverrides = {
            MonitoringConfiguration = {
              S3MonitoringConfiguration = {
                LogUri = var.emr_log_uri
              }
            }
          }
        }
        ResultPath = "$.silver"
        Catch = [{
          ErrorEquals = ["States.ALL"]
          ResultPath  = "$.error"
          Next        = "BronzeToSilverFailed"
        }]
        Next = "RawFailures"
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
        Cause = "EMR Serverless job failed; driver logs under <emr_log_uri>applications/<app>/jobs/<run>/SPARK_DRIVER/"
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
