-- Every booking that ever existed, one row per booking_id:
--   live    = Silver (DQ-checked, current state)
--   deleted = bookings the app HARD-DELETED: gone from Silver (deletes
--             propagate), so they come from their Bronze delete event.
--             REPLICA IDENTITY FULL -> the DMS delete event carries the whole
--             old row (status, cancel_reason, teacher_id, scheduled_at).
-- Without the deleted part, cancellation rates (Q2) and booked counts (Q1)
-- would be too low.
-- Casts: Silver is written by Spark, Bronze by Athena; same columns, the
-- types are pinned so the UNION never depends on how each engine typed them.

with live as (

    select
        booking_id,
        student_id,
        teacher_id,
        cast(scheduled_at as timestamp(6)) as scheduled_at,
        cast(duration_min as integer)      as duration_min,
        status,
        cancel_reason,
        false                              as is_deleted
    from {{ source('silver', 'class_bookings') }}

),

delete_events as (

    select
        *,
        -- same order as the Spark job: commit time, then change seq inside a commit
        row_number() over (
            partition by booking_id
            order by dms_ts desc, coalesce(dms_change_seq, '') desc
        ) as rn
    from {{ source('bronze', 'class_bookings') }}
    where op = 'D'

),

deleted as (

    select
        d.booking_id,
        d.student_id,
        d.teacher_id,
        cast(d.scheduled_at as timestamp(6)) as scheduled_at,
        cast(d.duration_min as integer)      as duration_min,
        d.status,
        d.cancel_reason,
        true                                 as is_deleted
    from delete_events as d
    where d.rn = 1
      and not exists (select 1 from live as l where l.booking_id = d.booking_id)

)

select * from live
union all
select * from deleted
