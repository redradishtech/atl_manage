#!/bin/bash
# [Script]
# Description = Illustrates pre: and post: function tags

# @pre:two
one() { echo "1"; }

# @pre:three
two() { echo "2"; }

# @main
three() { echo "3"; }

# @post:three
liftoff() { echo "liftoff"; }

# @post:liftoff
landing() { echo "landed"; }

# @pre:*
sudo() { echo "sudo"; }

# @pre:*
devbox() { echo "devbox"; }

# We should create tsort input to indicate that three depends on two, and two depends on one
# three two
# two one

. ../../multitool.bash
