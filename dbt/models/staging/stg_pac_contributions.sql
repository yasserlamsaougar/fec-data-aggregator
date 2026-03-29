-- PAC, party committee, and other committee contributions directly to candidates.
-- Key file for tracing organized money to specific candidates.

with source as (
    select * from {{ source('raw', 'pac_contributions') }}
)

select
    sub_id                                               as transaction_id,
    trim(cmte_id)                                        as contributor_committee_id,   -- who paid
    trim(cand_id)                                        as candidate_id,               -- who received

    transaction_amt::decimal(12, 2)                      as amount,
    (transaction_amt::decimal(12,2) < 0 or transaction_tp like '22%')   as is_refund,

    case
        when len(transaction_dt) = 8
        then strptime(transaction_dt, '%m%d%Y')::date
        else null
    end                                                  as transaction_date,

    transaction_tp                                       as transaction_type,
    transaction_pgi                                      as election_type,
    entity_tp                                            as entity_type,
    trim(name)                                           as contributor_name,
    trim(city)                                           as contributor_city,
    state                                                as contributor_state,
    trim(employer)                                       as contributor_employer,
    trim(occupation)                                     as contributor_occupation,
    other_id                                             as other_committee_id,
    tran_id                                              as fec_transaction_id,
    memo_text                                            as memo

from source
where transaction_amt is not null
