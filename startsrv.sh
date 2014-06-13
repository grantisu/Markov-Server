#!/bin/sh

source ~/perl5/perlbrew/etc/bashrc
plackup -o localhost -p 5000 -E deployment -s Starman

