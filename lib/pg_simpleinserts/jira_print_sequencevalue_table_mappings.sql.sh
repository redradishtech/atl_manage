#!/bin/bash
cat <<EOF
\\timing off
WITH seqnames (seq_name, id) AS
$(cat "$ATL_APPDIR/atlassian-jira/WEB-INF/classes/entitydefs/entitymodel.xml" | xq '.entitymodel.entity | map([."@entity-name", ."@table-name"])' | tr '[]' '()' | tr '"' "'" | sed -e 's/^($/(VALUES/')
, tablenames AS (
	-- http://stackoverflow.com/questions/95967/how-do-you-list-the-primary-key-of-a-sql-server-table
        --SELECT Tab.table_name,replace(Tab.table_name, '_', '') AS id, Col.Column_Name as primarykey from
        SELECT Tab.table_name, Tab.table_name AS id, Col.Column_Name as primarykey from
            INFORMATION_SCHEMA.TABLE_CONSTRAINTS Tab,
            INFORMATION_SCHEMA.CONSTRAINT_COLUMN_USAGE Col
        WHERE
            Col.Constraint_Name = Tab.Constraint_Name
            AND Col.Table_Name = Tab.Table_Name
            AND Constraint_Type = 'PRIMARY KEY'
        AND Tab.Table_Schema='public'
)
select seqnames.seq_name, tablenames.table_name, tablenames.primarykey from seqnames full outer JOIN tablenames ON seqnames.id = tablenames.id WHERE seq_name is not null AND table_name is not null;
EOF
