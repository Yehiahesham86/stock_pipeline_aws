"""Tests for transforms.py on tiny DataFrames. No AWS, no S3."""

import os
from datetime import datetime
from decimal import Decimal

import pytest

import transforms as T

T0 = datetime(2026, 11, 1)

STUDENT_SCHEMA = (
    "op string, dms_ts string, student_id bigint, full_name string, email string, "
    "country string, plan string, status string, referred_by bigint, "
    "created_at timestamp, updated_at timestamp, dms_change_seq string, source_file string"
)


def student(op, ts, sid, seq="", plan="trial", status="active", email=None, referred_by=None):
    email = email if email is not None else f"s{sid}@example.com"
    return (op, ts, sid, f"Student {sid}", email, "EG", plan, status, referred_by, T0, T0, seq, "f.parquet")


def students_df(spark, rows):
    return spark.createDataFrame(rows, STUDENT_SCHEMA)


# ---------------------------------------------------------------- dedup


def test_latest_event_wins(spark):
    df = students_df(
        spark,
        [
            student("I", "2026-11-01 10:00:00.000000", 1),
            student("U", "2026-11-01 11:00:00.000000", 1, seq="0002", plan="basic"),
            student("U", "2026-11-01 09:00:00.000000", 1, seq="0001", plan="premium"),
        ],
    )
    out = T.latest_event_per_key(df, "student_id").collect()
    assert len(out) == 1
    assert out[0]["plan"] == "basic"


def test_double_update_same_ts_uses_change_seq(spark):
    ts = "2026-11-01 10:00:00.000000"
    df = students_df(
        spark,
        [
            student("U", ts, 1, seq="00000000000000000000000000000000010", plan="basic"),
            student("U", ts, 1, seq="00000000000000000000000000000000011", plan="premium"),
        ],
    )
    assert T.latest_event_per_key(df, "student_id").first()["plan"] == "premium"


def test_cdc_event_beats_full_load_at_same_ts(spark):
    ts = "2026-11-01 10:00:00.000000"
    df = students_df(spark, [student("I", ts, 1, seq=""), student("U", ts, 1, seq="0001", plan="basic")])
    assert T.latest_event_per_key(df, "student_id").first()["plan"] == "basic"


def test_insert_then_delete_keeps_delete(spark):
    df = students_df(
        spark,
        [student("I", "2026-11-01 10:00:00.000000", 1), student("D", "2026-11-01 10:05:00.000000", 1, seq="1")],
    )
    assert T.latest_event_per_key(df, "student_id").first()["op"] == "D"


# ---------------------------------------------------------------- DQ


def errors_of(spark, rows):
    df = students_df(spark, rows)
    return [r[T.DQ_ERRORS] for r in T.add_dq_errors(df, "students", "student_id").orderBy("student_id").collect()]


def test_valid_row_has_no_errors(spark):
    assert errors_of(spark, [student("I", "2026-11-01 10:00:00", 1)]) == [[]]


def test_bad_values_are_named(spark):
    rows = [student("I", "2026-11-01 10:00:00", 1, plan="gold", email="not-an-email")]
    assert sorted(errors_of(spark, rows)[0]) == ["email_valid", "plan_allowed"]


def test_null_counts_as_failure(spark):
    rows = [student("I", "2026-11-01 10:00:00", 1, plan=None)]
    assert errors_of(spark, rows)[0] == ["plan_allowed"]


def test_self_referral_fails(spark):
    rows = [student("I", "2026-11-01 10:00:00", 1, referred_by=1)]
    assert errors_of(spark, rows)[0] == ["not_self_referred"]


def test_delete_only_checks_base_rules(spark):
    # a delete with a broken row must still go through (else Silver keeps a ghost row)
    rows = [student("D", "2026-11-01 10:00:00", 1, plan="gold")]
    assert errors_of(spark, rows)[0] == []


def test_missing_key_and_bad_op_fail(spark):
    rows = [student("X", None, None)]
    assert sorted(errors_of(spark, rows)[0]) == ["dms_ts_not_null", "op_allowed", "student_id_not_null"]


def test_payment_refund_rule(spark):
    schema = (
        "op string, dms_ts string, payment_id bigint, student_id bigint, payment_type string, "
        "plan string, amount decimal(10,2), currency string, refund_of bigint, "
        "created_at timestamp, updated_at timestamp"
    )
    df = spark.createDataFrame(
        [
            ("I", "ts", 1, 7, "purchase", "basic", Decimal("10.00"), "USD", None, T0, T0),  # ok
            ("I", "ts", 2, 7, "refund", "basic", Decimal("10.00"), "USD", None, T0, T0),  # refund w/o purchase
            ("I", "ts", 3, 7, "purchase", "basic", Decimal("-1.00"), "usd", None, T0, T0),  # amount + currency
        ],
        schema,
    )
    out = T.add_dq_errors(df, "payments", "payment_id").orderBy("payment_id").collect()
    assert [sorted(r[T.DQ_ERRORS]) for r in out] == [
        [],
        ["refund_of_iff_refund"],
        ["amount_positive", "currency_3_letters"],
    ]


def test_booking_cancel_reason_rule(spark):
    schema = (
        "op string, dms_ts string, booking_id bigint, student_id bigint, teacher_id bigint, "
        "scheduled_at timestamp, duration_min int, status string, cancel_reason string, "
        "created_at timestamp, updated_at timestamp"
    )
    df = spark.createDataFrame(
        [
            ("I", "ts", 1, 1, 1, T0, 50, "cancelled", "other", T0, T0),  # ok
            ("I", "ts", 2, 1, 1, T0, 50, "cancelled", None, T0, T0),  # cancelled without reason
            ("I", "ts", 3, 1, 1, T0, 30, "completed", None, T0, T0),  # bad duration
        ],
        schema,
    )
    out = T.add_dq_errors(df, "class_bookings", "booking_id").orderBy("booking_id").collect()
    assert [r[T.DQ_ERRORS] for r in out] == [[], ["cancel_reason_iff_cancelled"], ["duration_allowed"]]


def test_split_valid(spark):
    df = students_df(spark, [student("I", "ts", 1), student("I", "ts", 2, plan="gold")])
    good, bad = T.split_valid(T.add_dq_errors(df, "students", "student_id"))
    assert [r["student_id"] for r in good.collect()] == [1]
    assert T.DQ_ERRORS not in good.columns
    assert [r["student_id"] for r in bad.collect()] == [2]


def test_every_table_has_rules(spark):
    for table in T.PRIMARY_KEYS:
        assert T.table_rules(table)


# ---------------------------------------------------------------- MERGE (needs Iceberg)

needs_iceberg = pytest.mark.skipif(not os.environ.get("ICEBERG_JAR"), reason="set ICEBERG_JAR to run")


def merge_batch(spark, rows, target="local.silver.students"):
    df = students_df(spark, rows)
    latest = T.latest_event_per_key(df, "student_id")
    good, _ = T.split_valid(T.add_dq_errors(latest, "students", "student_id"))
    cols = T.silver_columns(df.columns)
    if not spark.catalog.tableExists(target):
        good.limit(0).drop("op").writeTo(target).using("iceberg").create()
    good.createOrReplaceTempView("batch")
    spark.sql(T.build_merge_sql(target, "batch", "student_id", cols))
    return {r["student_id"]: r["plan"] for r in spark.table(target).collect()}


@needs_iceberg
def test_merge_insert_update_delete_and_rerun(spark):
    spark.sql("DROP TABLE IF EXISTS local.silver.students")
    batch1 = [
        student("I", "2026-11-01 10:00:00", 1),
        student("I", "2026-11-01 10:00:00", 2),
        student("I", "2026-11-01 10:00:00", 3),
    ]
    assert merge_batch(spark, batch1) == {1: "trial", 2: "trial", 3: "trial"}

    batch2 = [
        student("U", "2026-11-01 11:00:00", 1, seq="1", plan="basic"),  # update
        student("D", "2026-11-01 11:00:00", 2, seq="2"),  # hard delete
        student("U", "2026-11-01 11:00:00", 3, seq="3", plan="gold"),  # bad -> Silver unchanged
        student("I", "2026-11-01 11:00:00", 4, seq="4"),  # new
    ]
    expected = {1: "basic", 3: "trial", 4: "trial"}
    assert merge_batch(spark, batch2) == expected
    # idempotent: the same batch again, and an OLDER batch, change nothing
    assert merge_batch(spark, batch2) == expected
    assert merge_batch(spark, batch1[:1]) == expected
