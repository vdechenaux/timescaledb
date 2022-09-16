-- This file and its contents are licensed under the Timescale License.
-- Please see the included NOTICE for copyright information and
-- LICENSE-TIMESCALE for a copy of the license.

\c :TEST_DBNAME :ROLE_SUPERUSER
CREATE OR REPLACE FUNCTION _timescaledb_internal.test_merge_chunks_on_dimension(chunk REGCLASS, merge_chunk REGCLASS, dimension_id INTEGER)
 RETURNS VOID
    AS :TSL_MODULE_PATHNAME, 'ts_test_merge_chunks_on_dimension' LANGUAGE C VOLATILE;
\c :TEST_DBNAME :ROLE_DEFAULT_PERM_USER

CREATE TABLE test1 ("Time" timestamptz, i integer, value integer);
SELECT table_name FROM Create_hypertable('test1', 'Time', chunk_time_interval=> INTERVAL '1 hour');
SELECT table_name FROM  add_dimension('test1', 'i', number_partitions=> 2);
ALTER TABLE test1 set (timescaledb.compress, timescaledb.compress_segmentby='i', timescaledb.compress_orderby='"Time"', timescaledb.compress_chunk_time_interval='2 hours');

-- This creates chunks 1 - 3 on first hypertable.
INSERT INTO test1 SELECT t, 1, 1.0 FROM generate_series('2018-03-02 1:00'::TIMESTAMPTZ, '2018-03-02 3:00', '1 minute') t;
-- This creates chunks 4 - 6 on first hypertable.
INSERT INTO test1 SELECT t, 2, 1.0 FROM generate_series('2018-03-02 1:00'::TIMESTAMPTZ, '2018-03-02 3:00', '1 minute') t;

CREATE TABLE test2 ("Time" timestamptz, i integer, value integer);
SELECT table_name FROM Create_hypertable('test2', 'Time', chunk_time_interval=> INTERVAL '1 hour');

-- This creates chunks 7 - 9 on second hypertable.
INSERT INTO test2 SELECT t, 1, 1.0 FROM generate_series('2018-03-02 1:00'::TIMESTAMPTZ, '2018-03-02 3:00', '1 minute') t;

SELECT * FROM _timescaledb_catalog.chunk;

\set ON_ERROR_STOP 0

-- Cannot merge chunks from different hypertables
SELECT _timescaledb_internal.test_merge_chunks_on_dimension('_timescaledb_internal._hyper_1_1_chunk','_timescaledb_internal._hyper_3_7_chunk', 1);

-- Cannot merge non-adjacent chunks
SELECT _timescaledb_internal.test_merge_chunks_on_dimension('_timescaledb_internal._hyper_1_1_chunk','_timescaledb_internal._hyper_1_3_chunk', 1);

-- Cannot merge same chunk to itself (its not adjacent to itself).
SELECT _timescaledb_internal.test_merge_chunks_on_dimension('_timescaledb_internal._hyper_1_1_chunk','_timescaledb_internal._hyper_1_1_chunk', 1);

-- Cannot merge chunks on with different partitioning schemas.
SELECT _timescaledb_internal.test_merge_chunks_on_dimension('_timescaledb_internal._hyper_1_1_chunk','_timescaledb_internal._hyper_1_4_chunk', 1);

-- Cannot merge chunks on with non-existant dimension slice.
-- NOTE: we are merging the same chunk just so they have the exact same partitioning schema and we don't hit the previous test error.
SELECT _timescaledb_internal.test_merge_chunks_on_dimension('_timescaledb_internal._hyper_1_1_chunk','_timescaledb_internal._hyper_1_1_chunk', 999);


\set ON_ERROR_STOP 1

-- Merge on open (time) dimension.
SELECT _timescaledb_internal.test_merge_chunks_on_dimension('_timescaledb_internal._hyper_1_5_chunk','_timescaledb_internal._hyper_1_6_chunk', 1);

-- Merge on closed dimension.
SELECT _timescaledb_internal.test_merge_chunks_on_dimension('_timescaledb_internal._hyper_1_1_chunk','_timescaledb_internal._hyper_1_4_chunk', 2);

SELECT compress_chunk(i) FROM show_chunks('test1') i;

\set ON_ERROR_STOP 0

-- Cannot merge chunks internal compressed chunks, no dimensions on them.
SELECT _timescaledb_internal.test_merge_chunks_on_dimension('_timescaledb_internal.compress_hyper_2_10_chunk','_timescaledb_internal.compress_hyper_2_11_chunk', 1);

\set ON_ERROR_STOP 1

-- This creates more data so caggs has multiple chunks.
INSERT INTO test1 SELECT t, 1, 1.0 FROM generate_series('2018-03-02 3:00'::TIMESTAMPTZ, '2018-03-03 3:00', '1 minute') t;

CREATE MATERIALIZED VIEW test_cagg
WITH (timescaledb.continuous) AS
SELECT i,
   time_bucket(INTERVAL '1 hour', "Time") AS bucket,
   AVG(value)
FROM test1
GROUP BY i, bucket;

-- Merging cagg chunks should also work.
SELECT _timescaledb_internal.test_merge_chunks_on_dimension('_timescaledb_internal._hyper_4_37_chunk','_timescaledb_internal._hyper_4_39_chunk', 4);