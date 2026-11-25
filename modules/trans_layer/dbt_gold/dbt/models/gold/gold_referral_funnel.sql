-- Q4 Referral funnel: invited -> trial -> converted (and expired).
-- Grain: referrer_id x invite_month (month of the referral's created_at).
-- From the CURRENT referral status (Silver), so a funnel stage is inferred:
--   invited       every referral starts as 'invited'
--   reached_trial referee_id is set: the source CHECK forces it for
--                 trial/converted, and it stays set when a trial expires, so
--                 'expired after trial' still counts as reached trial
--   converted / expired / still_open = current status
-- Assumes the app never clears referee_id; if it did, this needs the Bronze
-- status history instead.

with referrals as (

    select
        referral_id,
        referrer_id,
        referee_id,
        status,
        cast(date_trunc('month', created_at) as date) as invite_month
    from {{ source('silver', 'referrals') }}

),

students as (

    select student_id, full_name
    from {{ source('silver', 'students') }}

)

select
    r.referrer_id,
    s.full_name                                                         as referrer_name,
    r.invite_month,
    count(*)                                                            as invited,
    count_if(r.referee_id is not null)                                  as reached_trial,
    count_if(r.status = 'converted')                                    as converted,
    count_if(r.status = 'expired')                                      as expired,
    count_if(r.status in ('invited', 'trial'))                          as still_open,
    cast(count_if(r.referee_id is not null) as double) / count(*)       as trial_rate,
    cast(count_if(r.status = 'converted') as double) / count(*)         as conversion_rate
from referrals as r
left join students as s
    on s.student_id = r.referrer_id
group by r.referrer_id, s.full_name, r.invite_month
