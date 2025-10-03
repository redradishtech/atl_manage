;select distinct count(*), min(rt), min(urt), median(rt), median(urt), avg(rt), avg(urt), max(rt), max(urt), cs_method, sc_bytes, sc_status, cs_uri_stem, cs_uri_query from logline where cs_uri_stem like '%/batch.%' group by cs_method, sc_status, cs_uri_stem,cs_uri_query order by count(*) desc;
:echo Shows batch resource statistics
