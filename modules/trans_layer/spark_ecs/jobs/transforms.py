"""Bronze -> Silver logic as pure PySpark functions (DataFrame in -> DataFrame out).

No S3, no catalog, no SparkSession creation here: bronze_to_silver.py does the
I/O and calls these. That keeps every rule testable with pytest on tiny
DataFrames (tests/test_transforms.py).

Order matters:
  1. latest_event_per_key  -- dedup FIRST
  2. add_dq_errors         -- validate only the event that would win
  3. split_valid           -- good -> MERGE into Silver, bad -> quarantine

Why dedup before DQ: if a key has events U1 (good) then U2 (bad) and we drop
U2 first, U1 gets merged and Silver shows a state the source has already left.
Validating only the latest event means a bad event holds its key unchanged in
Silver until a newer good event arrives.
"""

from pyspark.sql import Column, DataFrame, Window
from pyspark.sql import functions as F

# ----------------------------------------------------------------------------
# Table config
# ----------------------------------------------------------------------------

# Primary key per source table (from source-stock-data-pipeline/sql/01_schema.sql)
PRIMARY_KEYS = {
    "teachers": "teacher_id",
    "students": "student_id",
    "class_bookings": "booking_id",
    "payments": "payment_id",
    "referrals": "referral_id",
}

# DMS metadata columns in Bronze that are not source data
DMS_COLUMNS = ["op", "dms_ts", "dms_change_seq", "source_file", "ingested_at"]

DQ_ERRORS = "dq_errors"


def _valid_email(col: str) -> Column:
    return F.col(col).rlike(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def _in(col: str, values: list) -> Column:
    return F.col(col).isin(values)


def _not_null(col: str) -> Column:
    return F.col(col).isNotNull()


# Rules per table: rule name -> Column that is TRUE when the row is valid.
# A function (not a module constant): building a Column needs a running SparkContext.
# A NULL result counts as a failure (e.g. hourly_rate NULL -> "hourly_rate > 0" is NULL).
# Copied from the CHECK / NOT NULL constraints in 01_schema.sql: the source DB
# already enforces them, so a failure here means the pipeline broke the data
# (bad cast, wrong column mapping, truncated file), not that the app did.
def table_rules(table: str) -> dict:
    return {
        "teachers": {
            "full_name_not_null": _not_null("full_name"),
            "email_valid": _valid_email("email"),
            "country_not_null": _not_null("country"),
            "hourly_rate_positive": F.col("hourly_rate") > 0,
            "status_allowed": _in("status", ["active", "inactive"]),
            "created_at_not_null": _not_null("created_at"),
            "updated_at_not_null": _not_null("updated_at"),
        },
        "students": {
            "full_name_not_null": _not_null("full_name"),
            "email_valid": _valid_email("email"),
            "country_not_null": _not_null("country"),
            "plan_allowed": _in("plan", ["trial", "basic", "premium"]),
            "status_allowed": _in("status", ["active", "paused", "churned"]),
            "not_self_referred": F.col("referred_by").isNull()
            | (F.col("referred_by") != F.col("student_id")),
            "created_at_not_null": _not_null("created_at"),
            "updated_at_not_null": _not_null("updated_at"),
        },
        "class_bookings": {
            "student_id_not_null": _not_null("student_id"),
            "teacher_id_not_null": _not_null("teacher_id"),
            "scheduled_at_not_null": _not_null("scheduled_at"),
            "duration_allowed": _in("duration_min", [25, 50]),
            "status_allowed": _in("status", ["booked", "completed", "cancelled", "no_show"]),
            "cancel_reason_allowed": F.col("cancel_reason").isNull()
            | _in(
                "cancel_reason",
                ["student_request", "teacher_unavailable", "technical_issue", "schedule_conflict", "other"],
            ),
            # a reason exists if and only if the class was cancelled
            "cancel_reason_iff_cancelled": (F.col("status") == "cancelled")
            == F.col("cancel_reason").isNotNull(),
            "created_at_not_null": _not_null("created_at"),
            "updated_at_not_null": _not_null("updated_at"),
        },
        "payments": {
            "student_id_not_null": _not_null("student_id"),
            "payment_type_allowed": _in("payment_type", ["purchase", "refund"]),
            "plan_allowed": _in("plan", ["basic", "premium"]),
            "amount_positive": F.col("amount") > 0,
            "currency_3_letters": F.col("currency").rlike(r"^[A-Z]{3}$"),
            # refunds must reference a purchase; purchases must not
            "refund_of_iff_refund": (F.col("payment_type") == "refund") == F.col("refund_of").isNotNull(),
            "created_at_not_null": _not_null("created_at"),
            "updated_at_not_null": _not_null("updated_at"),
        },
        "referrals": {
            "referrer_id_not_null": _not_null("referrer_id"),
            "referee_email_valid": _valid_email("referee_email"),
            "status_allowed": _in("status", ["invited", "trial", "converted", "expired"]),
            "referee_id_when_signed_up": ~_in("status", ["trial", "converted"])
            | F.col("referee_id").isNotNull(),
            "created_at_not_null": _not_null("created_at"),
            "updated_at_not_null": _not_null("updated_at"),
        },
    }[table]


def base_rules(key: str) -> dict:
    """Rules every event must pass, deletes included."""
    return {
        f"{key}_not_null": _not_null(key),
        "op_allowed": _in("op", ["I", "U", "D"]),
        "dms_ts_not_null": _not_null("dms_ts"),
    }


# ----------------------------------------------------------------------------
# Transforms
# ----------------------------------------------------------------------------


def event_order() -> list:
    """Newest event first: commit time, then DMS change sequence.

    dms_change_seq is EMPTY on full-load rows and a fixed-width, sortable
    string on CDC rows, so at an equal dms_ts a CDC event beats the full load.
    """
    return [F.col("dms_ts").desc(), F.coalesce(F.col("dms_change_seq"), F.lit("")).desc()]


def latest_event_per_key(df: DataFrame, key: str) -> DataFrame:
    """Keep one event per key: the newest one (it may be a delete)."""
    w = Window.partitionBy(key).orderBy(*event_order())
    return df.withColumn("_rn", F.row_number().over(w)).filter(F.col("_rn") == 1).drop("_rn")


def add_dq_errors(df: DataFrame, table: str, key: str) -> DataFrame:
    """Add dq_errors: array of failed rule names (empty array = valid).

    Delete events only need the base rules: the row is going away, and a
    blocked delete would leave a row in Silver that no longer exists in the source.
    """
    rules = base_rules(key)
    row_rules = table_rules(table)
    is_delete = F.col("op") == "D"

    failed = [F.when(~F.coalesce(rule, F.lit(False)), F.lit(name)) for name, rule in rules.items()]
    failed += [
        F.when(~is_delete & ~F.coalesce(rule, F.lit(False)), F.lit(name)) for name, rule in row_rules.items()
    ]
    return df.withColumn(DQ_ERRORS, F.array_compact(F.array(*failed)))


def split_valid(df: DataFrame) -> tuple:
    """(good, bad). good drops dq_errors; bad keeps it so you can see why."""
    is_valid = F.size(F.col(DQ_ERRORS)) == 0
    return df.filter(is_valid).drop(DQ_ERRORS), df.filter(~is_valid)


def build_merge_sql(target: str, source_view: str, key: str, columns: list) -> str:
    """MERGE one batch (one event per key) into the Silver Iceberg table.

    Idempotent: an event only wins if it is at least as new as what Silver
    already holds (dms_ts, then dms_change_seq), so re-running the same batch
    or an older batch changes nothing.
    columns = Silver columns (source columns + dms_ts, dms_change_seq, source_file).
    """
    newer = (
        "(s.dms_ts > t.dms_ts OR (s.dms_ts = t.dms_ts AND "
        "coalesce(s.dms_change_seq, '') >= coalesce(t.dms_change_seq, '')))"
    )
    set_list = ", ".join(f"t.{c} = s.{c}" for c in columns if c != key)
    col_list = ", ".join(columns)
    val_list = ", ".join(f"s.{c}" for c in columns)
    return f"""
MERGE INTO {target} t
USING {source_view} s
ON t.{key} = s.{key}
WHEN MATCHED AND s.op = 'D' AND {newer} THEN DELETE
WHEN MATCHED AND s.op <> 'D' AND {newer} THEN UPDATE SET {set_list}
WHEN NOT MATCHED AND s.op <> 'D' THEN INSERT ({col_list}) VALUES ({val_list})
""".strip()


def silver_columns(bronze_columns: list) -> list:
    """Silver keeps the source columns + what MERGE needs to order events."""
    return [c for c in bronze_columns if c not in ("op", "ingested_at")]
