DROP FUNCTION IF EXISTS @extschema@.add_retention_policy(REGCLASS, "any", BOOL);
DROP FUNCTION IF EXISTS @extschema@.add_compression_policy(REGCLASS, "any", BOOL);
DROP FUNCTION IF EXISTS @extschema@.detach_data_node;
CREATE TABLE _timescaledb_catalog.dimension_partition (
  dimension_id integer NOT NULL REFERENCES _timescaledb_catalog.dimension (id) ON DELETE CASCADE,
  range_start bigint NOT NULL,
  data_nodes name[] NULL,
  UNIQUE (dimension_id, range_start)
);
SELECT pg_catalog.pg_extension_config_dump('_timescaledb_catalog.dimension_partition', '');
GRANT SELECT ON _timescaledb_catalog.dimension_partition TO PUBLIC;
DROP FUNCTION IF EXISTS @extschema@.remove_continuous_aggregate_policy(REGCLASS, BOOL);

ALTER TABLE _timescaledb_catalog.chunk ADD COLUMN  osm_chunk boolean NOT NULL DEFAULT FALSE;
CREATE INDEX chunk_osm_chunk_idx ON _timescaledb_catalog.chunk (hypertable_id, osm_chunk);
