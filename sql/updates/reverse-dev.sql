DROP FUNCTION IF EXISTS  @extschema@.add_retention_policy(REGCLASS, "any", BOOL, INTERVAL);
CREATE FUNCTION @extschema@.add_retention_policy(relation REGCLASS, drop_after "any", if_not_exists BOOL = false)
RETURNS INTEGER AS '@MODULE_PATHNAME@', 'ts_policy_retention_add' LANGUAGE C VOLATILE STRICT;

DROP FUNCTION IF EXISTS  @extschema@.add_compression_policy(REGCLASS, "any", BOOL, INTERVAL);
CREATE FUNCTION @extschema@.add_compression_policy(hypertable REGCLASS, compress_after "any", if_not_exists BOOL = false)
RETURNS INTEGER AS '@MODULE_PATHNAME@', 'ts_policy_compression_add' LANGUAGE C VOLATILE STRICT;

DROP FUNCTION IF EXISTS @extschema@.detach_data_node;
CREATE FUNCTION @extschema@.detach_data_node(
    node_name              NAME,
    hypertable             REGCLASS = NULL,
    if_attached            BOOLEAN = FALSE,
    force                  BOOLEAN = FALSE,
    repartition            BOOLEAN = TRUE
) RETURNS INTEGER
AS '@MODULE_PATHNAME@', 'ts_data_node_detach' LANGUAGE C VOLATILE;

DROP FUNCTION _timescaledb_internal.attach_osm_table_chunk( hypertable REGCLASS, chunk REGCLASS);
DROP FUNCTION _timescaledb_internal.alter_job_set_hypertable_id( job_id INTEGER, hypertable REGCLASS );
DROP FUNCTION _timescaledb_internal.unfreeze_chunk( chunk REGCLASS);
-- Drop dimension partition metadata table
ALTER EXTENSION timescaledb DROP TABLE _timescaledb_catalog.dimension_partition;
DROP TABLE IF EXISTS _timescaledb_catalog.dimension_partition;
<<<<<<< HEAD
DROP FUNCTION IF EXISTS timescaledb_experimental.add_policies;
DROP FUNCTION IF EXISTS timescaledb_experimental.remove_policies;
DROP FUNCTION IF EXISTS timescaledb_experimental.remove_all_policies;
DROP FUNCTION IF EXISTS timescaledb_experimental.alter_policies;
DROP FUNCTION IF EXISTS timescaledb_experimental.show_policies;
DROP FUNCTION IF EXISTS @extschema@.remove_continuous_aggregate_policy(REGCLASS, BOOL, BOOL);
CREATE FUNCTION @extschema@.remove_continuous_aggregate_policy(continuous_aggregate REGCLASS, if_not_exists BOOL = false)
RETURNS VOID
AS '@MODULE_PATHNAME@', 'ts_policy_refresh_cagg_remove'
LANGUAGE C VOLATILE STRICT;

DROP VIEW IF EXISTS timescaledb_experimental.policies;

--
-- Rebuild the catalog table `_timescaledb_catalog.chunk`
--
-- We need to recreate the catalog from scratch because when we drop a column
-- Postgres marks `pg_attribute.attisdropped=TRUE` instead of removing it from
-- the `pg_catalog.pg_attribute` table.
--
-- If we downgrade and upgrade the extension without rebuilding the catalog table it
-- will mess up `pg_attribute.attnum` and we will end up with issues when trying
-- to update data in those catalog tables.

CREATE TABLE _timescaledb_catalog._tmp_chunk (
   LIKE _timescaledb_catalog.chunk
   INCLUDING ALL
   --create indexes and constraints with the correct names later
   EXCLUDING INDEXES
   EXCLUDING CONSTRAINTS
);

INSERT INTO _timescaledb_catalog._tmp_chunk
   SELECT id, hypertable_id,
          schema_name, table_name
          compressed_chunk_id ,
          dropped,
          status
   FROM _timescaledb_catalog.chunk
   ORDER BY id, hypertable_id ;

DROP TABLE _timescaledb_catalog.chunk;
ALTER EXTENSION timescaledb DROP TABLE _timescaledb_catalog.chunk;

ALTER TABLE _timescaledb_catalog._tmp_chunk RENAME TO chunk;

--now create constraints and indexes on the catalog chunk table
ALTER TABLE _timescaledb_catalog.chunk
ADD CONSTRAINT chunk_pkey PRIMARY KEY (id);
ALTER TABLE _timescaledb_catalog.chunk
ADD  CONSTRAINT chunk_schema_name_table_name_key UNIQUE (schema_name, table_name);
ALTER TABLE _timescaledb_catalog.chunk
ADD  CONSTRAINT chunk_compressed_chunk_id_fkey FOREIGN KEY (compressed_chunk_id) REFERENCES _timescaledb_catalog.chunk (id);
ALTER TABLE _timescaledb_catalog.chunk
ADD  CONSTRAINT chunk_hypertable_id_fkey FOREIGN KEY (hypertable_id) REFERENCES _timescaledb_catalog.hypertable (id);

CREATE INDEX chunk_hypertable_id_idx ON _timescaledb_catalog.chunk (hypertable_id);
CREATE INDEX chunk_compressed_chunk_id_idx ON _timescaledb_catalog.chunk (compressed_chunk_id);
CREATE INDEX chunk_osm_chunk_idx ON _timescaledb_catalog.chunk (hypertable_id, osm_chunk);

SELECT pg_catalog.pg_extension_config_dump('_timescaledb_catalog.chunk', '');
GRANT SELECT ON TABLE _timescaledb_catalog.chunk TO PUBLIC;
