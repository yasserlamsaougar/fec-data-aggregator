-- Tags each committee with an industry using a three-layer approach:
--
--   Layer 1 — OpenSecrets crosswalk (highest confidence)
--             Maps FEC committee IDs to OpenSecrets category codes,
--             the gold-standard used by researchers and journalists.
--             Requires running scripts/download_opensecrets.py first.
--
--   Layer 2 — Keyword match on committee name + connected org name
--             Falls back to our curated industry_taxonomy seed.
--
--   Layer 3 — Unclassified
--             Committee could not be matched to any known industry.
--
-- match_source column reports which layer produced the tag so downstream
-- models and reports can communicate confidence to the reader.

with committees as (
    select * from {{ ref('stg_committees') }}
),

taxonomy as (
    select * from {{ ref('industry_taxonomy') }}
),

os_categories as (
    select * from {{ ref('opensecrets_categories') }}
),

os_raw as (
    select * from {{ source('raw', 'opensecrets_committees') }}
),

-- ── Layer 1: OpenSecrets crosswalk ────────────────────────────────────────
opensecrets_match as (
    select
        c.committee_id,
        osc.industry,
        osc.industry_group,
        osc.priority,
        'opensecrets'                                    as match_source
    from committees c
    inner join os_raw os
        on upper(trim(c.committee_id)) = upper(trim(os.fec_id))
    inner join os_categories osc
        on upper(trim(os.prim_code)) = upper(trim(osc.opensecrets_catcode))
    -- Take the most specific OpenSecrets category when there are multiple matches
    qualify row_number() over (
        partition by c.committee_id
        order by osc.priority asc
    ) = 1
),

-- ── Layer 2: keyword match on committee/org name ─────────────────────────
keyword_match as (
    select
        c.committee_id,
        t.industry,
        t.industry_group,
        t.priority,
        'committee_keyword'                              as match_source
    from committees c
    cross join taxonomy t
    where
        lower(c.committee_name) like '%' || lower(t.keyword) || '%'
        or lower(coalesce(c.connected_organization_name, '')) like '%' || lower(t.keyword) || '%'
    qualify row_number() over (
        partition by c.committee_id
        order by t.priority asc
    ) = 1
),

-- ── Merge layers: OpenSecrets wins over keyword ───────────────────────────
best_match as (
    select committee_id, industry, industry_group, match_source
    from opensecrets_match
    union all
    -- Only use keyword if OpenSecrets has no result
    select km.committee_id, km.industry, km.industry_group, km.match_source
    from keyword_match km
    where km.committee_id not in (select committee_id from opensecrets_match)
)

select
    c.committee_id,
    c.committee_name,
    c.connected_organization_name,
    c.organization_type,
    c.committee_type,
    c.committee_designation,
    c.is_super_pac,
    coalesce(bm.industry,       'Unknown / Unclassified') as industry,
    coalesce(bm.industry_group, 'Unknown')                as industry_group,
    coalesce(bm.match_source,   'unclassified')           as match_source,
    -- Dark money: Super PAC with no industry identification across all layers
    (c.is_super_pac and bm.industry is null)              as is_dark_money_suspect

from committees c
left join best_match bm on c.committee_id = bm.committee_id
