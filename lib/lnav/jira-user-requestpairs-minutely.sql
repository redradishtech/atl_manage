;
select 
	strftime('%H:%M', datetime(log_time || ':00')) AS time_bucket
	,round(cum_secs,2) AS cumulative_secs
	,round(sc_bytes/1024/1024,2) AS cumulative_mb
	,c AS "count"
	, cs_username
	,regexp_replace(cs_uri_stem, '/s/.*/_/', '/s/.../') AS cs_uri_stem
from (
	-- For each minute interval, show the total time taken each significant request type (cs_uri_stem)
	-- E.g.:
	-- 2018-07-02 06	/login.jsp	billy	2048	221	2
	-- 2018-07-02 06	/login.jsp	sally	2048	155	2
	SELECT DISTINCT 
		log_time
		,cs_uri_stem
		,cs_username
		,sum(c_requesttime)/1000/1000 AS cum_secs
		,sum(sc_bytes) AS sc_bytes
		,count(*) AS c
	FROM 
	(
		-- E.g.:
		-- 2018-07-02 06	/login.jsp	1024	101	billy
		-- 2018-07-02 06	/login.jsp	1024	120	billy
		-- 2018-07-02 06	/login.jsp	1024	150	sally
		-- 2018-07-02 06	/login.jsp	1024	160	sally
		-- Chop off seconds from requests and filter to only the last hour
		select strftime('%Y-%m-%d %H:%M', log_time) AS log_time, cs_uri_stem, sc_bytes, rt, cs_username from logline WHERE log_time > datetime('now', '-6 hours', 'localtime')
	) x
	group by 1, 2, 3
	-- Smoosh into groups by date + request + username.
	-- The HAVING clause lets is say 'ignore sally's login.jsp requests if they cumulatively took under 20s to run in an hour
	-- This means:
	-- - hours with no >20s/h requests don't display anything, which is probably good as they're not interesting from a performance perspective.
	-- -  busy hours have lots of rows, which is again good - we can see by row count as well as cum_secs that the hour was busy.
	-- This variant displays minutely. 20s/h is equvalent to 0.33s/m, as per this calculation 
	HAVING cum_secs > (80 / 60*60) * 60
	ORDER BY 1 asc, 4 desc
) y
:echo Shows high CPU-consuming requests per user (20s total runtime/h), grouped by minute, for 6h
