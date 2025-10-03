# Versioned Directory Manager

A specification and bash script to manage versioned directories.

# Introduction

When deploying an application that may be upgraded, one typically will want to version the application directory to allow for possible rollback. E.g.:

```bash
root@jturner-desktop:/opt/app# ls -l
total 11
drwxr-xr-x 2 root root 3 Jul  8 15:18 4.0.0
drwxr-xr-x 2 root root 2 Jul  8 14:24 5.0.0
drwxr-xr-x 5 root root 7 Jul  8 15:21 old
lrwxrwxrwx 1 root root 3 Jul  8 14:24 current -> 5.0.0
lrwxrwxrwx 1 root root 3 Jul  8 14:24 previous -> 4.0.0
root@jturner-desktop:/opt/app# 
```

This project provides:

- A specification to nail down the conventions we're adhering to.
- A script, `switchver` that lets us upgrade or downgrade to any prior version, managing symlinks for us.

For instance, given:

```
root@jturner-desktop:/opt/app# ls -l
total 3
drwxr-xr-x 2 root root 3 Jul  8 15:45 4.0.0
drwxr-xr-x 2 root root 2 Jul  8 15:46 5.0.0
drwxr-xr-x 5 root root 6 Jul  8 15:46 old
lrwxrwxrwx 1 root root 3 Jul  8 15:45 current -> 5.0.0
lrwxrwxrwx 1 root root 3 Jul  8 15:46 previous -> 4.0.0
```
Let's upgrade from 5.0 to 6.0:

```
root@jturner-desktop:/opt/app# mkdir 6.0.0
root@jturner-desktop:/opt/app# switchver . upgrade 6.0.0
root@jturner-desktop:/opt/app# ls -l
total 3
drwxr-xr-x 2 root root 3 Jul  8 15:47 5.0.0
drwxr-xr-x 2 root root 2 Jul  8 15:47 6.0.0
drwxr-xr-x 6 root root 7 Jul  8 15:47 old
lrwxrwxrwx 1 root root 3 Jul  8 15:47 current -> 6.0.0
lrwxrwxrwx 1 root root 3 Jul  8 15:45 previous -> 5.0.0
root@jturner-desktop:/opt/app# 
root@jturner-desktop:/opt/app# ls -l old
total 3
drwxr-xr-x 2 root root 3 Jul  8 15:45 1.0.0
drwxr-xr-x 2 root root 3 Jul  8 15:45 2.0.0
drwxr-xr-x 2 root root 3 Jul  8 15:45 3.0.0
drwxr-xr-x 2 root root 3 Jul  8 15:45 4.0.0
lrwxrwxrwx 1 root root 6 Jul  8 15:47 5.0 -> ../5.0.0
```

and downgrading (back to 5.0 - implicit in the previous/ symlink):

```
root@jturner-desktop:/opt/app# switchver . downgrade
root@jturner-desktop:/opt/app# ls -l
total 4
wirwxr-xr-x 2 root root 3 Jul  8 15:45 4.0.0
drwxr-xr-x 2 root root 2 Jul  8 15:48 5.0.0
drwxr-xr-x 2 root root 2 Jul  8 15:47 6.0.0
drwxr-xr-x 5 root root 6 Jul  8 15:48 old
lrwxrwxrwx 1 root root 3 Jul  8 15:45 current -> 5.0.0
lrwxrwxrwx 1 root root 3 Jul  8 15:47 next -> 6.0.0
lrwxrwxrwx 1 root root 3 Jul  8 15:48 previous -> 4.0.0
root@jturner-desktop:/opt/app# ls -l old
total 2
drwxr-xr-x 2 root root 3 Jul  8 15:45 1.0.0
drwxr-xr-x 2 root root 3 Jul  8 15:45 2.0.0
drwxr-xr-x 2 root root 3 Jul  8 15:45 3.0.0
lrwxrwxrwx 1 root root 6 Jul  8 15:48 4.0 -> ../4.0.0
```

At any time we can assert that our structure is as expected:

```
root@jturner-desktop:/opt/app# rm -f previous    # Mess up our structure
root@jturner-desktop:/opt/app# switchver . check 
Missing previous/ symlink. Marker file in /opt/app/old/4.0 suggests we need symlink previous -> 4.0.0
root@jturner-desktop:/opt/app# ln -s 4.0 previous   # Fix the problem
root@jturner-desktop:/opt/app# switchver . check && echo "All good"
All good
```

We can also find the oldest version in old/, i.e. not the current/ or previous/ version:

```
root@jturner-desktop:/opt/app# switchver . oldest
old/1.0.0
```

Old versions can be incrementally deleted:

root@jturner-desktop:/opt/app# rm -rf $(switchver . oldest)
root@jturner-desktop:/opt/app# rm -rf $(switchver . oldest)
root@jturner-desktop:/opt/app# rm -rf $(switchver . oldest)
root@jturner-desktop:/opt/app# rm -rf $(switchver . oldest)
root@jturner-desktop:/opt/app# rm -rf $(switchver . oldest)
root@jturner-desktop:/opt/app# ls -l        # current/, previous/ and (in this example) next/ versions are preserved
drwxr-xr-x 2 root root 4096 Jul 21 20:42 4.0.0
drwxr-xr-x 2 root root 4096 Jul 21 20:42 5.0.0
drwxr-xr-x 2 root root 4096 Jul 21 20:42 6.0.0
drwxr-xr-x 2 root root 4096 Jul 21 20:44 old
lrwxrwxrwx 1 root root    3 Jul 21 20:42 current -> 5.0.0
lrwxrwxrwx 1 root root    3 Jul 21 20:42 next -> 6.0.0
lrwxrwxrwx 1 root root    3 Jul 21 20:42 previous -> 4.0.0
/root@jturner-desktop:opt/app# ls -l old    # 4.0 is not a true old/ version
total.0.0
lrwxrwxrwx 1 root root 6 Jul 21 20:42 4.0 -> ../4.0.0





# Specification

Terminology:

* the `base` directory is the root of all our versioned directories (e.g. `/opt/app`)
* a `version` is a SemVer.org string of the form '1.2.3', '1.2.3-patchver', '1.2.3-patchver~myiteration1', etc. 
* a 'version directory' is a directory whose name is a `version`
* an `upgrade marker file` is a file with name `UPGRADED_TO_xyz.txt`, where `xyz` is a `version`. 
* a `downgrade marker file` is a file with name `DOWNGRADED_TO_xyz.txt`, where `xyz` is a `version`. 
* an `old version directory` is a `version directory` containing an `upgrade marker file`
* an `newer version directory` is a `version directory` containing an `downgrade marker file`

The rules are:

* There MUST be a `current` symlink pointing to a `version directory` in the `base` directory.
* There MAY be a `previous` symlink which, if present, points to an `old version directory` in the `base` directory.
* If versions older than `previous` exist:
** There MUST be an `old/` directory present.
** All `old version directories` older than the `previous` must be directly within `old/`
** The `old version directory` referenced from `previous` must be symlinked into `old/`.
* There MAY be a `next` symlink which, after a downgrade, points to `newer version directory` downgraded from.
** If versions newer than `current` exist:
** All `newer version directories` must be in the `base` directory.


# Motivation

Read this to understand the choices for the above structure.

Say you are deploying an application to Linux. In my case it is usually Atlassian Jira, which wants an application directory `/opt/atlassian/jira` and a data directory, `/var/atlassian/application-data/jira`. 

## First attempt

Let's start by installing the app in `/opt/atlassian/jira`

The path to our executable is thus `/opt/atlassian/jira/start.sh`.

### Refinement 2: versioning

This is v1.0 of our app, and new releases are expected. Let's version our directory so we can keep old versions to downgrade to if necessary. We'll make a `current` symlink so the path to our executable is stable:

```
root@jturner-desktop:/opt/atlassian/jira# ls -l
total 1
drwxr-xr-x 2 root root 2 Jul  8 14:09 1.0.0
lrwxrwxrwx 1 root root 4 Jul  8 14:09 current -> 1.0/
```

## Refinement 3: a previous/ symlink

Version 1.1 arrives. You unpack it but it's not worth upgrading to.

Version 2.0 arrives. You upgrade to it:

```
root@jturner-desktop:/opt/atlassian/jira# ls -l
total 2
drwxr-xr-x 2 root root 2 Jul  8 14:09 1.0.0
drwxr-xr-x 2 root root 2 Jul  8 14:11 1.1
drwxr-xr-x 2 root root 2 Jul  8 14:11 2.0.0
lrwxrwxrwx 1 root root 3 Jul  8 14:11 current -> 2.0.0
```

Now we have a problem: if we need to roll back, it's not obvious that we should roll back to 1.0, not 1.1.

Let's fix this by keeping a `previous` symlink:

```
root@jturner-desktop:/opt/atlassian/jira# ls -l
total 3
drwxr-xr-x 2 root root 2 Jul  8 14:09 1.0.0
drwxr-xr-x 2 root root 2 Jul  8 14:11 1.1
drwxr-xr-x 2 root root 2 Jul  8 14:11 2.0.0
lrwxrwxrwx 1 root root 3 Jul  8 14:11 current -> 2.0.0
lrwxrwxrwx 1 root root 3 Jul  8 14:12 previous -> 1.0.0
```

## Refinement 3: upgrade marker files

Version 3.0 arrives, and you upgrade:

```
root@jturner-desktop:/opt/atlassian/jira# ls -l
total 3
drwxr-xr-x 2 root root 2 Jul  8 14:09 1.0.0
drwxr-xr-x 2 root root 2 Jul  8 14:11 1.1
drwxr-xr-x 2 root root 2 Jul  8 14:11 2.0.0
drwxr-xr-x 2 root root 2 Jul  8 14:13 3.0.0
lrwxrwxrwx 1 root root 3 Jul  8 14:14 current -> 3.0.0
lrwxrwxrwx 1 root root 3 Jul  8 14:11 previous -> 2.0.0
```

A new problem: we now have no record of what version occurred before 2.0 (previous/). If we guessed 1.1 we'd be wrong.

Let's add a marker file to each past version's directory, indicating which version we upgraded to:

```
root@jturner-desktop:/opt/atlassian/jira# touch 1.0/UPGRADED_TO_2.0.txt
root@jturner-desktop:/opt/atlassian/jira# touch 2.0/UPGRADED_TO_3.0.txt
```

Putting marker files in old version directories yields many benefits:

- by searching for \*/UPGRADED\_TO\_x.txt we find the precursor to version x
- the marker file acts as a nice visual cue to administrators that "this is not the production version"
- The marker file's timestamp indicates when the upgrade took place.
- it's handy place to put upgrade notes


## Refinement 4: an archive directory

More releases are made. Our directory is getting pretty messy:

```
root@jturner-desktop:/opt/atlassian/jira# ls -l
total 4
drwxr-xr-x 2 root root 3 Jul  8 14:16 1.0.0
drwxr-xr-x 2 root root 2 Jul  8 14:11 1.1
drwxr-xr-x 2 root root 3 Jul  8 14:16 2.0.0
drwxr-xr-x 2 root root 2 Jul  8 14:13 3.0.0
drwxr-xr-x 2 root root 2 Jul  8 14:24 4.0.0
drwxr-xr-x 2 root root 2 Jul  8 14:24 5.0.0
lrwxrwxrwx 1 root root 3 Jul  8 14:24 current -> 5.0.0
lrwxrwxrwx 1 root root 3 Jul  8 14:24 previous -> 4.0.0
```

Let's create an old/ directory for versions we're pretty sure we don't care about.

```
root@jturner-desktop:/opt/atlassian/jira# ls -l
total 3
drwxr-xr-x 2 root root 2 Jul  8 14:24 4.0.0
drwxr-xr-x 2 root root 2 Jul  8 14:24 5.0.0
drwxr-xr-x 6 root root 7 Jul  8 14:27 old
lrwxrwxrwx 1 root root 3 Jul  8 14:24 current -> 5.0.0
lrwxrwxrwx 1 root root 3 Jul  8 14:24 previous -> 4.0.0
root@jturner-desktop:/opt/atlassian/jira# ls -l old
total 3
drwxr-xr-x 2 root root 3 Jul  8 14:16 1.0.0
drwxr-xr-x 2 root root 2 Jul  8 14:11 1.1
drwxr-xr-x 2 root root 3 Jul  8 14:16 2.0.0
drwxr-xr-x 2 root root 2 Jul  8 14:13 3.0.0
lrwxrwxrwx 1 root root 6 Jul  8 14:27 4.0 -> ../4.0.0
root@jturner-desktop:/opt/atlassian/jira# 
```

Note that the 'previous' version (4.0) is not moved to old/ yet; instead a symlink is created. This is for three reasons:

1) The old/ directory might in fact be on another filesystem, in which case archiving (`mv 4.0 old/`) and restoring (`mv old/4.0 .`) are potentially slow (if we have lots of contents) and failure-prone (e.g. if you run out of disk space halfway through the `mv`). 'Slow' and 'failure-prone' are not what we want during upgrades.

2) I have cron-triggered backup scripts that backup `/opt/atlassian/jira/$ver/` -- not `/opt/atlassian/jira/current`, specifically because current/ might change halfway through a backup. The last step of my upgrade procedure will be to change the backup scripts to upgrade `/opt/atlassian/jira/$newver`, and in the interim (after changing symlinks, but before adjusting backup cronjobs) I want consistent backup backups of `/opt/atlassian/jira/$ver/`.

3) In my case, /opt/atlassian/jira is replicated from production to sandbox instances. I upgrade sandbox first. If /opt/atlassian/jira/$oldver/ were to disappear on sandbox (moved to old/), replication would immediately start recreating it from production, where $oldver is still current.


## Refinement 5: downgrade marker files

Thanks to the old/$ver/UPGRADED\_TO\_xyz.txt marker files, we can always figure out our 'previous' version. How about the other way?

Say we downgrade from 5.0 to 4.0 to 3.0 to 2.0:

```
root@jturner-desktop:/opt/app# ls -l
total 5
drwxr-xr-x 2 root root 3 Jul  8 20:59 1.0.0
drwxr-xr-x 2 root root 3 Jul  8 21:28 2.0.0
drwxr-xr-x 2 root root 3 Jul  8 21:25 3.0.0
drwxr-xr-x 2 root root 3 Jul  8 21:25 4.0.0
drwxr-xr-x 2 root root 4 Jul  8 21:21 5.0.0
drwxr-xr-x 2 root root 3 Jul  8 21:28 old
lrwxrwxrwx 1 root root 3 Jul  8 21:25 current -> 2.0.0
lrwxrwxrwx 1 root root 3 Jul  8 21:25 next -> 3.0.0
lrwxrwxrwx 1 root root 3 Jul  8 21:28 previous -> 1.0.0
```

Our `next/` symlink is set, so we know that 3.0 comes after 2.0. But what then? We can't be _sure_ if 4.0 or 5.0 is next.

To fix this, whenever we downgrade, let's add a DOWNGRADED\_TO\_xyz.txt marker file in the old current/ directory. By following the marker files we can now switch version up just as easily as down.

# Questions

### Why not track current version in a text file?

Instead of all these marker files, we could just have a current/ symlink plus a `version_history.txt` listing past versions, perhaps with comments or even upgrade dates:

```
2020-03-02	1.0.0
2020-04-24	2.0	# Upgraded from 1.0.0
2020-04-19	3.0.0
2020-04-20	2.0	# 3.0 is broken; downgrade
2020-04-30	3.1	# 3.1 fixes the bugs; upgrade from 2.0.0
```

This has the advantage of recording loops (e.g. 2.0 to 3.0 to 2.0 to 3.0) which marker files can't.

I prefer the marker file approach because each version directory is self-contained. Old directories can be backed up or copied, and each bears a record of its status. A marker file is a good visual indicator to administrators of the current directory's status.

### Why not use a version control system?

We could toss everything in git, tag it as '1.0', replace files with 2.0 files, then tag as '2.0', and so on.

The disadvantage here is if the directory is large. We don't want a .git directory duplicating all our contents, and we don't really care to track changes per file.
