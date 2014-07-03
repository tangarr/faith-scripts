#!/bin/bash

echo WYSTAPIL JAKIS BLAD
LD_LIBRARY_PATH=/opt/lib /opt/faith aborted "$1" && halt

exit 0
