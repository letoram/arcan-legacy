arcan-legacy
============

This repository contains supporting utilites that can be combined with the
Arcan project for frontend, HTPC etc. purposes. The code here used to be
part of the main arcan repository from 0.1-0.4.

    resources/ -- tree layout, support scripts and importers
    launcher/  -- C#/.NET based windows launcher
    romman/    -- 0.1-0.4 database utility (for safekeeping)
    dbman/     -- 0.5+ database utility

First, make sure you have a checked out and working arcan build from
git clone https://github.com/letoram/arcan.git

Then make a checkout of this one, i.e.
git clone https://github.com/letoram/arcan-legacy.git

Then checkout the application, i.e.
git clone https://github.com/letoram/awb.git or
git clone https://github.com/letoram/gridle.git

Populate arcan-legacy/resources as before,
i.e.
libretro cores, etc. into resources/targets/mytarget.[so,dll,exe,]
system- global datafiles (bios, ...) into resources/games/system
target-specific datafiles into resources/targets/mytarget

Build a database:
        ./dbman/dbman.rb --dbtool path/to/arcan\_db --database mydb.sqlite
               --target resources/targets --configs resources/games

Now things should work similarly to before:
./arcan -d mydb.sqlite -p /path/to/legacy/resources /path/to/awb\_or\_gridle
