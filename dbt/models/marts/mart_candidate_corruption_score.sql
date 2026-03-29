-- Corruption / donor-capture score per candidate.
--
-- Score philosophy: a candidate with a high score has a funding profile
-- dominated by PACs, corporations, Super PACs, and dark money. A genuine
-- grassroots candidate — many small donors, low median donation, few
-- large bundlers — earns a bonus that lowers their score.
--
-- Penalty components (max 160 pts before clamping to 100):
--   70 pts  PAC concentration       — % of total from PACs (weight 0.70)
--   40 pts  Dark money              — % from unidentified Super PACs (weight 0.50)
--   30 pts  Large donor share       — donations ≥ $1,000 as % of total (weight 0.30)
--   20 pts  Super PAC reliance      — % from Super PAC committees (weight 0.30)
--   20 pts  Industry capture        — single industry dominates funding (weight 0.20)
--
-- Grassroots bonus (max −25 pts, reduces score):
--   15 pts  Individual donor %      — scaled by how much of individual money is
--                                     from small donors (penalises bundled-large-donor
--                                     candidates like Jeffries; rewards true grassroots)
--   10 pts  Donor distribution      — low median + low large-donor share
--
-- Net score range: 0–100 (clamped).
-- Percentiles computed within office type + election year for fair comparison.
--
-- Risk tiers:
--   Lower Risk:   0–14   (primarily grassroots-funded)
--   Moderate Risk: 15–44 (mixed institutional/individual profile)
--   High Risk:    45+    (dominated by PACs, dark money, or bundled large donors)
--
-- NOTE: This is a signal, not a verdict. Combine with policy records.

with funding as (
    select * from {{ ref('mart_candidate_funding_summary') }}
),

individual_contrib_sizes as (
    select
        ccl.candidate_id,
        sum(case when ic.amount >= 1000 then ic.amount else 0 end)  as large_donor_total,
        sum(ic.amount)                                               as individual_total
    from {{ ref('stg_individual_contributions') }} ic
    inner join {{ ref('stg_candidate_committee_linkage') }} ccl
        on ic.committee_id = ccl.committee_id
    where ic.is_individual_donor and not ic.is_refund
    group by 1
),

-- ── Step 1: compute all penalty and bonus components ─────────────────────
components as (
    select
        f.candidate_id,
        f.candidate_name,
        f.party_name,
        f.office,
        f.office_state,
        f.election_year,
        f.incumbent_challenger_status,
        f.total_raised,
        f.pct_from_pacs,
        f.pct_from_individuals,
        f.pct_dark_money,
        f.pct_super_pac,
        f.unique_donor_count,
        round(coalesce(f.median_individual_donation, 0), 2)          as median_individual_donation,
        coalesce(f.pct_individual_from_large, 100)                   as pct_individual_from_large,

        round(
            coalesce(ics.large_donor_total, 0)
            / nullif(f.total_raised, 0) * 100,
        2)                                                           as pct_large_donors,

        -- Largest single industry as % of total
        round(
            greatest(
                f.raised_from_pharma,
                f.raised_from_finance,
                f.raised_from_defense,
                f.raised_from_energy,
                f.raised_from_tech,
                f.raised_from_aipac_aligned
            ) / nullif(f.total_raised, 0) * 100,
        2)                                                           as pct_top_industry,

        -- ── Penalty components ────────────────────────────────────────
        least(f.pct_from_pacs       * 0.70, 70)                     as penalty_pac_concentration,
        least(f.pct_dark_money      * 0.50, 40)                     as penalty_dark_money,
        least(f.pct_super_pac       * 0.30, 20)                     as penalty_super_pac,
        least(
            round(coalesce(ics.large_donor_total,0)
                  / nullif(f.total_raised,0) * 100, 2) * 0.30,
        30)                                                          as penalty_large_donors,
        least(
            greatest(
                f.raised_from_pharma, f.raised_from_finance,
                f.raised_from_defense, f.raised_from_energy,
                f.raised_from_tech, f.raised_from_aipac_aligned
            ) / nullif(f.total_raised, 0) * 100 * 0.20,
        20)                                                          as penalty_industry_capture,

        -- ── Grassroots bonus components (subtract from score) ─────────
        -- Reward high individual donor % BUT only the small-donor portion.
        -- Scales by (1 − pct_individual_from_large) so a candidate like
        -- Jeffries who has 71% from individuals but 49% of that from
        -- $1,000+ bundlers earns roughly half the individual bonus.
        -- Max 15 pts off.
        least(
            f.pct_from_individuals * 0.15
            * greatest(0, 1.0 - coalesce(f.pct_individual_from_large, 100) / 100.0),
        15)                                                          as bonus_individual_pct,

        -- Reward genuine small-donor distribution (max 10 pts off).
        -- Uses MEDIAN (not average) to prevent flooding with micro-donations
        -- while hiding large bundlers.
        --   1. Low median donation (≤ $1,000 scale)  → up to 5 pts
        --   2. Low large-donor share of individual revenue → up to 5 pts
        greatest(0,
            least(
                (1000.0 - least(coalesce(f.median_individual_donation, 1000), 1000))
                    / 1000.0 * 5
                + (1.0 - least(coalesce(f.pct_individual_from_large, 100), 100) / 100.0) * 5,
            10)
        )                                                            as bonus_donor_distribution

    from funding f
    left join individual_contrib_sizes ics
        on f.candidate_id = ics.candidate_id
),

-- ── Step 2: sum components into final score ───────────────────────────────
scored as (
    select
        *,
        greatest(0, least(
            round(
                penalty_pac_concentration
                + penalty_dark_money
                + penalty_super_pac
                + penalty_large_donors
                + penalty_industry_capture
                - bonus_individual_pct
                - bonus_donor_distribution,
            1),
        100))                                                        as corruption_score
    from components
)

-- ── Step 3: add percentile rankings ──────────────────────────────────────
select
    *,

    -- Percentile within same office + year (primary comparison)
    round(
        percent_rank() over (
            partition by election_year, office
            order by corruption_score
        ) * 100,
    1)                                                               as score_pct_within_office,

    -- Decile within same office + year (1 = cleanest 10%, 10 = most captured 10%)
    ntile(10) over (
        partition by election_year, office
        order by corruption_score
    )                                                                as score_decile_within_office,

    -- Overall percentile across all candidates, all offices
    round(
        percent_rank() over (
            order by corruption_score
        ) * 100,
    1)                                                               as score_pct_overall,

    -- Risk tier (calibrated to penalty weight scale)
    case
        when corruption_score >= 45 then 'High Risk'
        when corruption_score >= 15 then 'Moderate Risk'
        else 'Lower Risk'
    end                                                              as risk_tier

from scored
order by corruption_score desc
