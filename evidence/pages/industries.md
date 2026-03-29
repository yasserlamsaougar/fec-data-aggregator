---
title: Industry Money
---

# Who Buys Congress?

How much each industry sector spends across federal elections, and which candidates and parties receive it.

---

```sql industry_totals
select
    ct.industry_group,
    count(distinct c.candidate_id)          as candidates_funded,
    sum(c.amount)                           as total_contributed,
    avg(s.corruption_score)                 as avg_candidate_score
from intermediate.int_contributions_to_candidates c
join intermediate.int_committee_industry_tags ct
    on c.source_committee_id = ct.committee_id
join marts.mart_candidate_corruption_score s
    on c.candidate_id = s.candidate_id
where ct.industry_group != 'Unknown / Unclassified'
group by 1
order by total_contributed desc
```

<BarChart
    data={industry_totals}
    x=industry_group
    y=total_contributed
    title="Total Contributed by Industry"
    fmt=usd
    swapXY=true
/>

---

## Industry vs Party

```sql industry_party
select
    ct.industry_group,
    cand.party_name,
    sum(c.amount)   as total
from intermediate.int_contributions_to_candidates c
join intermediate.int_committee_industry_tags ct
    on c.source_committee_id = ct.committee_id
join staging.stg_candidates cand
    on c.candidate_id = cand.cand_id
where ct.industry_group != 'Unknown / Unclassified'
  and cand.party_name in ('Democrat', 'Republican')
group by 1, 2
order by total desc
```

<BarChart
    data={industry_party}
    x=industry_group
    y=total
    series=party_name
    title="Industry Spending by Party"
    swapXY=true
    type=grouped
/>

---

## Top Recipients per Industry

<Dropdown name=industry_select title="Industry">
    <DropdownOption value="Pharma & Healthcare" />
    <DropdownOption value="Finance & Banking" />
    <DropdownOption value="Defense & Military" />
    <DropdownOption value="Energy & Oil" />
    <DropdownOption value="Tech & Telecom" />
    <DropdownOption value="Israel / AIPAC-aligned" />
    <DropdownOption value="Labor" />
</Dropdown>

```sql top_recipients
select
    cand.candidate_name,
    cand.party_name,
    cand.office,
    cand.office_state,
    cand.election_year,
    sum(c.amount)               as received,
    s.corruption_score,
    s.risk_tier
from intermediate.int_contributions_to_candidates c
join intermediate.int_committee_industry_tags ct
    on c.source_committee_id = ct.committee_id
join staging.stg_candidates cand
    on c.candidate_id = cand.cand_id
join marts.mart_candidate_corruption_score s
    on c.candidate_id = s.candidate_id
where ct.industry_group = '${inputs.industry_select}'
group by 1, 2, 3, 4, 5, 7, 8
order by received desc
limit 25
```

<DataTable data={top_recipients} rows=25>
    <Column id=candidate_name title="Candidate" />
    <Column id=party_name title="Party" />
    <Column id=office title="Office" />
    <Column id=office_state title="State" />
    <Column id=election_year title="Year" />
    <Column id=received title="Received" fmt=usd />
    <Column id=corruption_score title="Score" />
    <Column id=risk_tier title="Risk" />
</DataTable>
