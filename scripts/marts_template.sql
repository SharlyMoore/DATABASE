create schema if not exists marts;


create or replace table marts.dim_date as
select cast(d as date)                                as date_actual,
       year(d) * 10000 + month(d) * 100 + day(d)      as date_sk,
       month(d)                                       as month,
       date_trunc('week', cast(d as date))            as week_start,
       isodow(d) in (6, 7)                            as is_weekend
from generate_series(date '2026-06-01', date '2026-08-31', interval 1 day) t(d);


create or replace table marts.dim_client as
select row_number() over (order by c.client_id)       as client_sk,
       c.client_id, c.fio, c.gender, c.birth_date,
       coalesce(r.city, c.city)                       as city,
       coalesce(r.region, 'Не определён')             as region,
       coalesce(r.federal_district, 'Не определён')   as federal_district,
       c.segment
from staging.clients c
left join staging.regions r on lower(r.city) = lower(c.city)
union all
select -1, 'UNKNOWN', 'Неизвестный клиент', null, null, null,
       'Не определён', 'Не определён', 'unknown';


create or replace table marts.dim_product as
select
    row_number() over (order by account_id) as product_sk,
    account_id,
    client_id,
    product_code,
    product_name
from staging.accounts
union all
select -1, NULL, NULL, 'UNKNOWN', 'Неизвестный продукт';


create or replace table marts.dim_merchant as
select
    row_number() over (order by m.merchant_id) as merchant_sk,
    m.merchant_id,
    m.merchant_name,
    coalesce(mcc.category, 'Неизвестно') as category,
    m.channel
from staging.merchants m
left join staging.mcc mcc on m.mcc = mcc.mcc
union all select -1, 'UNKNOWN', 'Неизвестный мерчант', 'Неизвестно', null
union all select -2, 'ATM',     'Снятие наличных',     'Наличные',  'atm'
union all select -3, 'P2P',     'Перевод СБП',         'Переводы',  'p2p';


create or replace table marts.fct_transactions as
select
    t.txn_id,
    d.date_sk,
    t.txn_ts,
    coalesce(dc.client_sk, -1) as client_sk,
    coalesce(dp.product_sk, -1) as product_sk,
    case t.channel when 'atm' then -2
                   when 'p2p' then -3
                   else coalesce(dm.merchant_sk, -1) end as merchant_sk,
    t.channel,
    t.status,
    t.amount                                          as amount_orig,
    t.currency,
    round(t.amount * coalesce(r.rate, 1.0), 2)        as amount_rub
from staging.transactions t
join marts.dim_date d           on d.date_actual = t.txn_ts::date
left join staging.cards k       using (card_id)
left join staging.accounts a    using (account_id)
left join marts.dim_client dc   on dc.client_id  = a.client_id
left join marts.dim_product dp  on dp.account_id = k.account_id
left join marts.dim_merchant dm on dm.merchant_id = t.merchant_id
asof left join staging.rates r
     on r.ccy = t.currency and r.rate_date <= t.txn_ts::date;

