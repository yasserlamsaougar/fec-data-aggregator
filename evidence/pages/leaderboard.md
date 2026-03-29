---
title: Corruption Score Leaderboard
---

# Donor-Capture Leaderboard

Ranked by corruption score — a composite of PAC concentration, dark money, industry capture, Super PAC reliance, and large donor share, minus a grassroots bonus for candidates genuinely funded by small donors.

---

<Dropdown name=office_filter title="Office">
    <DropdownOption value="%" valueLabel="All Offices" />
    <DropdownOption value="Senate" />
    <DropdownOption value="House" />
    <DropdownOption value="President" />
</Dropdown>

<Dropdown name=party_filter title="Party">
    <DropdownOption value="%" valueLabel="All Parties" />
    <DropdownOption value="Democrat" />
    <DropdownOption value="Republican" />
    <DropdownOption value="Independent" />
</Dropdown>

<Dropdown name=year_filter title="Election Year">
    <DropdownOption value="%" valueLabel="All Years" />
    <DropdownOption value="2024" />
    <DropdownOption value="2022" />
    <DropdownOption value="2020" />
</Dropdown>

```sql leaderboard
select
    candidate_name,
    party_name,
    office,
    office_state,
    election_year,
    total_raised,
    pct_from_pacs,
    pct_from_individuals,
    pct_dark_money,
    pct_super_pac,
    median_individual_donation,
    pct_individual_from_large,
    unique_donor_count,
    corruption_score,
    score_pct_within_office,
    score_decile_within_office,
    risk_tier
from marts.mart_candidate_corruption_score
where office     like '${inputs.office_filter}'
  and party_name like '${inputs.party_filter}'
  and election_year::varchar like '${inputs.year_filter}'
order by corruption_score desc
limit 100
```

<DataTable data={leaderboard} rows=50 search=true>
    <Column id=candidate_name title="Candidate" />
    <Column id=party_name title="Party" />
    <Column id=office title="Office" />
    <Column id=office_state title="State" />
    <Column id=election_year title="Year" />
    <Column id=total_raised title="Total Raised" fmt=usd />
    <Column id=pct_from_pacs title="% PAC" fmt=pct1 />
    <Column id=pct_dark_money title="% Dark $" fmt=pct1 />
    <Column id=unique_donor_count title="Unique Donors" />
    <Column id=median_individual_donation title="Median Donation" fmt=usd />
    <Column id=pct_individual_from_large title="% Large Indiv." fmt=pct1 />
    <Column id=corruption_score title="Score" />
    <Column id=score_pct_within_office title="Pct in Office" fmt=pct1 />
    <Column id=risk_tier title="Risk" />
</DataTable>

---

## Score Distribution

```sql score_dist
select
    office,
    corruption_score,
    party_name
from marts.mart_candidate_corruption_score
where office like '${inputs.office_filter}'
  and party_name like '${inputs.party_filter}'
```

<Histogram data={score_dist} x=corruption_score title="Score Distribution" series=party_name />
