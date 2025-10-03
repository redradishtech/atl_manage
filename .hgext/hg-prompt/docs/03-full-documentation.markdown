Documentation
=============

This page contains the full documentation for `hg-prompt`.

[TOC]

Usage
-----

The `hg prompt` command takes a single string as an argument and outputs it.
Here's a simple (and useless) example:

    $ hg prompt "test"
    test

Keywords in curly braces can be used to output repository information:

    $ hg prompt "currently on {branch}"
    currently on default

Keywords also have an extended form:

    {optional text{branch}more optional text}

This form will output the text and the expanded keyword **only** if the
keyword successfully expands. This can be useful for displaying extra text
only if it's applicable:

    $ hg prompt "currently on {branch} and at {bookmark}"
    currently on branch default and at

    $ hg prompt "currently on {branch} {and at {bookmark}}"
    currently on branch default

    $ hg bookmark my-book

    $ hg prompt "currently on {branch} {and at {bookmark}}"
    currently on branch default and at my-book

You can give the `--angle-brackets` option to use angle brackets for keywords
instead of curly brackets. This can come in handy when combining a simple
prompt string with more complicated shell functionality (like color
variables):

    $ hg prompt "{currently on {branch}}"
    currently on default

    $ hg prompt --angle-brackets "<currently on <branch>>"
    currently on default

Keywords
--------

There a number of keywords available.  Some of the keywords support filters.
These filters can be combined when it makes sense.  If in doubt, try it!

### `bookmark`

Display the current bookmark (requires the [bookmarks][] extension).

### `branch`

Display the current branch.

* `|quiet`: Display the current branch only if it is not the default branch.

### `closed`

Display `X` if working on a closed branch (i.e. if committing now would reopen
the branch).

### `count`

Display the number of revisions in the given revset (the revset `all()` will be
used if none is given).

See `hg help revsets` for more information.

* `|REVSET`: The revset to count.

### `incoming`

Display nothing, but if the default path contains incoming changesets the extra
text will be expanded.

For example: `{incoming changes{incoming}}` will expand to `incoming changes` if
there are changes, otherwise nothing.

Checking for incoming changesets is an expensive operation, so `hg-prompt` will
cache the results in `.hg/prompt/cache/` and refresh them every 15 minutes.

* `|count`: Display the number of incoming changesets (if greater than 0).

### `node`

Display the (full) changeset hash of the current parent.

* `|short`: Display the hash as the short, 12-character form.
* `|merge`: Display the hash of the changeset you're merging with.

### `outgoing`

Display nothing, but if the current repository contains outgoing changesets (to
default) the extra text will be expanded.

For example: `{outgoing changes{outgoing}}` will expand to `outgoing changes` if
there are changes, otherwise nothing.

Checking for outgoing changesets is an expensive operation, so `hg-prompt` will
cache the results in `.hg/prompt/cache/` and refresh them every 15 minutes.

* `|count`: Display the number of outgoing changesets (if greater than 0).

### `patch`

Display the topmost currently-applied patch (requires the [mq][] extension).

* `|count`: Display the number of patches in the queue.
* `|applied`: Display the number of currently applied patches in the queue.
* `|unapplied`: Display the number of currently unapplied patches in the queue.
* `|quiet`: Display a number only if there are any patches in the queue.

### `patches`

Display a list of the current patches in the queue.  It will look like this:

    $ hg prompt '{patches}'
    bottom-patch -> middle-patch -> top-patch

* `|reverse`: Display the patches in reverse order (i.e. topmost first).
* `|hide_applied`: Do not display applied patches.
* `|hide_unapplied`: Do not display unapplied patches.
* `|join(SEP)`: Display `SEP` between each patch, instead of the default ` -> `.
* `|pre_applied(STRING)`: Display `STRING` immediately before each applied patch.  Useful for adding color codes.
* `|post_applied(STRING)`: Display `STRING` immediately after each applied patch.  Useful for resetting color codes.
* `|pre_unapplied(STRING)`: Display `STRING` immediately before each unapplied patch.  Useful for adding color codes.
* `|post_unapplied(STRING)`: Display `STRING` immediately after each unapplied patch.  Useful for resetting color codes.

### `queue`

Display the name of the current MQ queue.

### `rev`

Display the repository-local changeset number of the current parent.

* `|merge`: Display the repository-local changeset number of the changeset you're merging with.

### `root`

Display the full path to the root of the current repository, without a trailing
slash.

* `|basename`: Display the directory name of the root of the current repository. For example, if the repository is in `/home/u/myrepo` then this keyword would expand to `myrepo`.

### `status`

Display `!` if the repository has any changed/added/removed files, otherwise `?`
if it has any untracked (but not ignored) files, otherwise nothing.

* `|modified`: Display `!` if the current repository contains files that have been modified, added, removed, or deleted, otherwise nothing.
* `|unknown`: Display `?` if the current repository contains untracked files, otherwise nothing.

### `tags`

Display the tags of the current parent, separated by a space.

* `|quiet`: Display the tags of the current parent, excluding the tag `tip`.
* `|SEP`: Display the tags of the current parent, separated by `SEP`.

### `task`

Display the current task (requires the [tasks][] extension).

### `tip`

Display the repository-local changeset number of the current tip.

* `|node`: Display the (full) changeset hash of the current tip.
* `|short`: Display a short form of the changeset hash of the current tip (must be used with the `|node` filter)

### `update`

Display `^` if the current parent is not the tip of the current branch,
otherwise nothing.  In effect, this lets you see if running `hg update` would do
something.

[bookmarks]: http://mercurial.selenic.com/wiki/BookmarksExtension
[tasks]: http://bitbucket.org/alu/hgtasks/wiki/Home
[mq]: http://mercurial.selenic.com/wiki/MqExtension

Sample Prompts
--------------

`hg-prompt` supports many keywords, but you probably don't want to use them all
at once. Which keywords you'll find useful depends on the workflow(s) you
commonly use.

Here are some example prompts to get you started.

### A Basic Prompt

A very simple prompt could tell you:

* Which named branch you're currently working on.
* If there are any uncommitted changes in the working directory.
* If you're at a revision that's not a branch tip (i.e. if running `hg update`
  would do something).

To get a prompt like this you could add this to your `~/.bashrc` file:

    export PS1='\u in \w`hg prompt "{on {branch}}{status}{update}" 2>/dev/null` $'

The result would look something like this:

    username in ~/src $ cd project
    username in ~/src/project on feature-branch $ touch sample
    username in ~/src/project on feature-branch? $ hg add sample
    username in ~/src/project on feature-branch! $ hg commit -m 'Add a file.'
    username in ~/src/project on feature-branch $ hg update default
    username in ~/src/project on default $ hg update 0
    username in ~/src/project on default^ $

The `2>/dev/null` part of the prompt command prevents errors from showing when
you're not currently in a Mercurial repository.

The keywords (`{branch}`, `{status}` and `{update}`) display the relevant
information.

The extra text in the `{branch}` keyword will only display if a branch exists,
so you won't see the word "on" if you're not in a repository.

### A More Compact Basic Prompt

Some people prefer a smaller, less obtrusive prompt. To get that kind of
prompt you can omit some of the less important text:

    export PS1='\w`hg prompt "[{branch}{status}{update}]" 2>/dev/null` $'

That will give you something like this:

    ~/src $ cd project
    ~/src/project[feature-branch] $ touch sample
    ~/src/project[feature-branch?] $ hg add sample
    ~/src/project[feature-branch!] $ hg commit -m 'Add a file.'
    ~/src/project[feature-branch] $ hg update default
    ~/src/project[default] $ hg update 0
    ~/src/project[default^] $
