-- Candidates running for federal office.
-- One row per candidate per election cycle.

-- NOTE: PAC contributions reference candidates from any election cycle, not just
-- the most recently loaded one. Load cn files for all relevant cycles to avoid
-- missing candidate profiles:
--   py scripts/download.py --cycles 2024 2022 2020 2018 2016 --file-types cn --extract
--   py scripts/load.py --cycles 2024 2022 2020 2018 2016
--
-- When multiple cycles are loaded, we deduplicate on cand_id keeping the most
-- recent record (highest election_year) so each candidate appears only once.

with source as (
    select * from {{ source('raw', 'candidates') }}
),

deduped as (
    select *
    from source
    qualify row_number() over (
        partition by cand_id
        order by cand_election_yr::integer desc
    ) = 1
)

select
    trim(cand_id)                                         as cand_id,

    -- Raw name preserved for joining/debugging
    trim(cand_name)                                      as candidate_name_raw,

    -- Parsed and normalized display fields
    -- FEC format: "SANDERS, BERNARD" → last="Sanders", first="Bernard", display="Bernard Sanders"
    {{ candidate_last_name('cand_name') }}               as last_name,
    {{ candidate_first_name('cand_name') }}              as first_name,
    {{ candidate_display_name('cand_name') }}            as candidate_name,

    cand_pty_affiliation                                 as party_code,
    case cand_pty_affiliation
        when 'DEM' then 'Democrat'
        when 'REP' then 'Republican'
        when 'IND' then 'Independent'
        when 'LIB' then 'Libertarian'
        when 'GRE' then 'Green'
        else 'Other / Unknown'
    end                                                  as party_name,

    cand_election_yr::integer                            as election_year,
    cand_office_st                                       as office_state,
    case cand_office
        when 'P' then 'President'
        when 'S' then 'Senate'
        when 'H' then 'House'
        else cand_office
    end                                                  as office,
    cand_office_district                                 as office_district,
    case cand_ici
        when 'I' then 'Incumbent'
        when 'C' then 'Challenger'
        when 'O' then 'Open Seat'
        else 'Unknown'
    end                                                  as incumbent_challenger_status,
    case cand_status
        when 'C' then 'Statutory Candidate'
        when 'F' then 'Statutory Candidate (future election)'
        when 'N' then 'Not Yet Statutory Candidate'
        when 'P' then 'Statutory Candidate (prior cycle)'
        else cand_status
    end                                                  as candidate_status,

    cand_pcc                                             as principal_campaign_committee_id,
    {{ normalize_name('cand_city') }}                    as candidate_city,
    cand_st                                              as candidate_state,
    cand_zip                                             as candidate_zip

from deduped
