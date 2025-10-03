-- SELECT format ('select %L AS table_name, md5(string_agg(row_hash, '''')) AS table_hash FROM (select md5(row_to_json(t)::text) AS row_hash FROM %I.%I t ORDER BY %I) sub;', t.table_name, table_schema, t.table_name, kcu.column_name)
SELECT format ('select %L AS table_name, count(*)  FROM %I.%I;', t.table_name, table_schema, t.table_name, kcu.column_name)
FROM information_schema.tables t
LEFT JOIN information_schema.table_constraints tc USING (table_schema,
                                                         TABLE_NAME)
LEFT JOIN information_schema.key_column_usage kcu USING (CONSTRAINT_NAME,
                                                         table_schema)
WHERE table_schema='public'
  AND t.table_type='BASE TABLE'
  AND tc.constraint_type='PRIMARY KEY'
ORDER BY t.table_name DESC;
