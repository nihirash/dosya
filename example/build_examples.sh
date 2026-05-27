#!/bin/bash

sjasmplus list.asm
sjasmplus -DZC list.asm
sjasmplus loadscr.asm
sjasmplus -DZC loadscr.asm
sjasmplus writetest.asm
sjasmplus -DZC writetest.asm

(cd bad-apple && sjasmplus main.asm)
(cd bad-apple && sjasmplus -DZC main.asm)