---
title: Candidate Profile
---

# {params.candidate_name}

```sql profile
select
    s.candidate_name,
    s.party_name,
    s.office,
    s.office_state,
    s.election_year,
    s.incumbent_challenger_status,
    s.total_raised,
    s.pct_from_pacs,
    s.pct_from_individuals,
    s.pct_dark_money,
    s.pct_super_pac,
    s.unique_donor_count,
    s.median_individual_donation,
    s.pct_individual_from_large,
    s.corruption_score,
    s.score_pct_within_office,
    s.score_decile_within_office,
    s.risk_tier,
    f.raised_from_pharma,
    f.raised_from_finance,
    f.raised_from_defense,
    f.raised_from_energy,
    f.raised_from_tech,
    f.raised_from_aipac_aligned
from marts.mart_candidate_corruption_score s
join marts.mart_candidate_funding_summary f using (candidate_id)
where s.candidate_name ilike '%${params.candidate_name}%'
order by s.election_year desc
limit 1
```

<BigValue data={profile} value=corruption_score title="Corruption Score" />
<BigValue data={profile} value=risk_tier title="Risk Tier" />
<BigValue data={profile} value=total_raised title="Total Raised" fmt=usd />
<BigValue data={profile} value=score_pct_within_office title="Percentile in Office" fmt=pct1 />

---

## Funding Breakdown

```sql funding_mix
select 'PACs'         as source, pct_from_pacs         as pct from marts.mart_candidate_corruption_score where candidate_name ilike '%${params.candidate_name}%' limit 1
union all
select 'Individuals'  as source, pct_from_individuals  as pct from marts.mart_candidate_corruption_score where candidate_name ilike '%${params.candidate_name}%' limit 1
union all
select 'Dark Money'   as source, pct_dark_money        as pct from marts.mart_candidate_corruption_score where candidate_name ilike '%${params.candidate_name}%' limit 1
```

<BarChart data={funding_mix} x=source y=pct title="Funding Mix (%)" fmt=pct1 />

---

## Industry Contributions

```sql industry_breakdown
select
    ct.industry_group,
    sum(c.amount) as total
from intermediate.int_contributions_to_candidates c
join intermediate.int_committee_industry_tags ct
    on c.source_committee_id = ct.committee_id
join staging.stg_candidates cand
    on c.candidate_id = cand.cand_id
where cand.candidate_name ilike '%${params.candidate_name}%'
  and ct.industry_group != 'Unknown / Unclassified'
group by 1
order by total desc
```

<BarChart data={industry_breakdown} x=industry_group y=total title="By Industry" fmt=usd swapXY=true />

---

## Score Components

```sql score_components
select
    'PAC Concentration'   as component, penalty_pac_concentration as value, 'penalty' as type
    from marts.mart_candidate_corruption_score where candidate_name ilike '%${params.candidate_name}%' limit 1
union all select 'Dark Money',         penalty_dark_money,        'penalty' from marts.mart_candidate_corruption_score where candidate_name ilike '%${params.candidate_name}%' limit 1
union all select 'Industry Capture',   penalty_industry_capture,  'penalty' from marts.mart_candidate_corruption_score where candidate_name ilike '%${params.candidate_name}%' limit 1
union all select 'Super PAC',          penalty_super_pac,         'penalty' from marts.mart_candidate_corruption_score where candidate_name ilike '%${params.candidate_name}%' limit 1
union all select 'Large Donors',       penalty_large_donors,      'penalty' from marts.mart_candidate_corruption_score where candidate_name ilike '%${params.candidate_name}%' limit 1
union all select 'Individual % Bonus', -bonus_individual_pct,     'bonus'   from marts.mart_candidate_corruption_score where candidate_name ilike '%${params.candidate_name}%' limit 1
union all select 'Donor Distribution Bonus', -bonus_donor_distribution, 'bonus' from marts.mart_candidate_corruption_score where candidate_name ilike '%${params.candidate_name}%' limit 1
```

<BarChart data={score_components} x=component y=value series=type title="Score Components" swapXY=true />
