-- Print accesses to the Zephyr Test Management plugin
;
create view z_access_log AS 
		select strftime('%Y-%m-%d %H', log_time) AS log_time
		, cs_uri_stem
		, sc_bytes
		, c_requesttime
		, cs_username
		from logline
		-- Derived from 'atl_plugin_descriptor_urlprefixes com.thed.zephyr.je'
		WHERE cs_uri_stem REGEXP '(/secure/admin/ZephyrGeneralConfiguration|/secure/admin/ZephyrLabFeatures|/secure/admin/ViewZephyrExecutionStatuses|/secure/admin/EditZephyrExecutionStatus|/secure/admin/DeleteZephyrExecutionStatus|/secure/admin/ViewZephyrCustomField|/secure/admin/ViewZephyrTestStepStatuses|/secure/admin/ViewZephyrAnalytics|/secure/admin/EditZephyrTestStepStatus|/secure/admin/DeleteZephyrTestStepStatus|/secure/admin/ZephyrLicense|/secure/admin/ZephyrDatacenter|/secure/ExecutionNavigator|/secure/ExecuteTest|/secure/AddExecute|/secure/AddTestsToCycle|/secure/AddToCycle|/secure/RedirectionAction|/secure/AttachFileAction|/secure/ZAttachTemporaryFile|/secure/ZephyrEncKeyLoadAction|/secure/addTestsToCycle|/secure/CopyTestStep|/secure/importTests)'
;
select cs_username, cs_uri_stem, * from z_access_log
;
:echo Zephyr action requests
