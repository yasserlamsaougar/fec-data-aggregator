---
title: FEC Money Trail
---

# Follow the Money

Campaign finance is public record — buried in millions of rows of government data. This dashboard traces every dollar flowing through US federal elections using data from the [Federal Election Commission](https://www.fec.gov).

---

```sql overview
select
    count(distinct candidate_id)        as total_candidates,
    count(distinct election_year)       as cycles_covered,
    sum(total_raised)                   as total_money,
    avg(corruption_score)               as avg_corruption_score
from marts.mart_candidate_corruption_score
```

<BigValue data={overview} value=total_candidates title="Candidates Tracked" />
<BigValue data={overview} value=total_money title="Total Money in System" fmt=usd />
<BigValue data={overview} value=avg_corruption_score title="Avg Corruption Score" fmt=num2 />
<BigValue data={overview} value=cycles_covered title="Election Cycles" />

---

## Most Captured Candidates

The 20 candidates with the highest donor-capture score across all cycles.

```sql top_captured
select
    candidate_name,
    party_name,
    office,
    office_state,
    election_year,
    total_raised,
    pct_from_pacs,
    pct_dark_money,
    corruption_score,
    risk_tier,
    score_pct_within_office
from marts.mart_candidate_corruption_score
order by corruption_score desc
limit 20
```

<DataTable data={top_captured} rows=20>
    <Column id=candidate_name title="Candidate" />
    <Column id=party_name title="Party" />
    <Column id=office title="Office" />
    <Column id=office_state title="State" />
    <Column id=election_year title="Year" />
    <Column id=total_raised title="Total Raised" fmt=usd />
    <Column id=pct_from_pacs title="% PAC" fmt=pct1 />
    <Column id=pct_dark_money title="% Dark Money" fmt=pct1 />
    <Column id=corruption_score title="Score" />
    <Column id=risk_tier title="Risk" />
</DataTable>

---

## Money by Party

```sql party_totals
select
    party_name,
    count(distinct candidate_id)    as candidates,
    sum(total_raised)               as total_raised,
    avg(corruption_score)           as avg_score,
    avg(pct_from_pacs)              as avg_pct_pacs,
    avg(pct_dark_money)             as avg_pct_dark_money
from marts.mart_candidate_funding_summary f
join marts.mart_candidate_corruption_score s using (candidate_id)
where party_name in ('Democrat', 'Republican')
group by 1
order by total_raised desc
```

<BarChart data={party_totals} x=party_name y=total_raised title="Total Raised by Party" />
<BarChart data={party_totals} x=party_name y=avg_score title="Avg Corruption Score by Party" />

---

## Risk Tier Breakdown

```sql risk_breakdown
select
    risk_tier,
    office,
    count(*) as candidates
from marts.mart_candidate_corruption_score
group by 1, 2
order by office, candidates desc
```

<BarChart
    data={risk_breakdown}
    x=office
    y=candidates
    series=risk_tier
    title="Candidates by Risk Tier and Office"
    type=grouped
/>
