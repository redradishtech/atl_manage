;select log_time, rt, cs_username, sc_bytes, cs_uri_query from logline where cs_uri_stem like '/rest/greenhopper/1.0/xboard/work/allData.json' and sc_status=200;
:echo Show successful allData.json requests. AllData.json is a suspected performance killer. Good for histograms and spectrograms.
