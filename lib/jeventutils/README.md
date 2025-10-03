Teach your slow-running bash scripts to emit a JSON log stream recording metadata about command run times, lock wait times, and logs generated! Then aggregate the JSON data across multiple runs to see average run times.

## Motivation


Say you have a backup script triggered from cron:

```
0 * * * * root flock /var/lock/mybackup.lock /usr/local/bin/mybackup.sh &| ts >> /var/log/mybackup.log
```

The flock prevents overlapping runs, and stdout/stderr is captured (with timestamps added by `ts` from the `moreutils` package). It could be improved but is a fair attempt.

Having set up a cron entry like this, I always find myself with questions later:

- *Run history* - Has my script been running at all? When last did it run? How long on average is taking to run?
- *Current status* - Is my script currently running? If so, how long has it been running for? It is waiting on the lockfile, or doing actual work?

jeventutils is a set of wrapper scripts that answer these questions. The idea is that as well as stdout (fd1) and stderr (fd2), there should be a JSON event log on fd3. This JSON event log can later be queried to figure out when scripts ran and what they did.


## Command Overview

### jrun

`jrun` is a command wrapper that emits JSON recording pid, runtime and exit code on fd3:

`jrun testcommand sleep 1 3>&1`
```json
{"run:testcommand":{"state":"running","pid":5794,"cmd":"'sleep 1'"}}
{"run:testcommand":{"runtime":1003,"state":"finished","exitcode":0,"cmd":"'sleep 1'"}}
```

### jlog

`jlog` appends stdout/stderr of the nested command to a log file. Each line is tagged with timestamp and pid:

`jlog testcommand ls -l /etc/pass* 3>&1`
```json
{"log:testcommand":{"file":"/tmp/logdir/testcommand.log","pid":9546}}
{"log:testcommand":{"file":"/tmp/logdir/testcommand.log","newlines":318,"pid":9546}}
```
and `/tmp/logdir/testcommand.log` contains the `ls` output, 

```
ts=2021-12-09T13:05:58+1100 pid=331602 -rw-r--r-- 1 root root 5098 Oct  9 13:58 /etc/passwd
ts=2021-12-09T13:05:58+1100 pid=331602 -rw-r--r-- 1 root root 4957 Oct  9 13:58 /etc/passwd-
```

### jwritelock, jreadlock

'jwritelock' obtains an exclusive lock, and `jreadlock` a shared lock, before running the nested command.

```bash
jwritelock mylock sleep 1 3>&1
```
```json
{"lock:mylock":{"state":"waiting","pid":45268,"lockfile":"/tmp/logdir/mylock.lock","locktype":"exclusive"}}
{"lock:mylock":{"state":"acquired","pid":45268,"lockfile":"/tmp/logdir/mylock.lock","waittime":3,"locktype":"exclusive"}}
{"lock:mylock":{"state":"released","holdtime":1007,"lockfile":"/tmp/logdir/mylock.lock","waittime":3,"locktype":"exclusive"}}
```

Here 'holdtime' and 'waittime' are in milliseconds.

### jeventlog

`jeventlog` appends JSON log messages (emitted by `jrun`, `jlog` and `jreadlock`/`jwritelock`) to a log file, or to stdout. Typically you would chain the above  commands together, then redirect fd 3 to jeventlog's stdin; for instance:

`jwritelock pingtest \
	jlog pingtest \
	jrun pingtest ping -c1 1.1.1.1 \
	3> >(jeventlog pingtest)`

`cat $JLOGDIR/pingtest.log.json`
```json
{"runid":"289278","starttime":"2020-06-23T10:42:15Z","lock:pingtest":{"state":"waiting","pid":289276,"lockfile":"/tmp/logdir/pingtest.lock","locktype":"exclusive"}}
{"runid":"289278","starttime":"2020-06-23T10:42:15Z","lock:pingtest":{"state":"acquired","pid":289276,"lockfile":"/tmp/logdir/pingtest.lock","waittime":2,"locktype":"exclusive"}}
{"runid":"289278","starttime":"2020-06-23T10:42:15Z","log:pingtest":{"file":"/tmp/logdir/pingtest.log","pid":289276}}
{"runid":"289278","starttime":"2020-06-23T10:42:15Z","run:pingtest":{"state":"running","pid":289307,"cmd":"'ping -c1 1.1.1.1'"}}
{"runid":"289278","starttime":"2020-06-23T10:42:15Z","run:pingtest":{"runtime":204,"state":"finished","exitcode":0,"cmd":"'ping -c1 1.1.1.1'"}}
{"runid":"289278","starttime":"2020-06-23T10:42:15Z","log:pingtest":{"file":"/tmp/logdir/pingtest.log","newlines":6,"pid":289276}}
{"runid":"289278","starttime":"2020-06-23T10:42:15Z","lock:pingtest":{"state":"released","holdtime":228,"lockfile":"/tmp/logdir/pingtest.lock","waittime":2,"locktype":"exclusive"}}
```

`jeventlog` adds the `runid` and `starttime` attributes, allowing the JSON lines from disparate commands to be tied together later.

### jevents

`jevents` takes output from `jeventlog` and produces a human-readable report.

`jevents pingtest`

```bash
[23/Jun 20:42] (4s ago)  pingtest finished successfully, taking 0s. 6 logs generated (grep 289276 /tmp/logdir/pingtest.log). pingtest.lock is released
```

`jevents` prints a summary of the last 5 runs, most to least recent. Adding a '-s' flag prints stats across all runs.

E.g. if we run our ping test 10 times:

```bash
for i in {1..10}; do jwritelock pingtest jlog pingtest jrun pingtest ping -c1 1.1.1.1 3> >(jeventlog pingtest) & done
```
`jevents -s pingtest` gives:
```bash
[23/Jun 20:44] (25s ago)  pingtest finished successfully, taking 0s. 6 logs generated (grep 299367 /tmp/logdir/pingtest.log). pingtest.lock is released
[23/Jun 20:44] (25s ago)  pingtest finished successfully, taking 0s. 6 logs generated (grep 299357 /tmp/logdir/pingtest.log). pingtest.lock is released (1s wait)
[23/Jun 20:44] (25s ago)  pingtest finished successfully, taking 0s. 6 logs generated (grep 299370 /tmp/logdir/pingtest.log). pingtest.lock is released
[23/Jun 20:44] (25s ago)  pingtest finished successfully, taking 0s. 6 logs generated (grep 299366 /tmp/logdir/pingtest.log). pingtest.lock is released
[23/Jun 20:44] (25s ago)  pingtest finished successfully, taking 0s. 6 logs generated (grep 299372 /tmp/logdir/pingtest.log). pingtest.lock is released (1s wait)
Stats:
        run:pingtest ('ping -c1 1.1.1.1') succeeded for 10/10 of most recent runs, taking 0s on average (max 0s, min 0s)
```

`jeventlog` and `jevents` may be chained to avoid the intermediate `.log.json` file, e.g.:

```bash
for i in {1..20}; do jrun _ sleep 1 & done 3> >(jeventlog | jevents -s)
```

```bash
[23/Jun 20:51] (2s ago)  _ finished successfully, taking 1s
Stats:
        run:_ ('sleep 1') succeeded for 20/20 of most recent runs, taking 1s on average (max 1s, min 1s)
```

### jeventquery

Runs a jq query on JSON logs.

For example, given JSON from 10 ping runs:

```bash
for i in {1..10}; do jwritelock pingtest jlog pingtest jrun pingtest ping -c1 1.1.1.1 3> >(jeventlog pingtest) & done
```

```bash
jeventquery pingtest 'length'		# 10
jeventquery pingtest '.[0]'		# Print most recent ping's JSON
```
```json
{
  "runid": "408597",
  "starttime": "2020-06-25T06:13:21Z",
  "lock:pingtest": {
    "state": "released",
    "pid": 408564,
    "lockfile": "/tmp/logdir/pingtest.lock",
    "locktype": "exclusive",
    "waittime": 419,
    "holdtime": 51,
    "type": "lock",
    "id": "pingtest"
  },
  "log:pingtest": {
    "file": "/tmp/logdir/pingtest.log",
    "pid": 408564,
    "newlines": 6,
    "type": "log",
    "id": "pingtest"
  },
  "run:pingtest": {
    "state": "finished",
    "pid": 408959,
    "cmd": "'ping -c1 1.1.1.1'",
    "runtime": 17,
    "exitcode": 0,
    "type": "run",
    "id": "pingtest"
  }
}
```
```bash
jeventquery pingtest 'map(..|select(.type?=="run" and .state?=="finished") | .runtime) | {avg: (add / length), min: min, max: max, count: length}'    # Ping runtime stats
```
```json
{
  "avg": 20,
  "min": 14,
  "max": 52,
  "count": 10
}
```

### jeventsummaryscript

`jeventsummaryscript` accepts event JSON and invokes an external script with the exit code and run status summary. This can be used to notify monitoring systems like Nagios/Icinga/Zabbix/healthchecks.io.



For example, in Nagios/Icinga one might have `/etc/nagios/conf.d/letsencrypt_renew.cfg`:

```
service_description             Renew cert
use                             passive-service
host                            issues.redradishtech.com
freshness_threshold             86400
register                        1
}
```

The 'nsga-ng-client' package has a `/usr/share/doc/nsca-ng-client/examples/invoke_check` script that will inform a passive Nagios service of a result:

```
invoke_check issues.redradishtech.com 'Renew cert' 0 'Cert renewed'
```

Our crontab can call that script, substitituting in the correct exit code and summary output text::

```
0 1 * * *       root    JLOGDIR=/tmp; JLOCKDIR=/tmp; jwritelock issues_letsencrypt jlog issues_letsencrypt jrun issues_letsencrypt certbot certonly -d issues.redradishtech.com --dns-cloudflare --dns-cloudflare-credentials /etc/secrets/cloudflare.ini 3> >(jeventlog | jeventsummaryscript invoke_check "issues.redradishtech.com" "renew cert" @EXITCODE@ "@SUMMARY@")
```

Now your monitoring system will notify you if this cron script ever fails, or even just fails to run. 

## Installation

1. Install `jq`

Install jq 1.6 or higher via your package manager.

1. Get the source:

```bash
cd /opt
git clone https://github.com/redradishtech/jeventutils
```

2. Fetch and build the `jo` JSON utility. Note, we need this 1.3 version from github, _not_ the older version available via Debian package.


```bash
# Fetch and build 'jo'
git submodule init
git submodule update
cd lib/jo
autoreconf -i
./configure
make
cd ../..
```

3. If you are writing a bash script, source `jeventutils.sh` at the top:

```
#!/bin/bash

# JLOCKDIR=/tmp
# JLOGDIR=/tmp
. /opt/jeventutils/lib/jeventutils.sh

main() {
        echo "Hello there, ${1:-world}"
}

jwritelock myscript \
        jlog myscript \
        jrun myscript \
        main "$@" \
        3> >(jeventlog myscript)
```

You can set JLOGDIR before sourcing jeventutils.sh to specify where logs should go. The default is `$XDG_CACHE_HOME` if set, `$HOME/.cache` if `$HOME` is set, or `/var/cache` otherwise.

Likewise specify JLOCKDIR to specify where lockfiles are made. The default is `$XDG_RUNTIME_DIR` if set (e.g. `/run/user/$UID`), `/var/lock` otherwise.


The scripts also have wrappers in `jeventutils/bin`. These are useful for crontab entries

 to your PATH.

```bash
export PATH=/opt/jeventutils/bin:$PATH
```

== Systemd Comparison

Returning to our original example of a cronned backup:

```
0 * * * * root flock /var/lock/mybackup.lock /usr/local/bin/mybackup.sh | ts >> /var/log/mybackup.log
```

= Future Development

It should be possible to replace jrun with systemd-run:

systemd-run --unit backup --pipe rsnapshot

This will kick off backup.service, automatically locking so another instance can't run. Timing info is available after the run as properties.

Investigate using https://github.com/itchyny/gojq instead of vanilla go.

## Bugs

Occasionally the JSON log file gets corrupted, e.g.:

```json
{"runid":"26284", "starttime": "2022-08-16T09:40:01.145Z", "lock:replication_filesystem_sync":{"lockfile":"/opt/atlassian/confluence/current/temp/replication_filesystem_sync.lock","locktype":"exclusive","state":"waiting","pid":26279}}
{"runid":"30933", "starttime": "2022-08-16T09:45:01.650Z", {"runid":"8629", "starttime": "2022-08-16T09:55:16.911Z", "lock:replication_filesystem_sync":{"lockfile":"/opt/atlassian/confluence/current/temp/replication_filesystem_sync.lock","locktype":"exclusive","state":"waiting","pid":8621}}
{"runid":"28007", "starttime": "2022-08-16T10:15:17.509Z", "lock:replication_filesystem_sync":{"lockfile":"/opt/atlassian/confluence/current/temp/replication_filesystem_sync.lock","locktype":"exclusive","state":"waiting","pid":27995}}
```

## TODO

We need an equivalent of the ( flock --exclusive 200; .... ) 200>/path/to/lock pattern

