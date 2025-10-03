'Plugins' here are just bash scripts, parsed in three phases:
 - The first parse learns of available functions, their args, comments and @tags. This will later be used to generate help
 - The second parse processes the header comment, reading the ini-style parameters, which are converted into variables of the form $_pluginkey__variablename
 - The script is sourced, instantiating the functions


The primary task of a 'plugin' is to define new functions, which will then become symlink aliases. For instance, the systemd plugin defines `install`, `uninstall`, `start`, `stop` etc.

# Variables accessible to plugins

Multitool scripts are configured in the bash comment header, ini-style. For example, the systemd.bash plugin defines some default settings:

```
# [Service]
# _Type = root
# _Name = ${_script__name}
# Type = simple
# WorkingDirectory=${_script__basedir}
#
# [Timer]
# OnCalendar =
# Persistent = true
```

which your script may then activate (by using the `[Service]` or `[Timer]` header) and augment:

```
# [Service]
#
# [Timer]
# OnCalendar="*-*-* 00:25:00"
```

When the plugin is finally sourced, it will find the following variables declared:

```bash
$_service___type=root
$_service___name="My Backup Service"
$_service__type=simple
$_service__workingdirectory=/path/to/backup-script
$_timer__oncalendar="*-*-* 00:25:00"
$_timer__persistent=true
```

Your script may use them, but also set new variables.


This results in a variable, 


# Plugin ordering

Say we have:

# @main
backup() { ... }

healthchecks.bash defines:

healthcheck_start() { ...}

and programmatically tags it:

# @pre:backup
healthcheck_start() { ...}

by setting $_tag_

sudo.bash has:

# @pre!:*
_run_in_sudo() {
