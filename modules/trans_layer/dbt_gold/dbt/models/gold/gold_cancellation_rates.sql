-- Q2 Cancellation & no-show rate by teacher and by cancel reason.
-- Grain: teacher_id x week_start x reason
--   reason = cancel_reason for cancelled classes, 'no_show' for no-shows.
-- rate = lost classes for that reason / all classes booked with the teacher
-- that week, so summing rate over reasons = the teacher's total loss rate.
-- hard_deleted_classes = how many of them exist ONLY because the pipeline is
-- CDC (deleted in the app, rebuilt from the Bronze delete event).

with bookings as (

    select
        *,
        cast(date_trunc('week', scheduled_at) as date) as week_start
    from {{ ref('int_class_bookings') }}

),

booked_per_week as (

    select teacher_id, week_start, count(*) as booked_classes
    from bookings
    group by teacher_id, week_start

),

lost as (

    select
        teacher_id,
        week_start,
        case when status = 'no_show' then 'no_show' else cancel_reason end as reason,
        case when status = 'no_show' then 'no_show' else 'cancelled' end   as outcome,
        count(*)               as lost_classes,
        count_if(is_deleted)   as hard_deleted_classes
    from bookings
    where status in ('cancelled', 'no_show')
    group by 1, 2, 3, 4

)

select
    l.teacher_id,
    l.week_start,
    l.reason,
    l.outcome,
    l.lost_classes,
    l.hard_deleted_classes,
    w.booked_classes,
    cast(l.lost_classes as double) / w.booked_classes as rate
from lost as l
inner join booked_per_week as w
    on w.teacher_id = l.teacher_id
   and w.week_start = l.week_start
