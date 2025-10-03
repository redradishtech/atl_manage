;
select log_time, rt, cs_username, sc_bytes from logline where cs_uri_stem like '%1.0/_/download/batch/jira.webresources:global-static/jira.webresources:global-static.css' and sc_status=200;
:echo Show successful global-static-css requests, a suspected performance killer. Good for histograms and spectrograms.
