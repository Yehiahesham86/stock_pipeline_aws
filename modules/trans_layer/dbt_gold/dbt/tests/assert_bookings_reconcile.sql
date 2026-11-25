-- Every booking is counted exactly once in Q1 and every lost one in Q2:
--   sum(booked_classes)  in Q1 = live Silver bookings + hard-deleted ones
--   sum(lost_classes)    in Q2 = cancelled + no-show bookings
-- Catches rows dropped or duplicated by the teacher join / week bucketing.
with bookings as (

    select
        count(*)                                        as all_bookings,
        count_if(status in ('cancelled', 'no_show'))    as lost_bookings
    from {{ ref('int_class_bookings') }}

),

q1 as (

    select coalesce(sum(booked_classes), 0) as booked
    from {{ ref('gold_teacher_utilization_weekly') }}

),

q2 as (

    select coalesce(sum(lost_classes), 0) as lost
    from {{ ref('gold_cancellation_rates') }}

)

select b.all_bookings, q1.booked, b.lost_bookings, q2.lost
from bookings as b
cross join q1
cross join q2
where b.all_bookings <> q1.booked
   or b.lost_bookings <> q2.lost
