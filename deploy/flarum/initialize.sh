#!/bin/sh
# Explicit first-install operation, not an automatic runtime migration.
set -eu
test ! -e /data/config.php
test -f /bootstrap/install.json
mkdir -p /data/assets /data/storage
cp -a /opt/flarum-seed/assets/. /data/assets/
cp -a /opt/flarum-seed/storage/. /data/storage/
touch /data/forum.sqlite
php -d memory_limit=256M flarum install --file=/bootstrap/install.json --no-interaction
php -r '$p="/data/config.php"; $c=require $p; $c["flarum_announcements.disabled"]=true; $c["cookie.path"]="/flarum"; $c["cookie.secure"]=true; $c["database"]["journal_mode"]="WAL"; $c["database"]["busy_timeout"]=5000; $c["database"]["synchronous"]="FULL"; file_put_contents($p,"<?php return ".var_export($c,true).";\n");'
chown -R www-data:www-data /data
chmod 700 /data
chmod 600 /data/config.php /data/forum.sqlite
