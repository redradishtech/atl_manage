# App Management Scripts

A collection of personal scripts I use to manage deployments of apps, mainly Atlassian's self-hosted Jira, Confluence and Crowd (hence the `atl_` prefix in `bin/atl_*`), but also a few others, like InvoiceNinja.

## Goals

The kinds of app I maintain are definitely pets, not cattle. These are Java apps with 32Gb+ heaps, 1Tb+ data directories and millions of database records. Sometimes the on-disk configuration needs tweaking. Sometimes the app itself needs tweaking by modifying or adding JSP files. Each production installation typically has an associated sandbox and associated cold standby.

So, pets not cattle, but we also don't want snowflakes. We want apps to be:

1. **Version-controlled**: the app deployment is all in version control. This makes it possible for tweaks to be made to the configuration or application itself, and have those tweaks captured and propagated across instances (e.g. to sandbox/standby) and upgrades.
2. **Self-contained**: all 'auxiliary' files relating to an application deployment (webserver config, backup config,
   monitoring, systemd scripts etc) are stored alongside the application's native files, e.g. in
   `/opt/atlassian/jira/current/{backups,apache2,monitoring,systemd}`, and version-controlled along with the app.
3. **Profile-driven**: there is a 'profile' for each app deployment, loaded by the user (`atl load jira-sandbox.mycompany.com`). The files in version control are almost entirely generic, containing `@TOKENS@` replaced at
   runtime with profile env variables. E.g. deploying with `ATL_ROLE=prod` yields a different app to one with
   `ATL_ROLE=sandbox`, or setting `ATL_BACKUP_TYPES=rsnapshot,tarsnap` will add new files in `backups/` and
   `monitoring/`. 
4. **Centrally updated**: each app deployment is version-controlled, but they all share a common ancestor. This lets me
   roll out changes to many instances. E.g. if I add a new flag to `bin/setenv.sh` to the ancestor Jira, it will be
   rolled out on next upgrade to all Jiras I administer.
5. **Easy to upgrade**: there is a well-defined upgrade process with easy rollback, that ensures cold standbys are
   upgraded too.


## Scripts galore

The `bin/` directory contains scripts for installing, upgrading, and generally working with apps. They assume a 'profile' is loaded in the shell to contextualize them. These scripts were written over a 10 year period, each for a specific purpose. Some were one-off hacks, and some I use almost daily.

## Bash libraries

In `lib/` there are some attempts at generalized libraries (`versioned_directories`, `requiresort`, `multitool`, `jeventutils`, `lib/loadfuncs.sh`, `appfetcher`). These are not quite polished enough to live independently, but are reusable.

