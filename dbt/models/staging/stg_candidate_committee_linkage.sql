-- Links candidates to their authorized committees.
-- Essential for tracing money raised by committees back to the candidate.

with source as (
    select * from {{ source('raw', 'candidate_committee_linkage') }}
)

select
    linkage_id,
    trim(cand_id)                     as candidate_id,
    cand_election_yr::integer         as candidate_election_year,
    fec_election_yr::integer          as fec_election_year,
    cmte_id                           as committee_id,
    cmte_tp                           as committee_type,
    case cmte_dsgn
        when 'P' then 'Principal Campaign Committee'
        when 'A' then 'Authorized by Candidate'
        when 'D' then 'Leadership PAC'
        when 'J' then 'Joint Fundraiser'
        else cmte_dsgn
    end                               as committee_designation

from source
