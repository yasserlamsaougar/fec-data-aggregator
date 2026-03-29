-- Candidate financial summary from FEC F3/F3P campaign filings (weball*.zip).
-- One row per candidate per election cycle.
--
-- This is the AUTHORITATIVE total for how much a campaign raised, including
-- unitemized small-donor contributions (<$200) that never appear in the
-- individual contribution transaction file (indiv).
--
-- The weball file has 30 columns (FEC all-candidates file format):
-- https://www.fec.gov/campaign-finance-data/all-candidates-file-description/
--
-- NOTE: weball does NOT break out itemized vs unitemized individual contributions.
-- It only provides ttl_indiv_contrib (total). ind_unitemized_reported is therefore
-- not available from this file and is excluded from downstream marts.

with source as (
    select * from {{ source('raw', 'candidate_financial_summary') }}
)

select
    trim(cand_id)                                        as cand_id,
    trim(cand_name)                                      as cand_name_raw,
    trim(cand_ici)                                       as cand_ici,
    trim(pty_cd)                                         as party_code,
    trim(cand_office_st)                                 as cand_state,

    -- Core receipt totals (self-reported by campaign)
    try_cast(ttl_receipts          as decimal(18, 2))    as tot_rec,
    try_cast(ttl_indiv_contrib     as decimal(18, 2))    as ind_con,
    try_cast(other_pol_cmte_contrib as decimal(18, 2))   as oth_com_con,
    try_cast(pol_pty_contrib        as decimal(18, 2))   as par_com_con,
    try_cast(cand_contrib           as decimal(18, 2))   as can_con,
    try_cast(cand_loans             as decimal(18, 2))   as cand_loans,
    try_cast(other_loans            as decimal(18, 2))   as other_loans,

    -- Disbursement / balance
    try_cast(ttl_disb               as decimal(18, 2))   as tot_dis,
    try_cast(coh_cop                as decimal(18, 2))   as cash_on_hand_close,
    try_cast(debts_owed_by          as decimal(18, 2))   as debts_owed,

    -- Refunds
    try_cast(indiv_refunds          as decimal(18, 2))   as ind_ref,
    try_cast(cmte_refunds           as decimal(18, 2))   as cmte_ref,

    -- Coverage period (weball only has end date, no start date)
    try_strptime(nullif(trim(cvg_end_dt), ''), '%m/%d/%Y') as coverage_end_date,

    -- Election year: weball has no explicit fec_election_yr column; use cycle_year
    -- added by the loader (which is the cycle the file was downloaded for).
    cycle_year                                           as fec_election_yr,
    cycle_year

from source
where trim(cand_id) != ''
