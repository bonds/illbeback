# Requirements

* Python 3.x
* rsync
* pip install pyyaml

# Installation

* ````git clone https://github.com/bonds/illbeback /tmp/illbeback````
* ````doas /tmp/illbeback/install.sh````

# Usage

````
usage: illbeback [-h] [-c CONFIG]

backup a directory with versioning, kinda like Apple's Time Machine, but based
on rsync instead

optional arguments:
  -h, --help            show this help message and exit
  -c CONFIG, --config CONFIG
                        config file to use, defaults to ~/.illbeback
````

# Config Examples

## Example A: ~/.illbeback
````
# vim: set filetype=yaml :

name: laptop
source: "~"
destination: "myserver.example.com:/mnt/backups"
exclude:
    - "*.core"
    - ".config/fish/fish_history"
    - ".vim/backup"
    - "/Library/Application\ Support/Alfred\ 2/*"
    - "/Library/Caches/"
````

## Example B: ~/.illbeback-photos

````
# vim: set filetype=yaml :

name: photos
source:
    cache: "~/.cache/shotwell"
    config: "~/.local/share/shotwell"
    library: "/run/media/scott/usb0"
destination: "myserver.example.com:/mnt/backups"
exclude:
    - ".Trash-1000"
