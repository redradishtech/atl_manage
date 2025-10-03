#!/bin/bash
shopt -s extglob
rm -r  >&2 !(*.do)
