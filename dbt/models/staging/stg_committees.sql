-- Political committees registered with the FEC.
-- Includes candidate campaign committees, PACs, party committees, etc.

with source as (
    select * from {{ source('raw', 'committees') }}
)

select
    trim(cmte_id)                                        as committee_id,
    trim(cmte_nm)                                        as committee_name_raw,
    {{ normalize_name('cmte_nm') }}                      as committee_name,
    case cmte_dsgn
        when 'A' then 'Authorized by Candidate'
        when 'B' then 'Lobbyist/Registrant PAC'
        when 'D' then 'Leadership PAC'
        when 'J' then 'Joint Fundraiser'
        when 'P' then 'Principal Campaign Committee'
        when 'U' then 'Unauthorized'
        else cmte_dsgn
    end                                                  as committee_designation,
    case cmte_tp
        when 'C' then 'Communication Cost'
        when 'D' then 'Delegate'
        when 'E' then 'Electioneering Communication'
        when 'H' then 'House'
        when 'I' then 'Independent Expenditor (Person or Group)'
        when 'N' then 'PAC - Nonqualified'
        when 'O' then 'Super PAC (Independent Expenditure-Only)'
        when 'P' then 'Presidential'
        when 'Q' then 'PAC - Qualified'
        when 'S' then 'Senate'
        when 'U' then 'Single Candidate Independent Expenditure'
        when 'V' then 'PAC with Non-Contribution Account - Nonqualified'
        when 'W' then 'PAC with Non-Contribution Account - Qualified'
        when 'X' then 'Party - Nonqualified'
        when 'Y' then 'Party - Qualified'
        when 'Z' then 'National Party Nonfederal Account'
        else cmte_tp
    end                                                  as committee_type,
    -- Flag Super PACs (unlimited outside spending, often dark money vehicle)
    (cmte_tp = 'O')                                      as is_super_pac,
    cmte_pty_affiliation                                 as party_code,
    case org_tp
        when 'C' then 'Corporation'
        when 'L' then 'Labor Organization'
        when 'M' then 'Membership Organization'
        when 'T' then 'Trade Association'
        when 'V' then 'Cooperative'
        when 'W' then 'Corporation w/o Capital Stock'
        else 'Unknown / Individual'
    end                                                  as organization_type,
    trim(connected_org_nm)                               as connected_organization_name_raw,
    {{ normalize_employer('connected_org_nm') }}         as connected_organization_name,
    trim(cand_id)                                        as candidate_id,
    {{ normalize_name('cmte_city') }}                    as committee_city,
    cmte_st                                              as committee_state,
    cmte_zip                                             as committee_zip

from source
