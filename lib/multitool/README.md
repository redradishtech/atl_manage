# multitool.bash


`multitool.bash` is a mini framework for writing production-worthy bash scripts (primarily backing up servers), focusing on a few main ideas:

 - Write one script, containing (related) functions, that 'unpacks' into many symlinks, one for each function (hence the 'multitool' analogy), so each function can be individually invoked.
 - Auto-generated help, based on comments in the script.
 - Use decorator-like @tags on functions, E.g. @sudo to indicate a function runs as root.
 - Plugins that provide project-specific wrappers of other commands.

There is also:
 - systemd support -- turn your script into a service
 - https://healthchecks.io support -- get alerts if your service fails to run
 - local dependencies, courtesy of NixOS via [Devbox](https://github.com/jetify-com/devbox/) -- specify the exact version of external binaries you need, independent of what's on the host OS
 - restic backup support
 - rclone support
 - restic-with-a-rclone-backend support

# Motivation

Have you ever found yourself writing sets of related scripts, and needing to source a `common.sh` file for common variables?
Have you ever wanted to run 'sudo' on a whole bash function, because it needs to run as root? 

# Functionality walkthrough

## Auto-generated help

Let's start with a simple bash script, we'll call `script.sh`.

To make it use multitool, just source `multitool.bash` at the end:

```bash
#!/bin/bash -eu

# Our amazing function
hello() {
	echo "Hello world!"
}

. ../multitool.bash
```
Now, running the script prints usage:

```
$ ./script.sh 
Usage: script.sh COMMAND
Where COMMAND is:
  hello                #  Our amazing function                                                  [script.sh]
  help                 #  Print help                                                            [script.sh]

Run './help --plugins' to see functions made available by plugins
```

Let's add an overall description:

```bash
#!/bin/bash -eu
# [Script]
# Description = Demonstrates a multitool script

# Our amazing function
hello() {
	echo "Hello world!"
}

. ../multitool.bash
```

Output:
```
$ ./script.sh 
Description: Demonstrates a multitool script
Commands
  hello                #  Our amazing function                                                  [script.sh]
  help                 #  Print help                                                            [script.sh]

Run './help --plugins' to see functions made available by plugins
```

## Auto-generated symlinks

Running `script.sh` has the side-effect of creating 'hello' and 'help' symlinks:

```
$ ls -la
total 31
drwxrwxr-x+ 2 root    sudo        6 Jul 19 15:14 .
drwxrwxr-x+ 5 root    sudo       10 Jul 19 15:14 ..
lrwxrwxrwx  1 jturner jturner    11 Jul 19 15:09 hello -> ./script.sh
lrwxrwxrwx  1 root    sudo       11 Jul 19 12:07 help -> ./script.sh
-rwxrwxr-x+ 1 root    sudo       92 Jul 19 15:14 script.sh
```

Running `./hello` runs the `hello` function. So does `./script.sh hello`.

Each time you add, remove or rename a function, symlinks will be updated.

You can tag a function as `@main` to indicate it should run by default if `script.sh` is invoked:


```bash
#!/bin/bash -eu
# [Script]
# Description = Demonstrates a multitool script

# Our amazing function
# @main
hello() {
	echo "Hello world!"
}

. ../multitool.bash
```
Output:

```
$ ./script.sh 
Hello world!
```

### @sudo tag

Let's add another function, `helloroot`, and have it run as root:

```bash
#!/bin/bash -eu
# [Script]
# Description = Demonstrates a multitool script

# Our amazing function
# @main
hello() {
	echo "Hello world!"
}

# A function that runs as root
# @sudo
helloroot() {
	echo "Hello root! We are EUID $EUID"
}

. ../multitool.bash
```

On the next run, the 'helloroot' symlink is created, and the `helloroot` command automatically runs as sudo:

```bash
$ ./script.sh 
Creating symlink: helloroot
Hello world!
$ ls
hello  helloroot  help  script.sh
$ ./helloroot 
Hello root! We are EUID 0
```

## ProductionHost / AuxiliaryHost

Some scripts are intended only to be run on a particular host. E.g. a script that backs up a server to a remote location must only be run on the production server. 

Let's require that our script can only run on host `prod102`:

```bash
#!/bin/bash -eu
# [Script]
# Description = Demonstrates a multitool script
# ProductionHost = prod102
#
# Our amazing function
# @main
hello() {
	echo "Hello world!"
}

# A function that runs as root
# @sudo
helloroot() {
	echo "Hello root! We are EUID $EUID"
}

. ../multitool.bash
```
Now I get:

```
$ ./script.sh 
Script is expected to run on 'prod102' (ProductionHost), not 'jturner-desktop'. Perhaps add 'jturner-desktop' as an AuxiliaryHost?
```

In addition to `ProductionHost` there is `AuxiliaryHost`, which specifies servers that functions _other than the @main function_ can be run on. E.g. your @main-tagged function might back up the server, but there may be other functions, e.g. to check a backup's integrity or restore a backup, that can be invoked off the production host.

`ProductionHost` and `AuxiliaryHost` are regexes, so multiple values can be allowed, e.g. `ProductionHost = (prod102|prod103)`.

## Restic plugin

Let's create a more realistic script, illustrating what I primarily need it for: backing up servers. My preferred backup system is currently [Restic](https://restic.net/) backing up to a Cloudflare R2 bucket. Restic can't talk to R2 natively, so it uses [RClone](https://rclone.org/)'s [restic backend](https://rclone.org/commands/rclone_serve_restic/).

Multitool has 'plugins', which are thin wrappers around native functions like `restic` and `rclone`. To see available plugins, run `./help --plugins` (or `./multitool.bash help --plugins` if you don't yet have a script):

```
Plugins:

RClone - Adds ./rclone wrapper, set up for this project.
  [rclone]
    RCLONE_CONFIG_PASS   sets a password (default: none)
    RCLONE_CONFIG        sets the rclone.conf location (default: ${_script__basedir}/rclone.conf)
  rclone               #  Invokes rclone with RCLONE_CONFIG and RCLONE_CONFIG_PASS set as specified [rclone]

IsProduction - Restricts scripts to run on [Script] ProductionHost/AuxiliaryHost, if specified. Any function may be run on ProductionHost. Functions not tagged @main may be run on AuxiliaryHost.
  [script]
    AuxiliaryHost        regex matching $HOSTNAME of hosts that non-@main functions are allowed to run on. (default: none)
    ProductionHost       regex matching $HOSTNAME of hosts the script should normally run on. (default: none)

Restic - Enable restic, defaulting to ./restic_repo.
  [restic]
    RESTIC_PASSWORD      sets the Restic password (required) (default: none)
    RESTIC_REPOSITORY    sets the repo location (default: "${_script__basedir}/restic_repo")
  restic               #  Invokes restic with RESTIC_PASSWORD and RESTIC_REPOSITORY set as specified. [restic]
  restic-init          #  Invokes 'restic init --repository-version 2'                          [restic]

Restic RClone Backend - RClone backend for Restic
  [restic_rclone_backend]
    RESTIC_REPOSITORY    URL to rclone backend. E.g. rest:http://... or unix:///path/to/socket (default: rest:http://${_restic_rclone_backend__address})
    Address              Set the port the RClone restic backend listens for connections on. IPaddress:Port, :Port or [unix://]/path/to/socket to bind server to (default [127.0.0.1:8999]) (default: localhost:8999)
    Servicename          Name of the systemd service to run rclone backend in. Not normally needed. (default: ${_script__name}-rclone-backend)
  rclone_backend_listening  #                                                                        [restic_rclone_backend]
  rclone_backend_start  #  Starts 'rclone serve restic' in the background, serving the Restic API at  [restic_rclone_backend]
  rclone_backend_stop  #                                                                        [restic_rclone_backend]
  rclone_backend_waitfor  #                                                                        [restic_rclone_backend]
  rclone_backend_status  #                                                                        [restic_rclone_backend]

Systemd - Turns your script into a systemd service
  [unit]
    Description          systemd service description (default: ${_script__description})
  [timer]
    OnCalendar           If set, a systemd timer is installed (default: none)
  [service]
    _Name                Systemd service name (default: ${_script__name})
    _Type                Whether the systemd service should run as current user ('user') or 'root' (default: root)
  restart              #  Restart the  systemd service                                          [systemd]
  stop                 #  Stop the  systemd service                                             [systemd]
  journalctl           #  Run journalctl or journalctl --user as appropriate, with --user param preset [systemd]
  systemd-run          #  Run systemd-run or systemd-run --user as appropriate                  [systemd]
  logs                 #  Follow the systemd service logs (systemctl -fu )                      [systemd]
  install              #  Install .service Systemd service                                      [systemd]
  start                #  Start the  systemd service                                            [systemd]
  systemctl            #  Run systemctl or systemctl --user as appropriate                      [systemd]
  uninstall            #  Uninstall  systemd service.                                           [systemd]
  status               #  Prints status of the  systemd service                                 [systemd]

Healthchecks - Notifies https://healthchecks.io of the start and end of the @main-tagged function. For more fine-grained control, tag a function @healthchecks:manual, and in the function call _healthcheck_start / _healthcheck_end.
  [healthchecks]
    APIKey               Set the Healthchecks.io project API key (visible under Settings), allowing us to register our own endpoint. Note: APIKey may be stored in cross-project ~/.config/multitool/defaultheader.bash (default: none)
    URL                  Sets the Healthcheck URL, e.g. https://hc-ping.com/<uuid>. See https://healthchecks.io/docs/ (default: none)
  healthcheck_register  #  Registers a healthchecks.io Check for this script. Requires [Healthchecks] APIKey to be set" [healthchecks]
```

`--plugins` shows help for every plugin installed (in multitool's `multitool.d/` directory). Get help about a particular plugin with `--plugin=<plugin>`, e.g.:

```
$ ./backup.sh help --plugin=restic
Plugins:

Restic - Enable restic, defaulting to ./restic_repo.
  [restic]
    RESTIC_PASSWORD      sets the Restic password (required) (default: none)
    RESTIC_REPOSITORY    sets the repo location (default: "${_script__basedir}/restic_repo")
  restic               #  Invokes restic with RESTIC_PASSWORD and RESTIC_REPOSITORY set as specified. [restic]
  restic-init          #  Invokes 'restic init --repository-version 2'                          [restic]
```
To enable a plugin, just define the header in your script. Here it's `# [Restic]` (capitalization doesn't matter). Here is a minimal Restic-using script that provides `backup`, `lsbackup` and `restore` commands:

```bash
#!/bin/bash -eu
# [Script]
# Name = backup-etc
#
# [Restic]
# RESTIC_PASSWORD='hunter2'
# RESTIC_REPOSITORY="/var/backups/my-etc-backup"

# Trigger a backup
# @sudo
backup() {
    dirs=( /etc )
    restic backup --one-file-system --verbose=1 "${dirs[@]}"
}

# Restore files to DIR
# @sudo
restore() {
    (( $# == 1 )) || { echo >&2 "Usage: $0 DIR"; exit 1; }
    local restoredir="$1"
    restic restore latest --target "$restoredir"
}

# Print what is in the latest Restic backup
# @sudo
lsbackup() {
    restic ls latest
}

. ../../multitool.bash
```

The help prints:

```
$ ./backup.sh 
Description: Backup /etc
Usage: backup.sh COMMAND
Where COMMAND is:
  restic               #  Invokes restic with RESTIC_PASSWORD and RESTIC_REPOSITORY set as specified. [restic]
  restic-init          #  Invokes 'restic init --repository-version 2'                          [restic]
  backup               #  Trigger a backup                                                      [backup.sh]
  lsbackup             #  Print what is in the latest Restic backup                             [backup.sh]
  help                 #  Print help                                                            [backup.sh]
  restore              #  Restore files to DIR                                                  [backup.sh]
```
and function symlinks have been created:

```
Run './help --plugins' to see functions made available by plugins
$ ls -la
total 45
drwxrwxr-x+ 2 jturner jturner    10 Jul 19 20:37 .
drwxrwxr-x+ 3 root    sudo       22 Jul 19 20:20 ..
lrwxrwxrwx  1 jturner jturner    11 Jul 19 20:21 backup -> ./backup.sh
-rwxrwxr-x+ 1 jturner root      501 Jul 19 20:37 backup.sh
lrwxrwxrwx  1 jturner jturner    11 Jul 19 20:21 help -> ./backup.sh
lrwxrwxrwx  1 jturner jturner    11 Jul 19 20:21 lsbackup -> ./backup.sh
lrwxrwxrwx  1 jturner jturner    11 Jul 19 20:21 restic -> ./backup.sh
lrwxrwxrwx  1 jturner jturner    11 Jul 19 20:21 restic-init -> ./backup.sh
lrwxrwxrwx  1 jturner jturner    11 Jul 19 20:21 restore -> ./backup.sh
```

We can now create a restic repo:

```bash
$ ./restic-init
Restic running with repo: /var/backups/my-etc-backup
created restic repository 64588f771f at /var/backups/my-etc-backup

Please note that knowledge of your password is required to access
the repository. Losing your password means that your data is
irrecoverably lost.
Restic finished
```

generate a backup:

```bash
$ ./backup
Restic running with repo: /var/backups/my-etc-backup
open repository
repository 4af6e677 opened (version 2, compression level auto)
created new cache in /home/jturner/.cache/restic
found 5 old cache directories in /home/jturner/.cache/restic, run `restic cache --cleanup` to remove them
no parent snapshot found, will read all files
load index files
[0:00]          0 index files loaded
start scan on [/etc]
start backup on [/etc]
scan finished in 0.035s: 2049 files, 46.854 MiB

Files:        2049 new,     0 changed,     0 unmodified
Dirs:          489 new,     0 changed,     0 unmodified
Data Blobs:   1972 new
Tree Blobs:    407 new
Added to the repository: 48.178 MiB (40.824 MiB stored)

processed 2049 files, 46.854 MiB in 0:00
snapshot 82926b36 saved
Restic finished
```

and list the latest backup contents:

```
$ ./lsbackup  | head
Restic running with repo: /var/backups/my-etc-backup
snapshot 82926b36 of [/etc] at 2025-07-19 20:46:41.167362966 +1000 AEST by root@jturner-desktop filtered by []:
/etc
/etc/.etckeeper
/etc/.git
/etc/.gitignore
/etc/.hosts.swp
/etc/.java
/etc/.java/.systemPrefs
/etc/.java/.systemPrefs/.system.lock
...
```

(the `lsbackup` function is equivalent to running `./restic ls latest`)



## RClone plugin

We want to back up to Cloudflare R2, which needs to be done through RClone. Run `./help --plugin=rclone` to see what's needed:

```
$ ./help --plugin=rclone
Plugins:

RClone - Adds ./rclone wrapper, set up for this project.
  [rclone]
    RCLONE_CONFIG_PASS   sets a password (default: none)
    RCLONE_CONFIG        sets the rclone.conf location (default: ${_script__basedir}/rclone.conf)
```

So initially we just need to add a `# [RClone]` comment, and our `./rclone` wrapper is created:

```bash
#!/bin/bash -eu
# [Script]
# Name = backup-etc
# Description = Backup /etc
#
# [Restic]
# RESTIC_PASSWORD='hunter2'
# RESTIC_REPOSITORY="/var/backups/my-etc-backup"
#
# [RClone]

# Trigger a backup
# @sudo
backup() {
    dirs=( /etc )
    restic backup --one-file-system --verbose=1 "${dirs[@]}"
}

# Restore files to DIR
# @sudo
restore() {
    (( $# == 1 )) || { echo >&2 "Usage: $0 DIR"; exit 1; }
    local restoredir="$1"
    restic restore latest --target "$restoredir"
}

# Print what is in the latest Restic backup
# @sudo
lsbackup() {
    restic ls latest
}

. ../../multitool.bash
```

```
jturner@jturner-desktop:/opt/atl_manage/lib/multitool/demo/backup$ ./help 
Creating symlink: rclone
Description: Backup /etc
Commands
  restic               #  Invokes restic with RESTIC_PASSWORD and RESTIC_REPOSITORY set as specified. [restic]
  restic-init          #  Invokes 'restic init --repository-version 2'                          [restic]
  rclone               #  Calls rclone with the script-specific settings                        [backup.sh]
  backup               #  Trigger a backup                                                      [backup.sh]
  lsbackup             #  Print what is in the latest Restic backup                             [backup.sh]
  help                 #  Print help                                                            [backup.sh]
  restore              #  Restore files to DIR                                                  [backup.sh]

Run './help --plugins' to see functions made available by plugins
```


