-- The model's grain: no two rows may share these columns.
-- (Same as dbt_utils.unique_combination_of_columns, written here so the image
-- needs no `dbt deps` / package download.)
{% test unique_combination(model, columns) %}

select
    {{ columns | join(', ') }},
    count(*) as n_rows
from {{ model }}
group by {{ columns | join(', ') }}
having count(*) > 1

{% endtest %}
