-- Q3 Net revenue per student: purchases minus refunds.
-- Grain: student_id (every student, 0 when they never paid).
-- A refund is counted against the student of the purchase it refunds
-- (refund_of -> payment_id). The source test on refund_of + the singular test
-- assert_net_revenue_reconciles catch refunds that would drop out of this join.
-- Currency: amounts are summed as-is, which is only right while every payment
-- is USD -> tests/assert_single_currency.sql fails the build otherwise
-- (multi-currency needs the FX rates step first).

with students as (

    select student_id, full_name, plan, status
    from {{ source('silver', 'students') }}

),

payments as (

    select payment_id, student_id, payment_type, amount, refund_of
    from {{ source('silver', 'payments') }}

),

purchases as (

    select
        student_id,
        count(*)    as purchase_count,
        sum(amount) as purchase_amount
    from payments
    where payment_type = 'purchase'
    group by student_id

),

refunds as (

    select
        p.student_id,
        count(*)      as refund_count,
        sum(r.amount) as refund_amount
    from payments as r
    inner join payments as p
        on p.payment_id = r.refund_of
       and p.payment_type = 'purchase'
    where r.payment_type = 'refund'
    group by p.student_id

)

select
    s.student_id,
    s.full_name                                              as student_name,
    s.plan,
    s.status,
    coalesce(pu.purchase_count, 0)                           as purchase_count,
    cast(coalesce(pu.purchase_amount, 0) as decimal(12, 2)) as purchase_amount,
    coalesce(rf.refund_count, 0)                             as refund_count,
    cast(coalesce(rf.refund_amount, 0) as decimal(12, 2))   as refund_amount,
    cast(coalesce(pu.purchase_amount, 0) - coalesce(rf.refund_amount, 0) as decimal(12, 2)) as net_revenue,
    'USD'                                                    as currency
from students as s
left join purchases as pu
    on pu.student_id = s.student_id
left join refunds as rf
    on rf.student_id = s.student_id
