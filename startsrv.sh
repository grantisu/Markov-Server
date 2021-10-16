#!/bin/sh

# DEPRECATED: use Markov-Server.service as a unit file instead

#source ~/perl5/perlbrew/etc/bashrc
plackup -o localhost -p 5000 -E deployment -s Starman --access-log access.log --workers=1 --max-requests=50000

