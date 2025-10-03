#!/usr/bin/env perl
#
use strict;
use warnings;
use SemVer;

my $version = "1.2.3";

my $semver = SemVer->new($version);
my $major = $semver->major;

print "Major version: $major\n";
