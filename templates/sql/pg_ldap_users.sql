-- SQL to print valid 'ldapsearch' commands, emulating the user search done by Atlassian apps.
-- See https://www.redradishtech.com/display/KB/Testing+LDAP+connectivity+with+ldapsearch
-- 
-- For this to work, first 'CREATE EXTENSION tablefunc' as a superuser
--
-- Note: the LDAPTLS_REQCERT=never prevents badly-reported failures if the TLS cert isn't trusted (I figure it's not this script's job to worry about that). See https://unix.stackexchange.com/questions/68377/how-to-make-ldapsearch-working-on-sles-over-tls-using-certificate and http://lpetr.org/blog/archives/update-openldap-ssl-certificate-centos-6

\echo # Please first run:
\echo # atl_psql --super -c ''''create extension if not exists tablefunc;''''
WITH ldapdetails AS (
    select * from crosstab('select directory_id, attribute_name, attribute_value from cwd_directory_attribute order by 1,2',
        $$values ('ldap.url'),
        ('ldap.userdn'),
        ('ldap.password'),
        ('ldap.basedn'),
        ('ldap.user.dn'),
        ('ldap.user.filter'),
        ('ldap.user.username'),
        ('ldap.user.displayname'),
        ('ldap.user.email'),
        ('ldap.user.firstname'),
        ('ldap.user.lastname')
        $$)
    AS ct(directory_id int,
        "url" varchar,
        "userdn" varchar,
        "password" varchar,
        "basedn" varchar,
        "user.dn" varchar,
        "user.filter" varchar,
        "user.username" varchar,
        "user.displayname" varchar,
        "user.email" varchar,
        "user.firstname" varchar,
        "user.lastname" varchar)
)
SELECT '# For directory ' || directory_id || '
'
|| 'LDAPTLS_REQCERT=never ldapsearch -LL -x -z5 '
|| '-H ' || url
|| coalesce(' -D ''' || userdn || '''', '')
|| coalesce(' -w ''' || password || '''', '')
|| coalesce(' -b ''' || basedn || '''', '')
|| ' -s sub ''' || "user.filter" || ''''
|| ' ' || "user.username"
|| ' ' || "user.displayname"
|| ' ' || "user.firstname"
|| ' ' || "user.lastname"
|| ' ' || "user.email"
FROM ldapdetails JOIN cwd_directory ON ldapdetails.directory_id = cwd_directory.id WHERE cwd_directory.directory_type='CONNECTOR';
