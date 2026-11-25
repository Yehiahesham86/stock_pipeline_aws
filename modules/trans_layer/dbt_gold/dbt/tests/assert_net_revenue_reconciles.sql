-- Total net revenue in Gold = all purchases - all refunds in Silver.
-- Catches revenue lost or doubled by the joins in the model: a refund whose
-- purchase is missing, a payment of a student not in Silver, a fan-out.
with gold as (

    select sum(net_revenue) as total
    from {{ ref('gold_net_revenue_per_student') }}

),

silver as (

    select
        coalesce(sum(case when payment_type = 'purchase' then amount end), 0)
      - coalesce(sum(case when payment_type = 'refund' then amount end), 0) as total
    from {{ source('silver', 'payments') }}

)

select gold.total as gold_total, silver.total as silver_total
from gold
cross join silver
where coalesce(gold.total, 0) <> silver.total
