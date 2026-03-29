-- Unified contribution flow: resolves all money back to the receiving candidate
-- and attaches an industry tag to every transaction.
--
-- Two paths:
--   1. PAC → candidate (direct): industry from int_committee_industry_tags
--   2. Individual → committee → candidate: industry from int_individual_donor_industry
--      (employer-based, more precise than committee name guessing)
--
-- match_source reports the confidence tier of the industry tag:
--   'opensecrets'       — matched via OpenSecrets crosswalk (highest)
--   'employer_keyword'  — matched via donor employer field
--   'committee_keyword' — matched via committee/org name
--   'unclassified'      — no industry identified

with pac_direct as (
    select
        pc.transaction_id,
        pc.candidate_id,
        pc.contributor_committee_id                      as source_committee_id,
        null::varchar                                    as donor_name,
        null::varchar                                    as donor_employer,
        null::varchar                                    as donor_occupation,
        pc.amount,
        pc.transaction_date,
        pc.election_type,
        'pac_direct'                                     as contribution_path,
        ct.industry,
        ct.industry_group,
        ct.match_source,
        ct.is_dark_money_suspect,
        coalesce(ct.is_super_pac, false)                 as is_super_pac
    from {{ ref('stg_pac_contributions') }} pc
    left join {{ ref('int_committee_industry_tags') }} ct
        on pc.contributor_committee_id = ct.committee_id
    where not pc.is_refund
),

individual_via_committee as (
    select
        ic.transaction_id,
        ccl.candidate_id,
        ic.committee_id                                  as source_committee_id,
        ic.donor_name,
        ic.donor_employer,
        ic.donor_occupation,
        ic.amount,
        ic.transaction_date,
        ic.election_type,
        'individual'                                     as contribution_path,
        coalesce(idi.industry,       'Unknown / Unclassified') as industry,
        coalesce(idi.industry_group, 'Unknown')                as industry_group,
        coalesce(idi.match_source,   'unclassified')           as match_source,
        false                                            as is_dark_money_suspect,
        false                                            as is_super_pac
    from {{ ref('stg_individual_contributions') }} ic
    inner join {{ ref('stg_candidate_committee_linkage') }} ccl
        on ic.committee_id = ccl.committee_id
    left join {{ ref('int_individual_donor_industry') }} idi
        on ic.transaction_id = idi.transaction_id
    where ic.is_individual_donor
      and not ic.is_refund
)

select * from pac_direct
union all
select * from individual_via_committee
