-- gold_net_revenue_per_student adds amounts up as USD. A payment in any other
-- currency would be summed as if it were dollars -> stop the build instead.
-- Remove once the FX rates step converts amounts (Phase 4b).
select payment_id, currency
from {{ source('silver', 'payments') }}
where currency <> 'USD'
