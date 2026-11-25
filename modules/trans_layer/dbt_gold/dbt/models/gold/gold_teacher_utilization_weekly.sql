-- Q1 Teacher utilization: completed vs. booked classes per teacher per week.
-- Grain: teacher_id x week_start (ISO week, Monday, of scheduled_at, UTC).
-- booked_classes = every booking scheduled that week, whatever happened to it,
-- including hard-deleted cancellations (int_class_bookings).
-- utilization_rate = completed / booked. A current week still has 'booked'
-- (not yet happened) classes, so its rate rises until the week is over.

with bookings as (

    select
        *,
        cast(date_trunc('week', scheduled_at) as date) as week_start
    from {{ ref('int_class_bookings') }}

),

teachers as (

    select teacher_id, full_name
    from {{ source('silver', 'teachers') }}

)

select
    b.teacher_id,
    t.full_name                                                       as teacher_name,
    b.week_start,
    count(*)                                                          as booked_classes,
    count_if(b.status = 'completed')                                  as completed_classes,
    count_if(b.status = 'cancelled')                                  as cancelled_classes,
    count_if(b.status = 'no_show')                                    as no_show_classes,
    count_if(b.status = 'booked')                                     as open_classes,
    sum(case when b.status = 'completed' then b.duration_min else 0 end) as completed_minutes,
    cast(count_if(b.status = 'completed') as double) / count(*)       as utilization_rate
from bookings as b
left join teachers as t
    on t.teacher_id = b.teacher_id
group by b.teacher_id, t.full_name, b.week_start
