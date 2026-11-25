-- A funnel only narrows: invited >= reached_trial >= converted, and every
-- referral is in exactly one current state.
select *
from {{ ref('gold_referral_funnel') }}
where reached_trial > invited
   or converted > reached_trial
   or converted + expired + still_open <> invited
