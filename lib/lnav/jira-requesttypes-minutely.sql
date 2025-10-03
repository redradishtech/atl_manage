;
select 
	strftime('%H:%M', datetime(log_time || ':00')) AS time_bucket
	,round(cum_secs,2) AS cumulative_secs
	,round(sc_bytes/1024/1024,2) AS cumulative_mb
	,c AS "count"
	,regexp_replace(cs_uri_stem, '/s/.*/_/', '/s/.../') AS cs_uri_stem
	,users
from (
	-- For each minute interval, show the total time taken each significant request type (cs_uri_stem)
	SELECT DISTINCT 
		log_time
		,cs_uri_stem
		,sum(c_requesttime)/1000/1000 AS cum_secs
		,sum(sc_bytes) AS sc_bytes
		,count(*) AS c
		,group_concat(cs_username) AS users
	FROM 
	(
		-- Chop off seconds from requests and filter to only the last hour
		select strftime('%Y-%m-%d %H:%M', log_time) AS log_time, cs_uri_stem, sc_bytes, c_requesttime, cs_username from access_log WHERE log_time > datetime('now', '-6 hours', 'localtime')
	) x
	group by 1, 2
	-- This variant displays minutely. 20s/h is equvalent to 0.33s/m, as per this calculation 
	HAVING cum_secs > (20 / 60*60) * 60
	ORDER BY 1 asc, 3 desc
) y;
:echo Shows high CPU-consuming request types (20s total runtime/h), grouped by minute, for 6h
