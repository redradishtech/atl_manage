Installation
============

Installing `hg-prompt` requires [Python][] 2.5+ and (obviously) Mercurial.

[Python]: http://python.org/

First, clone the repository:

    $ hg clone http://bitbucket.org/sjl/hg-prompt/

Edit the `[extensions]` section in your `~/.hgrc` file:

    [extensions]
    prompt = (path to)/prompt.py

Make sure everything is working:

    $ hg prompt 'test'
    test

Take a look at the [Quick Start][] guide to learn how to put some useful
information into your shell prompt.

[Quick Start]: ../quickstart/
