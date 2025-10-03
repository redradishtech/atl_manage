begin;
	--delete from rt.customfieldvalue where oldid is null; Bug from prior import
	-- Copies rt.* rows into public.*, creating a copy in import.*
-- https://stackoverflow.com/questions/2679854/postgresql-disabling-constraints
\set ON_ERROR_STOP on
set session_replication_role to replica;
SET search_path=information_schema;
--\getenv newschema ATL_NEWSCHEMA
--\echo Creating schema :'newschema'
--create schema :newschema;

-- ONLY FOR THE FIRST RUN
--drop schema import cascade;
create schema import;
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
-- https://dba.stackexchange.com/questions/162978/using-a-create-table-as-select-how-do-i-specify-a-with-condition-cte
-- Inherit indexes with the LIKE ... INCLUDING syntax. https://dzone.com/articles/table-inheritance-whats-it-good-for
	--alter table public.%I disable trigger all;
-- The 'distinct' guards against rt.* already having duplicate records with duplicate ids. I don't know how such records got in there, but the lack of foreign key constraints allowed it.
SELECT format('
   	create table import.%I AS with del as (delete from public.%I where tableoid = (select ''rt.%I''::regclass::oid) returning *) select distinct * from del; 
	select * from import.%I;
	insert into public.%I select distinct  * from import.%I;
	drop table rt.%I;
', table_name, table_name, table_name, table_name, table_name, table_name, table_name, table_name, table_name, table_name, table_name, table_name)
FROM relevant_tables JOIN tables USING (table_schema) 
  WHERE table_name ~ relevant_tables.table_pattern \gexec
set session_replication_role to default;
