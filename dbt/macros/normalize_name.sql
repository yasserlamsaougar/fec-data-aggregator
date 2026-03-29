{% macro title_case(col) %}
    -- DuckDB has no initcap(). Implement title case using substr() for
    -- broad version compatibility. NULL and empty strings return NULL.
    case
        when trim({{ col }}) is null or trim({{ col }}) = '' then null
        else array_to_string(
            list_transform(
                list_filter(
                    string_split(lower(trim({{ col }})), ' '),
                    x -> x != ''
                ),
                x -> upper(substr(x, 1, 1)) || substr(x, 2)
            ),
            ' '
        )
    end
{% endmacro %}


{% macro normalize_name(col) %}
    {{ title_case(col) }}
{% endmacro %}


{% macro normalize_employer(col) %}
    -- Normalize employer names for display and consistent taxonomy matching:
    --   1. Title case
    --   2. Standardize & → And
    --   3. Collapse multiple spaces
    --   4. Strip trailing corporate suffixes (Inc, Llc, Corp, etc.)
    regexp_replace(
        regexp_replace(
            array_to_string(
                list_transform(
                    string_split(
                        regexp_replace(lower(trim({{ col }})), '\s+', ' ', 'g'),
                        ' '
                    ),
                    x -> upper(x[1:1]) || x[2:]
                ),
                ' '
            ),
            '\s*&\s*', ' And ', 'g'
        ),
        '\s+(Inc\.?|Llc\.?|Corp\.?|Ltd\.?|Co\.?|Lp\.?|Llp\.?|Na\.?|Pc\.?|Plc\.?)$',
        '', 'i'
    )
{% endmacro %}


{% macro candidate_last_name(col) %}
    case
        when position(',' in {{ col }}) > 0
        then {{ title_case("trim(split_part(" ~ col ~ ", ',', 1))") }}
        else {{ title_case(col) }}
    end
{% endmacro %}


{% macro candidate_first_name(col) %}
    case
        when position(',' in {{ col }}) > 0
        then {{ title_case("trim(split_part(" ~ col ~ ", ',', 2))") }}
        else null
    end
{% endmacro %}


{% macro candidate_display_name(col) %}
    -- "SANDERS, BERNARD"  → "Bernard Sanders"
    -- "BERNIE SANDERS"    → "Bernie Sanders"
    case
        when position(',' in {{ col }}) > 0
        then {{ title_case("trim(split_part(" ~ col ~ ", ',', 2))") }}
             || ' '
             || {{ title_case("trim(split_part(" ~ col ~ ", ',', 1))") }}
        else {{ title_case(col) }}
    end
{% endmacro %}
