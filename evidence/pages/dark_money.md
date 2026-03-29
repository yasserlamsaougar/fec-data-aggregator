---
title: Dark Money Tracker
---

# Dark Money Tracker

Super PACs with no identifiable industry affiliation — committees designed to obscure who is really funding a candidate. These are flagged when a Super PAC's name and connected organization cannot be matched to any known industry in our taxonomy.

---

```sql dark_money_overview
select
    count(distinct committee_id)    as dark_money_pacs,
    sum(f.raised_from_dark_money)   as total_dark_money,
    avg(s.pct_dark_money)           as avg_pct_dark_money
from intermediate.int_committee_industry_tags ct
join marts.mart_candidate_funding_summary f on 1=1
join marts.mart_candidate_corruption_score s using (candidate_id)
where ct.is_dark_money_suspect
```

<BigValue data={dark_money_overview} value=dark_money_pacs title="Suspected Dark Money PACs" />
<BigValue data={dark_money_overview} value=total_dark_money title="Total Dark Money" fmt=usd />
<BigValue data={dark_money_overview} value=avg_pct_dark_money title="Avg % Dark Money per Candidate" fmt=pct1 />

---

## Suspected Dark Money Committees

Super PACs with vague names and no identifiable sponsor or industry connection.

```sql dark_pacs
select
    ct.committee_name,
    ct.connected_organization_name,
    ct.organization_type,
    count(distinct c.candidate_id)  as candidates_funded,
    sum(c.amount)                   as total_spent
from intermediate.int_committee_industry_tags ct
join intermediate.int_contributions_to_candidates c
    on ct.committee_id = c.source_committee_id
where ct.is_dark_money_suspect
group by 1, 2, 3
order by total_spent desc
limit 50
```

<DataTable data={dark_pacs} rows=50 search=true>
    <Column id=committee_name title="Committee Name" />
    <Column id=connected_organization_name title="Connected Org" />
    <Column id=organization_type title="Org Type" />
    <Column id=candidates_funded title="Candidates Funded" />
    <Column id=total_spent title="Total Spent" fmt=usd />
</DataTable>

---

## Candidates Most Funded by Dark Money

```sql dark_money_candidates
select
    s.candidate_name,
    s.party_name,
    s.office,
    s.office_state,
    s.election_year,
    f.raised_from_dark_money,
    s.pct_dark_money,
    s.corruption_score,
    s.risk_tier
from marts.mart_candidate_funding_summary f
join marts.mart_candidate_corruption_score s using (candidate_id)
where f.raised_from_dark_money > 0
order by f.raised_from_dark_money desc
limit 50
```

<BarChart
    data={dark_money_candidates}
    x=candidate_name
    y=raised_from_dark_money
    series=party_name
    title="Top Recipients of Dark Money"
    swapXY=true
    fmt=usd
/>

<DataTable data={dark_money_candidates} rows=50>
    <Column id=candidate_name title="Candidate" />
    <Column id=party_name title="Party" />
    <Column id=office title="Office" />
    <Column id=office_state title="State" />
    <Column id=election_year title="Year" />
    <Column id=raised_from_dark_money title="Dark Money" fmt=usd />
    <Column id=pct_dark_money title="% of Total" fmt=pct1 />
    <Column id=corruption_score title="Score" />
    <Column id=risk_tier title="Risk" />
</DataTable>
