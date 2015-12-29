#!/bin/sh

if [[ `id -u` != 0 ]]; then
    echo "error: this script must be run by root"
    exit 1
fi

echo installing illbeback

cp illbeback.sh /usr/local/bin/illbeback
chown root:bin /usr/local/bin/illbeback
chmod 555 /usr/local/bin/illbeback

echo done
