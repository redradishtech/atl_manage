-- https://dba.stackexchange.com/questions/8239/how-to-easily-convert-utf8-tables-to-utf8mb4-in-mysql-5-5/104866#104866
SELECT concat("ALTER DATABASE `", table_schema, "` CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci;") AS _sql
FROM information_schema.`tables`
WHERE table_schema = database()
  AND table_type='BASE TABLE'
GROUP BY table_schema
UNION
SELECT concat("ALTER TABLE `", table_schema, "`.`", TABLE_NAME, "` CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;") AS _sql
FROM information_schema.`tables`
WHERE table_schema LIKE database()
  AND table_type='BASE TABLE'
GROUP BY table_schema,
         TABLE_NAME
UNION
SELECT concat("ALTER TABLE `", `columns`.table_schema, "`.`", `columns`.table_name, "` CHANGE `", COLUMN_NAME, "` `", COLUMN_NAME, "` ", data_type, "(", character_maximum_length, ") CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci", if(is_nullable="YES", " NULL", " NOT NULL"), ";") AS _sql
FROM information_schema.`columns`
INNER JOIN information_schema.`tables` ON `tables`.table_name = `columns`.table_name
WHERE `columns`.table_schema = database()
  AND data_type in ('varchar',
                    'char')
  AND table_type='BASE TABLE'
UNION
SELECT concat("ALTER TABLE `", `columns`.table_schema, "`.`", `columns`.table_name, "` CHANGE `", COLUMN_NAME, "` `", COLUMN_NAME, "` ", data_type, " CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci", if(is_nullable="YES", " NULL", " NOT NULL"), ";") AS _sql
FROM information_schema.`columns`
INNER JOIN information_schema.`tables` ON `tables`.table_name = `columns`.table_name
WHERE `columns`.table_schema = database()
  AND data_type in ('text',
                    'tinytext',
                    'mediumtext',
                    'longtext')
  AND table_type='BASE TABLE';
