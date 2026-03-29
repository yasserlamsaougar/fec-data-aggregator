-- Top-level funding picture per candidate per cycle.
-- Industry tags flow in from int_contributions_to_candidates which uses:
--   - OpenSecrets crosswalk (PAC committees, highest confidence)
--   - Employer field (individual donors, precise)
--   - Committee keyword match (fallback)
--
-- ⚠️  COVERAGE LIMITATION — what this mart does NOT capture:
--
--   1. Leadership PAC fundraising: Candidates (especially party leaders) often
--      operate a separate leadership PAC (e.g. Jeffries' HOUSE MAJORITY PAC).
--      Individual donations to that PAC are not linked back to the candidate
--      via the CCL file, so they are entirely absent from individual_via_committee.
--
--   2. Joint fundraising committee (JFC) distributions: donors who give to a JFC
--      have their money split and forwarded to participating campaigns. That
--      forwarded amount arrives as a committee-to-committee transfer in pas2 and
--      is counted here as PAC/committee money rather than an individual donation.
--
--   3. Party committee coordinated expenditures and in-kind contributions.
--
--   total_raised (sum of captured transactions) is therefore lower than
--   total_receipts_reported (self-reported F3/F3P total). Use total_receipts_reported
--   as the authoritative headline total. pct_coverage shows how much of the
--   official total is captured in the itemized transaction data.

with contributions as (
    select * from {{ ref('int_contributions_to_candidates') }}
),

candidates as (
    select * from {{ ref('stg_candidates') }}
),

agg as (
    select
        c.candidate_id,
        -- Fallback to raw ID when cn file for the candidate's cycle wasn't loaded.
        -- Fix by loading more cn cycles: py scripts/download.py --file-types cn --cycles 2016 2018 2020 2022 --extract
        coalesce(cand.candidate_name, c.candidate_id)    as candidate_name,
        coalesce(cand.party_name, 'Unknown')             as party_name,
        coalesce(cand.office, 'Unknown')                 as office,
        coalesce(cand.office_state, 'Unknown')           as office_state,
        cand.election_year,
        coalesce(cand.incumbent_challenger_status, 'Unknown') as incumbent_challenger_status,
        (cand.cand_id is not null)                       as has_candidate_profile,

        count(*)                                                     as total_transactions,
        sum(c.amount)                                                as total_raised,

        -- By contribution path
        sum(case when c.contribution_path = 'pac_direct'  then c.amount else 0 end)
                                                                     as raised_from_pacs,
        sum(case when c.contribution_path = 'individual'  then c.amount else 0 end)
                                                                     as raised_from_individuals,

        -- By industry group (unified across PAC + individual sources)
        sum(case when c.industry_group = 'Pharma & Healthcare'      then c.amount else 0 end)
                                                                     as raised_from_pharma,
        sum(case when c.industry_group = 'Finance & Banking'        then c.amount else 0 end)
                                                                     as raised_from_finance,
        sum(case when c.industry_group = 'Defense & Military'       then c.amount else 0 end)
                                                                     as raised_from_defense,
        sum(case when c.industry_group = 'Energy & Oil'             then c.amount else 0 end)
                                                                     as raised_from_energy,
        sum(case when c.industry_group = 'Tech & Telecom'           then c.amount else 0 end)
                                                                     as raised_from_tech,
        sum(case when c.industry_group = 'Israel / AIPAC-aligned'   then c.amount else 0 end)
                                                                     as raised_from_aipac_aligned,
        sum(case when c.is_dark_money_suspect                        then c.amount else 0 end)
                                                                     as raised_from_dark_money,
        sum(case when c.is_super_pac                                 then c.amount else 0 end)
                                                                     as raised_from_super_pacs,

        -- Match source breakdown (shows how much was classified at each confidence tier)
        sum(case when c.match_source = 'opensecrets'      then c.amount else 0 end)
                                                                     as classified_by_opensecrets,
        sum(case when c.match_source = 'employer_keyword' then c.amount else 0 end)
                                                                     as classified_by_employer,
        sum(case when c.match_source = 'committee_keyword' then c.amount else 0 end)
                                                                     as classified_by_keyword,
        sum(case when c.match_source = 'unclassified'     then c.amount else 0 end)
                                                                     as unclassified_amount,

        -- Grassroots signals
        count(distinct case when c.contribution_path = 'individual'
            then c.donor_name end)                                   as unique_donor_count,

        percentile_cont(0.5) within group (
            order by case when c.contribution_path = 'individual'
                     then c.amount end
        )                                                            as median_individual_donation,

        round(
            sum(case when c.contribution_path = 'individual' and c.amount >= 1000
                then c.amount else 0 end)
            / nullif(
                sum(case when c.contribution_path = 'individual'
                    then c.amount end),
            0) * 100,
        2)                                                           as pct_individual_from_large

    from contributions c
    left join candidates cand on c.candidate_id = cand.cand_id
    group by 1, 2, 3, 4, 5, 6, 7, 8
),

-- Join in F3/F3P self-reported totals from the weball financial summary file.
-- tot_rec is the authoritative campaign total including unitemized small donations
-- (<$200) that are invisible in the itemized transaction file.
with_summary as (
    select
        agg.*,
        fs.tot_rec                              as total_receipts_reported,
        fs.ind_con                              as ind_total_reported,
        fs.coverage_end_date                    as financial_report_thru,
        -- Use official total as denominator where available; fall back to
        -- sum-of-transactions so the mart always has valid percentages.
        coalesce(fs.tot_rec, agg.total_raised)  as _effective_total
    from agg
    left join {{ ref('stg_candidate_financial_summary') }} fs
        on  agg.candidate_id = fs.cand_id
        and agg.election_year = fs.fec_election_yr
)

select
    -- Identity
    candidate_id,
    candidate_name,
    party_name,
    office,
    office_state,
    election_year,
    incumbent_challenger_status,
    has_candidate_profile,

    -- Volume
    total_transactions,

    -- Itemized transaction total (sum of captured individual + PAC rows).
    -- Always populated. Lower than total_receipts_reported because it excludes
    -- unitemized small donations, leadership PAC receipts, and JFC pass-throughs.
    total_raised,

    -- Self-reported campaign total from F3/F3P filings (null if weball not loaded).
    -- Includes unitemized small donations. Use as the headline fundraising figure.
    total_receipts_reported,

    -- Total individual contributions per campaign report (self-reported).
    -- weball does not separate itemized vs unitemized; use total_raised vs
    -- total_receipts_reported to infer the unitemized gap.
    ind_total_reported,

    -- How much of the official total is captured in itemized transactions.
    -- Low coverage = large unitemized small-donor base OR leadership PAC activity.
    round(total_raised / nullif(total_receipts_reported, 0) * 100, 2)
                                                                       as pct_coverage,

    -- Coverage period of the most recent financial report
    financial_report_thru,

    -- By contribution path
    raised_from_pacs,
    raised_from_individuals,

    -- By industry group
    raised_from_pharma,
    raised_from_finance,
    raised_from_defense,
    raised_from_energy,
    raised_from_tech,
    raised_from_aipac_aligned,
    raised_from_dark_money,
    raised_from_super_pacs,

    -- Classification confidence breakdown
    classified_by_opensecrets,
    classified_by_employer,
    classified_by_keyword,
    unclassified_amount,

    -- % of itemized money with a known industry (denominator is total_raised,
    -- not the official total, since unitemized donations cannot be classified)
    round((total_raised - unclassified_amount) / nullif(total_raised, 0) * 100, 2)
                                                                       as pct_classified,

    -- Grassroots signals
    unique_donor_count,
    median_individual_donation,
    pct_individual_from_large,

    -- Percentage ratios use official total as denominator when available.
    -- This correctly dilutes PAC/large-donor percentages by the unitemized
    -- small-donor base that is otherwise invisible in the transaction data.
    round(raised_from_pacs        / nullif(_effective_total, 0) * 100, 2) as pct_from_pacs,
    round(raised_from_individuals / nullif(_effective_total, 0) * 100, 2) as pct_from_individuals,
    round(raised_from_dark_money  / nullif(_effective_total, 0) * 100, 2) as pct_dark_money,
    round(raised_from_super_pacs  / nullif(_effective_total, 0) * 100, 2) as pct_super_pac

from with_summary
