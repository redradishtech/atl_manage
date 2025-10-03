#!/bin/bash
redo pid
# Symlink to the crash log, if any
ln -sf /tmp/hs_err_pid$(cat pid).log .
