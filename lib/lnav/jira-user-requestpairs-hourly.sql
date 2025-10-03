;
create view access_log_trunc AS 
		-- E.g.:
		-- 2018-07-02 06	/login.jsp	1024	101	billy
		-- 2018-07-02 06	/login.jsp	1024	120	billy
		-- 2018-07-02 06	/login.jsp	1024	150	sally
		-- 2018-07-02 06	/login.jsp	1024	160	sally
		-- Chop off seconds from requests and filter to only the last hour
		select strftime('%Y-%m-%d %H', log_time) AS log_time
		, cs_uri_stem
		, sc_bytes
		, c_requesttime AS c_requesttime	-- in microseconds
		, cs_username
		from logline
;
create view buckets AS
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
		,count(*) AS n
	FROM 
	access_log_trunc
	group by 1, 2, 3
	-- Smoosh into groups by date + request + username.
	-- The HAVING clause lets is say 'ignore sally's login.jsp requests if they cumulatively took under 20s to run in an hour
	-- This means:
	-- - hours with no >20s/h requests don't display anything, which is probably good as they're not interesting from a performance perspective.
	-- -  busy hours have lots of rows, which is again good - we can see by row count as well as cum_secs that the hour was busy.
	HAVING cum_secs >20
	ORDER BY 1 asc, 4 desc
;
create view _analysis AS select 
	strftime('%d %H', datetime(log_time || ':00:00')) AS time_bucket
	,cum_secs AS secs
	,round(CAST(cum_secs AS float)/n,2) AS "secs/req"
	,round(CAST(sc_bytes AS float)/1024/1024,2) AS mb
	,round(CAST(sc_bytes AS float)/1024/1024/n,2) AS "mb/req"
	,n
	,cs_username
	,regexp_replace(cs_uri_stem, '/s/.*/_/', '/s/.../') AS cs_uri_stem
	,datetime(log_time || ':00:00') AS log_time
	from buckets;

-- Now add the '%' stats
;
create view analysis AS select
	time_bucket
	,secs
	,"secs/req"
	,round(CAST(secs AS float)/a2.total_secs*100,2) AS "%secs"
	,mb
	,"mb/req"
	,n
	,round(100.0*n/a2.total_n,2) AS "%n"
	,cs_username
	,cs_uri_stem
	,log_time
	FROM _analysis a1 JOIN (
		select time_bucket
		,sum(n) AS total_n
		,sum(secs) AS total_secs
		FROM _analysis GROUP BY time_bucket) a2 
	USING (time_bucket)
	ORDER BY time_bucket asc, "%secs" desc;
;select * from analysis;
:echo Shows high CPU-consuming requests per user (20s total runtime), grouped by hour, for 24h. See views access_log_trunc, buckets and analysis
