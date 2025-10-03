SET search_path=information_schema;
--\getenv newschema ATL_NEWSCHEMA
--\echo Creating schema :'newschema'
--create schema :newschema;
\echo create schema if not exists  rt;
-- Table inheritance may affect use of indexes, so let's apply it only to tables we need
WITH relevant_tables(table_schema, table_pattern) AS (VALUES 
	('public', '^project') -- This include projectcategory, project_key etc
	,('public', '^nodeassociation')
	,('public', '^searchrequest')
	,('public', '^sharepermissions')
	,('public', '^issuestatus')
	,('public', '^issuetype')
	,('public', '^priority')
	,('public', '^remotelink')
	,('public', '^customfieldvalue') -- For sprint refs
	,('public', '^AO_60DB71_')  -- Agile boards
	,('public', '^AO_24D977_')	-- Rich filters
)
-- Inherit indexes with the LIKE ... INCLUDING syntax. https://dzone.com/articles/table-inheritance-whats-it-good-for
SELECT format('create table if not exists %s.%I ( like %I.%I INCLUDING INDEXES,  oldid %s unique) inherits (%I.%I);', 'rt', TABLE_NAME, table_schema, TABLE_NAME, columns.data_type, table_schema, TABLE_NAME)
-- 'Unique' allows duplicate nulls (e.g. for nodeassociations where we have no oldid)  not not real values
FROM relevant_tables
JOIN TABLES USING (table_schema)
JOIN table_constraints USING (table_catalog,
                              table_schema,
                              TABLE_NAME)
JOIN constraint_table_usage USING (table_catalog,
                                   table_schema,
                                   TABLE_NAME,
                                   CONSTRAINT_CATALOG,
                                   CONSTRAINT_SCHEMA,
                                   CONSTRAINT_NAME)
JOIN constraint_column_usage USING (table_catalog,
                                    table_schema,
                                    TABLE_NAME,
                                    CONSTRAINT_CATALOG,
                                    CONSTRAINT_SCHEMA,
                                    CONSTRAINT_NAME)
JOIN columns USING (table_catalog,
                    table_schema,
                    TABLE_NAME,
                    COLUMN_NAME)
WHERE table_schema='public'
  AND constraint_type='PRIMARY KEY'
  AND table_name ~ relevant_tables.table_pattern
--\gexec
