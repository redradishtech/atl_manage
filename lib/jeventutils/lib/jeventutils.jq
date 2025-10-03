## jq functions for summarizing JSON log output.

## Rounds a floating point number down to two decimal places
# https://stackoverflow.com/questions/46117049/how-i-can-round-digit-on-the-last-column-to-2-decimal-after-a-dot-using-jq
# round() is available but I can't see how to set the precision. We could do a fancier job of the interval string: https://stackoverflow.com/questions/46282902/format-time-period-with-jq-console-tool
def roundit: .*100.0 + 0.5|floor/100.0;

## Colour definitions.
# From https://stackoverflow.com/questions/57298373/print-colored-raw-output-with-jq-on-terminal
# augmented with role colours ('fail', 'success', 'time', 'date')
# Setting JLOGUTILS_COLOR=false will eliminate all colours, e.g. for monitoring output.
def colours:
 (select(env.JLOGUTILS_COLOR!="false") |
 {
 "black": "\u001b[30m",
 "fail": "\u001b[31m",  # Red
 "red": "\u001b[31m",
 "success": "\u001b[32m", # Green
 "green": "\u001b[32m",
 "yellow": "\u001b[33m",
 "blue": "\u001b[34m",
 "date": "\u001b[34m",
 "magenta": "\u001b[35m",
 "cyan": "\u001b[36m",
 "white": "\u001b[37m",
 "reset": "\u001b[0m",
 "time": "\u001b[33m",  # Yellow
}) //
 {
 "black": "",
 "fail": "",  # Red
 "red": "",
 "success": "", # Green
 "green": "",
 "yellow": "",
 "blue": "",
 "date": "",
 "magenta": "",
 "cyan": "",
 "white": "",
 "reset": "",
 "time": "",  # Yellow
} 
;

def parsetime:
	# Strip milliseconds before parsing because jq doesn't support it. https://github.com/stedolan/jq/issues/1117
	sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;
	# We could also have used:
	#sub("\\.[0-9]+Z$"; "Z") | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime;
	#
	# Note that 'fromdate' and strptime() give different results depending on the current timezone, which is not what we want:
	# ( export TZ=UTC; jq -n '"2021-12-09T06:31:32Z" | fromdate' ); ( unset TZ; jq -n '"2021-12-09T06:31:32Z" | fromdate'; )
	# 1639031492
	# 1639035092
	# 
	# Perhaps this is a jq bug. I have set TZ=UTC in the calling script to avoid this problem.

## Given milliseconds, emits a human-readable string ('..h ..m ..s')
#
# https://stackoverflow.com/questions/46282902/format-time-period-with-jq-console-tool
# input: milliseconds
# output: ignore millisecond remainder
def formattime:
  def f(u): if .>0 then " \(.)" + u else "" end ;
  # emit a stream of the remainders
  def s: foreach (1000,60,60,24,1) as $i ([.,0];
    .[0] as $n
    | ($n/$i | floor) as $m
    | [$m, $n - ($m*$i)];
    if $i == 1 then .[0] else .[1] end);

 [s] as [$ms, $s, $m, $h, $d]
  | {s : " \($s)s",
     m : ($m|f("m")),
     h : ($h|f("h")),
     d : ($d|f("d")) }
  | "\(.d)\(.h)\(.m)\(.s)"[1:] as $val 
  | (colours.yellow + $val +  colours.reset)
;

def summarize_entry($args):
	$args as [$rungroup]
	| ((now - ($rungroup.starttime | parsetime))) as $ago
	# FIXME: print whether the lock is exclusive or inclusive
	| if (.type=="lock") then
			(
			(select(.state=="waiting") | "waiting on (\(.lockfile)) for \($ago*1000|formattime) (pid \(.pid))")
			// (select(.state=="acquired") | "holding \(.lockfile) (\(.locktype)) for \($ago*1000|formattime) after \(.waittime|formattime) wait (pid \(.pid))")
			// (select(.state=="released" and .waittime>1000) | "\(.lockfile) is released (\(.waittime|formattime) wait)") 
			#// (select(.state=="released" and .waittime<=1000) | "held and released") 
			// "\(.id).lock is \(.state)"
			)
	elif (.type=="run") then
			(
			(select(.state=="running") | "running \(.cmd) for \($ago*1000|formattime) (pid \(.pid))")
			// (select(.state=="dead") | "\(colours.fail)failed\(colours.reset) (nonexistent pid \(.pid)) running \(.cmd)" )
			// (select(.state=="finished" and .exitcode==0) | "finished \(colours.green)successfully\(colours.reset), taking \(.runtime|formattime)")
			// (select(.state=="finished" and .exitcode!=0) | "\(colours.fail)failed\(colours.reset) with exitcode \(.exitcode) \($ago*1000|formattime) ago after running for \(.runtime|formattime)")
			// "in state \(.state)"
			)
	elif (.type=="log") then
		((select(.newlines>0) | "\(.newlines) logs generated (grep \(.pid) \(.file))") // "No logs generated") 
	else
		"Unknown item \(.)"
	end
	;

# Given a single line { "log:backup": {.. } }, adds a 'type' field (e.g. type: "log") to each record having a key in "foo:bar" form. This allows us later to find e.g. "all logs".
# Implementation detail: we could get the caller to emit a 'type' field ( {"log:backup": {type:"backup",...},..} ) but that hurts readability when we can just infer it here. We could also have chosen a completely machine-readable, regular format { "entry": { "type": "log", "name": "foo" ...} }, but a) that is ugly to read, b) our irregularly-named keys { "log:foo": {...} } (where 'foo' could be anything) makes generating a merged summary of a bunch of events ('jeventquery' shell function) very simple to implement in singlerun_merge.
def singlerun_addtypes:
	with_entries( (.key|split(":")) as [$type,$id] | if $id then .value.type=$type | .value.id=$id  else . end );

## Given a single line {runid:.., starttime:.., "run:backup": {...} }, as found in a jeventlog file, emits a string summary. This can be used to summarize the most recent run output.
# active_summary is used in $ATL_MANAGE/monitoring/nagiosify, and also in the jevents bash function in jeventutils.sh
def singlerun_merge:
	reduce .[] as $item({}; . * $item)
	;

# Given .log.json contents, prints pids that ought to be live, i.e. running processes or processes holding/waiting on locks. The caller can then check these pids for liveness
def active_pids:
	group_by(.runid)	# Split into 'rungroup' arrays, where each array contains records with identical .runid (pid). There should be only one each if the process is complete (jeventlog would roll them up).
	| map( singlerun_merge ) # Reduce our runid array into a single record
	| .[]				# Split into identical-runid entries
	| singlerun_addtypes
	| .runid as $runid
	| del(.starttime, .runid)
	# E.g. {"lock:app":{"type":"lock",..}, "run:rsnapshot":{"type":"run","runid":1234, ..} }
	# Note: we're not in an array. Now select() to only consider unfinished or locked (usually) runs
	# Note: map() works on values ( {"type":"lock",..}, then {"type":"run","runid",1234,..} ). This yields an array of true or falses 
	# FIXME: If we are fed unexpected input e.g. {foo:1}, missing a 'type' attribute, then we break here with a cryptic error.
	| select( 
	(map(.type=="run" and .state!="finished") | any)	# We're interested in rungroups with any unfinished runs..
	// (map(.type=="lock" and .state!="released") | any)	# .. or with unreleased locks
		)
	| .[] 			# Split our rungroup into entries..
	| select(.type=="run" or .type=="lock")	# Find the 'run' entry (that is unfinished) or 'lock' entry (that is waiting or held)
	| .pid    # pid of the running/blocked/holding process
	;

# Given .log.json contents, prints pids of unfinished runs. The caller can then check these pids for liveness
def active_locks:
	group_by(.runid)	# Split into 'rungroup' arrays, where each array contains records with identical .runid (pid). There should be only one each if the process is complete (jeventlog would roll them up).
	| map( singlerun_merge ) # Reduce our runid array into a single record
	| .[]				# Split into identical-runid entries
	| singlerun_addtypes
	| .runid as $runid
	| del(.starttime, .runid)
	# E.g. {"lock:app":{"type":"lock",..}, "run:rsnapshot":{"type":"run","runid":1234, ..} }
	# Note: we're not in an array. Now select() to only consider unfinished or locked (usually) runs
	# Note: map() works on values ( {"type":"lock",..}, then {"type":"run","runid",1234,..} ). This yields an array of true or falses 
	# FIXME: If we are fed unexpected input e.g. {foo:1}, missing a 'type' attribute, then we break here with a cryptic error.
	| select( 

	(map(.type=="lock" and .state!="released") | any)	# We're interested in rungroups with any unfinished runs..
		)
	| .[] 			# Split our rungroup into entries..
	| select(.type=="lock")	# Find the 'run' entry (that is unfinished)
	| [.id, .lockfile, .pid] | @tsv 		
	;

# Given .log.json contents, prints a summary line for the last 5 runs, and also any earlier runs that didn't finish
def active_summary:
	(env.JLOGUTILS_RELATIVE_RUNS_TO_SHOW|tonumber? // 5) as $recent_runs_to_show		# Summarize at least this many recent runs
	| (env.JLOGUTILS_HOURS_DEAD_RUNS_ARE_SHOWN_FOR|tonumber? // 24) as $hours_dead_runs_are_shown_for	# Don't show terminated runs unless were terminated within the past X hours|
	| (env.JLOGUTILS_HOURS_TO_RELATIVIZE_DATES_FOR|tonumber? // 24) as $hours_to_relativize_dates_for	# Show a relative ("Hh Mm Ss ago") time along the timestamp if the run happened in the past X hours
	| group_by(.runid)		# Split into 'rungroup' arrays, where each array contains records with identical .runid (pid). There should be only one each if the process is complete (jeventlog would roll them up).
	| map( singlerun_merge ) 	# Reduce our runid array into a single record
	| sort_by(.starttime)		# Sort by run start time, most recent last
	| reverse			#.. most recent first
	| (.[0:$recent_runs_to_show] | map(.runid))	as $lastruns	# Identify runids for the last N runs.
	| .[]				# Consider each rungroup..
	| .		as $rungroup
	| .runid	as $runid
	| ((now - (.starttime | parsetime))) as $ago
	| singlerun_addtypes
	| del(.starttime, .runid)
	| ((..|select(.type?=="run" and .state=="running")) |= ($pidstatus."\(.pid)" as $realstate | .state=$realstate)) # For Update "running" entries, setting state to the real pid state (passed in as the $pidstatus arg)
	#| ((..|select(.type?=="lock" and .state=="acquired")) |= (.state = ($lockstatus."\(.id)" // .state)))
	| ((..|select(.type?=="lock" and .state=="acquired")) |= ($lockstatus."\(.id)" as $newstatus | .state=("held by \($newstatus.lockingpidstatus) pid \($newstatus.lockingpid)" // .state)) )
	# E.g. {"lock:app":{"type":"lock",..}, "run:rsnapshot":{"type":"run","runid":1234, ..} }
	# Note: we're not in an array. Now select() to only consider unfinished or locked (usually) runs
	# Note: map() works on values ( {"type":"lock",..}, then {"type":"run","runid",1234,..} ). This yields an array of true or falses 
	# FIXME: If we are fed unexpected input e.g. {foo:1}, missing a 'type' attribute, then we break here with a cryptic error.
	| select( 
	(map( .type=="run" and .state=="running") | any)	# We're interested in rungroups with any unfinished runs..
	// (map( .type=="run" and .state=="dead" and $ago<$hours_dead_runs_are_shown_for*60*60) | any)	# We're interested in rungroups with any unfinished runs..
	// select (map(.type!="run") | all)			# ..and rungroups whose entries are all not runs (locks, etc)
	// select ($lastruns | index($runid))			# ..and the most recent rungroups. Happily, if the last rungroup is *also* one
								# unfinished, or a lock, then this whole condition matches once, not twice, for its line
		)
	#| select ( map(.type=="run" and .state!="finished") | any)	# Pick lines with any unfinished runs..
	#	// select ( map(.type!="run") | all)			# ..and lines whose entries are all not runs (locks, etc)
	| map_values( . + {summary: summarize_entry([$rungroup]) })
	# If $ago suggests we're operating on just-generated logs, omit the "Starting" part
	#| $runid +(if $ago>5 then "Started \($ago*1000|formattime) ago, " else "" end) +
	| ((now - ($rungroup.starttime | parsetime))) as $ago
	| colours.date + ($rungroup.starttime | parsetime | strftime("[%d/%b %H:%M UTC]")) + colours.reset
	+ (if  $ago<($hours_to_relativize_dates_for*60*60) then " (\($ago*1000|formattime) ago) " else "" end)
	+ " " +([
			 ([.[] | select(.type=="run")|"\(.id) \(.summary)" ] | join(", and "))
			,([.[] | select(.type=="log")|"\(.summary)" ] | join(", and "))
			,([.[] |select(.type=="lock")|"\(.summary)"] | join(", and ")  )
	] 
	| [.[]|select(.!="")]    # If we have no logs, or no logs, we'll have a "" in our array. Eliminate that to avoid ". ." in our output.
	| join(". ")
	)
;

## Generate summary stats from all the 'run' records in a jeventlog file. 'run' records are where real work occurs (vs. waiting for locks)
# This is an intermediate, output-agnostic form intended to be passed to finishedruns_summary
def finishedruns:
	# https://stackoverflow.com/questions/48321235/sql-style-group-by-aggregate-functions-in-jq-count-sum-and-etc
	100 as $samplesize
	| ([.[] | to_entries[] | select( (.key|startswith("run:")) and (.value.state=="finished") )]) as $allruns	# Find our 'run' nodes
	| $allruns[0:$samplesize] as $lastruns
	| ($lastruns | group_by(.key, .value.cmd) | map(
					{
					key: .[0].key
					, cmd: .[0].value.cmd
					, count:length
					, successcount: ( [map(.value.exitcode)[]|select(.==0)]|length )
					, runtime: {
						 min: map(.value.runtime) | del(.[]|nulls) | min
						 , avg: map(.value.runtime) | del(.[]|nulls) | (if (length>0) then (add/length) else null end)   # Handle zero runs without exploding
						 , max: map(.value.runtime) | del(.[]|nulls) | max
						 ,alll: map(.value.runtime) | del(.[]|nulls)
					 }
					} 
					)) as $finishedruns
	| {$finishedruns} + {firstrun: $allruns[0].starttime, lastrun: $allruns[-1].starttime};

#Used in jevents in jeventutils.sh
def finishedruns_summary:
        "\t" + ([.finishedruns[] | "\(.key) (\(.cmd)) \(colours.green)succeeded\(colours.reset) for \(.successcount)/\(.count) of most recent runs, taking \(colours.yellow)\(.runtime.avg|formattime)\(colours.reset) on average (max \(.runtime.max|formattime), min \(.runtime.min|formattime))"] | join("\n\t"));
	#"\t" + ([.finishedruns[] | "\(.key) (\(.cmd)) \(colours.green)succeeded\(colours.reset) for \(.successcount)/\(.count) of most recent runs, taking \(colours.yellow)\(.runtime.avg|formattime)\(colours.reset) on average (max \(.runtime.max|formattime), min \(.runtime.min|formattime))"] | join("\n\t"));
# vim: set foldmethod=marker:
