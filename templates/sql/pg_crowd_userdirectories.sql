--  For each 'Crowd' user directory configured (that is, Crowd or Crowd-embedded-in-Jira), print the connection details. Used by $ATL_APPDIR/monitoring/userdirectories.healthcheck to validate connectivity
-- '\echo # Please first run:'
-- "\\echo # atl_psql --super -c ''''create extension if not exists tablefunc;''''"
WITH crowddetails AS (
    select * from crosstab('select directory_id, attribute_name, attribute_value from cwd_directory JOIN cwd_directory_attribute ON cwd_directory.id=cwd_directory_attribute.directory_id where active::char in (''T'', ''1'')  order by 1,2',
        $$values ('crowd.server.url'),
        ('application.name'),
        ('application.password')
        $$)
    AS ct(directory_id int,
        "url" varchar,
        "username" varchar,
	"password" varchar)
)
SELECT directory_id, directory_name, url, username, password from crowddetails JOIN cwd_directory ON crowddetails.directory_id = cwd_directory.id WHERE directory_type='CROWD';
