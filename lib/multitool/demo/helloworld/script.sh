#!/bin/bash -eu
# [Script]
# Name = multitool_demo
# Description = Demonstrates a multitool script
# ProductionHost = jturner-desktop
#
# [Unit]

# Our amazing function
# @main
hello() {
	echo "Hello world!"
}

# A function that runs as root
# @sudo
# @execstart
helloroot() {
	echo "Hello root! We are EUID $EUID"
}


. ../../multitool.sh
