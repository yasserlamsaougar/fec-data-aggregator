-- Tags individual contributions by donor employer using the industry taxonomy.
--
-- The employer field is the most precise industry signal for individual donations
-- because it directly names the company (e.g. "PFIZER INC", "GOLDMAN SACHS").
-- This bypasses the ambiguity of committee name guessing.
--
-- match_source = 'employer_keyword'  → employer matched a taxonomy keyword
-- match_source = 'unclassified'      → no match found

with contributions as (
    select * from {{ ref('stg_individual_contributions') }}
    where is_individual_donor
      and not is_refund
      and donor_employer is not null
      and trim(donor_employer) not in ('', 'N/A', 'NA', 'NONE', 'NOT EMPLOYED', 'RETIRED', 'SELF', 'SELF EMPLOYED', 'SELF-EMPLOYED', 'HOMEMAKER')
),

taxonomy as (
    select * from {{ ref('industry_taxonomy') }}
),

matched as (
    select
        c.transaction_id,
        c.committee_id,
        c.amount,
        c.transaction_date,
        c.donor_employer,
        t.industry,
        t.industry_group,
        t.keyword                                        as matched_keyword,
        t.priority,
        row_number() over (
            partition by c.transaction_id
            order by t.priority asc
        )                                                as match_rank
    from contributions c
    cross join taxonomy t
    where lower(c.donor_employer) like '%' || lower(t.keyword) || '%'
)

select
    c.transaction_id,
    c.committee_id,
    c.amount,
    c.transaction_date,
    c.donor_employer,
    coalesce(m.industry,       'Unknown / Unclassified') as industry,
    coalesce(m.industry_group, 'Unknown')                as industry_group,
    m.matched_keyword,
    case
        when m.industry is not null then 'employer_keyword'
        else 'unclassified'
    end                                                  as match_source

from contributions c
left join matched m
    on c.transaction_id = m.transaction_id
    and m.match_rank = 1
