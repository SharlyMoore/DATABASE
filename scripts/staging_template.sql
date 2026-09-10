create schema if not exists staging;

create or replace view staging.regions as
select * from read_csv('data/refs/regions.csv');

create or replace view staging.mcc as
select * from read_csv('data/refs/mcc_codes.csv', all_varchar=true);

create or replace view staging.merchants as
select * from read_csv('data/processing/merchants.csv', all_varchar=true);

-- ОБРАЗЕЦ 1

create or replace view staging.clients as
with raw as (
    select * from read_csv('data/abs/clients.csv', delim=';', all_varchar=true)
),
typed as (
    select
        client_id,
        trim(regexp_replace(fio, ' +', ' ')) as fio,
        case when lower(gender) in ('м', 'муж') or gender = 'M'
             then 'М' else 'Ж' end as gender,
        case when birth_date like '%.%'
             then strptime(birth_date, '%d.%m.%Y')::date
             else birth_date::date end as birth_date,
        trim(replace(city, 'г. ', '')) as city,
        lower(segment) as segment,
        registered_at::timestamp as registered_at,
        updated_at::timestamp as updated_at
    from raw
)
select * from typed
qualify row_number() over (partition by client_id order by updated_at desc) = 1;

-- TODO 1
create or replace view staging.accounts as
select 
    account_id, 
    client_id, 
    product_code, 
    product_name,
    opened_at::DATE as opened_at,
    status
from read_csv('data/abs/accounts.csv', delim=';', all_varchar=true);

-- TODO 2

create or replace view staging.cards as
select 
    card_id, 
    account_id, 
    payment_system,
    issued_at::DATE as issued_at,
    status
from read_csv('data/abs/cards.csv', delim=';', all_varchar=true);

-- TODO 3

create or replace view staging.transactions as
with raw as (
    select * from read_parquet('data/processing/transactions_*.parquet')
)
select * from raw
qualify row_number() over (partition by txn_id order by txn_ts) = 1;


-- ОБРАЗЕЦ 2

create or replace view staging.rates as
select date::date as rate_date, 'USD' as ccy, valutes.USD.value as rate
from read_json('data/rates/cbr_rates.json')
union all
select date::date, 'EUR', valutes.EUR.value from read_json('data/rates/cbr_rates.json')
union all
select date::date, 'CNY', valutes.CNY.value from read_json('data/rates/cbr_rates.json');