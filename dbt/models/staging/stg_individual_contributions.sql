-- Individual donor contributions to committees.
-- This is the largest FEC file — millions of rows per cycle.

with source as (
    select * from {{ source('raw', 'individual_contributions') }}
),

cleaned as (
    select
        sub_id                                               as transaction_id,
        trim(cmte_id)                                        as committee_id,
        -- Raw fields preserved for audit
        trim(name)                                           as donor_name_raw,
        trim(employer)                                       as donor_employer_raw,

        -- Normalized for display
        {{ normalize_name('name') }}                         as donor_name,
        {{ normalize_name('city') }}                         as donor_city,
        state                                                as donor_state,
        zip_code                                             as donor_zip,
        {{ normalize_name('occupation') }}                   as donor_occupation,

        -- Employer: normalized for display AND consistent taxonomy matching
        -- Standardizes & → And, strips Inc/LLC/Corp suffixes, title cases
        {{ normalize_employer('employer') }}                 as donor_employer,
        transaction_amt::decimal(12, 2)                      as amount,

        -- Parse FEC date format MMDDYYYY → proper date
        case
            when len(transaction_dt) = 8
            then strptime(transaction_dt, '%m%d%Y')::date
            else null
        end                                                  as transaction_date,

        transaction_tp                                       as transaction_type,
        -- Common types: 10=contribution, 11=tribal, 15=earmarked, 22Y=refund
        (transaction_tp like '22%' or transaction_amt::decimal(12,2) < 0)  as is_refund,

        entity_tp                                            as entity_type,
        -- IND=Individual, ORG=Organization, PAC, PTY=Party, CCM=Candidate Committee
        (entity_tp = 'IND')                                  as is_individual_donor,

        transaction_pgi                                      as election_type,
        -- P=Primary, G=General, R=Runoff, S=Special, E=Recount, C=Convention

        tran_id                                              as fec_transaction_id,
        memo_text                                            as memo,
        other_id                                             as earmarked_to_committee_id

    from source
    where transaction_amt is not null
)

select
    *,
    -- Donation size buckets (FEC itemization threshold is $200)
    case
        when is_refund                   then 'refund'
        when amount < 200                then 'small'       -- unitemized, anonymous
        when amount between 200 and 999  then 'medium'
        when amount between 1000 and 2999 then 'large'
        when amount >= 3000              then 'major'       -- max individual limit is $3,300/cycle (2024)
    end                                                      as donation_size_bucket

from cleaned
