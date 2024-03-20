-- This file and its contents are licensed under the Timescale License.
-- Please see the included NOTICE for copyright information and
-- LICENSE-TIMESCALE for a copy of the license.

\c :TEST_DBNAME :ROLE_SUPERUSER

\ir include/setup_hyperstore.sql

-- TODO(#1068) Parallel sequence scan does not work
set max_parallel_workers_per_gather to 0;

select twist_chunk(show_chunks(:'hypertable'));

-- Check that all chunks are compressed
select chunk_name, compression_status from chunk_compression_stats(:'hypertable');

select relname, amname
  from pg_class join pg_am on (relam = pg_am.oid)
 where pg_class.oid in (select show_chunks(:'hypertable'))
order by relname;

-- Pick a random row to update
\x on
select * from :hypertable order by created_at offset 577 limit 1;
select created_at, location_id, owner_id, device_id
from :hypertable order by created_at offset 577 limit 1 \gset
\x off

-- Test updating the same row using segment-by column, other lookup column
explain (costs off)
update :hypertable set temp = 100.0 where created_at = :'created_at';
\x on
select * from :hypertable where created_at = :'created_at';
update :hypertable set temp = 100.0 where created_at = :'created_at';
select * from :hypertable where created_at = :'created_at';
\x off

-- Disable checks on max tuples decompressed per transaction
set timescaledb.max_tuples_decompressed_per_dml_transaction to 0;

-- Using the segmentby attribute that has an index
explain (costs off)
update :hypertable set humidity = 110.0 where location_id = :location_id;
select count(*) from :hypertable where humidity = 110.0;
update :hypertable set humidity = 110.0 where location_id = :location_id;
select count(*) from :hypertable where humidity = 110.0;

-- Testing to select for update, and then perform an update of those
-- rows. The selection is to make sure that we have a mix of
-- compressed and uncompressed tuples.
start transaction;
select _timescaledb_debug.is_compressed_tid(ctid),
       metric_id, created_at
  into to_update
  from :hypertable
 where metric_id between 1000 and 1005
order by metric_id for update;

select * from to_update order by metric_id;

update :hypertable set humidity = 200.0, temp = 500.0
where (created_at, metric_id) in (select created_at, metric_id from to_update);

select * from :hypertable where humidity = 200.0 order by metric_id;
commit;
