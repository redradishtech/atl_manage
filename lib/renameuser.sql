-- PL/pgSQL function to rename a Jira/Confluence/Crowd user.
CREATE
OR REPLACE FUNCTION renameuser(oldusername varchar, newusername varchar) RETURNS void AS $$
DECLARE
nid integer;
BEGIN
update app_user
set lower_user_name=lower(newusername)
where lower_user_name = oldusername;
update cwd_user
set user_name=newusername,
    lower_user_name=lower(newusername)
where lower_user_name = lower(oldusername) returning id
into nid;
update cwd_membership
set child_name=newusername,
    lower_child_name=lower(newusername)
where lower_child_name = lower(oldusername);
raise
notice 'Renamed % to % (cwd_user record %)', oldusername, newusername, nid;
END
$$
LANGUAGE plpgsql ;
--select renameuser('jeff', 'jturner');
