-- Fails for every row outside [min_value, max_value]; either bound may be left out.
-- NULLs pass (use not_null for those).
{% test value_between(model, column_name, min_value=none, max_value=none) %}

select {{ column_name }}
from {{ model }}
where false
{% if min_value is not none %}
   or {{ column_name }} < {{ min_value }}
{% endif %}
{% if max_value is not none %}
   or {{ column_name }} > {{ max_value }}
{% endif %}

{% endtest %}
