#!/usr/bin/env python3.4
# vim: set filetype=python :

# inspired by: http://blog.interlinked.org/tutorials/rsync_time_machine.html


from subprocess import Popen, PIPE, DEVNULL
from datetime import datetime
from fcntl import lockf, LOCK_EX, LOCK_NB
import re
import sys
import os
import yaml
import argparse


# from https://stackoverflow.com/questions/4417546/ ...
# constantly-print-subprocess-output-while-process-is-running/
def run_at_source(command, display=True, timeout=15):
    if display:
        # print("running: {}".format(command))
        popen = Popen(command, stdout=PIPE, bufsize=1, shell=True)
        lines_iterator = iter(popen.stdout.readline, b"")
        while popen.poll() is None:
            for line in lines_iterator:
                nline = line.rstrip()
                print(nline.decode("utf-8"), end="\r\n", flush=True)
    else:
        # print("running: {}".format(command))
        popen = Popen(command, stdout=PIPE, stderr=DEVNULL, shell=True)
        popen.wait(timeout=timeout)
    return popen


def run_at_destination(backup_destination, command, timeout=15):
    if ":" in backup_destination:
        command = "ssh {} {}".format(connection(backup_destination), command)
    return run_at_source(command, display=False, timeout=timeout)


def path(resource):
    if ":" in resource:
        match = re.compile("^.*:(.*)$").match(resource)
        return match.group(1)
    else:
        return resource


def connection(resource):
    if ":" in resource:
        match = re.compile("^(.*):.*$").match(resource)
        return match.group(1)
    else:
        return None


def all_backups(backup_destination):
    global all_backups_cached
    if all_backups_cached is None:
        all_backups_cached = run_at_destination(
            backup_destination,
            "ls {}".format(path(backup_destination)))
        all_backups_cached = all_backups_cached.stdout.read().decode("utf-8")
        all_backups_cached = all_backups_cached.splitlines()
    return all_backups_cached


def completed_backups(backup_destination):
    completed = []
    for backup in all_backups(backup_destination):
        if backup == "completed":
            next
        inc = re.compile("^incomplete-.*$")
        if inc.match(backup):
            next
        completed.append(backup)
    return completed


def incomplete_backup(backup_destination):
    for backup in all_backups(backup_destination):
        inc = re.compile("^incomplete-.*$")
        if inc.match(backup):
            return backup


def old_backups(backup_destination):
    months_encountered = set()
    backups_to_remove = set()
    for backup in sorted(sorted(completed_backups(backup_destination),
                         reverse=True)[30:-1]):
        made_on = datetime.strptime(backup, "%Y-%m-%dT%H_%M_%S").date()
        made_on_month = (made_on.year, made_on.month)
        if made_on_month in months_encountered:
            backups_to_remove.add(backup)
        else:
            months_encountered.add(made_on_month)
    return backups_to_remove


def delete_old_backups(backup_destination):
    for backup in sorted(old_backups(backup_destination)):
        backup_path = "{}/{}".format(path(backup_destination), backup)
        print("deleting {}".format(backup_path))
        run_at_destination(backup_destination,
                           "rm -rf {}".format(backup_path), timeout=300)


def main():

    os.nice(20)

    command = 'route -n show -inet | grep default | head -1 | awk \'{print $8}\' | grep ppp'
    proc = run_at_source(command)
    if proc.returncode == 0:
        print('warning: on a wwan connection, skipping backup')
        sys.exit()

    ap = argparse.ArgumentParser(
        description='backup a directory with versioning, kinda like Apple\'s \
                     Time Machine, but based on rsync instead')
    ap.add_argument('-c', '--config', default='~/.illbeback',
                    help='config file to use, defaults to ~/.illbeback')
    args = ap.parse_args()
    config = yaml.safe_load(open(os.path.expanduser(args.config)))

    backup_sources = config['source']
    if backup_sources.__class__ == str:
        backup_sources = {'default': backup_sources}
    backup_destination = os.path.join(config['destination'], config['name'])
    dont_backup = config.get('exclude', [])
    name = config['name']

    lockfile = open("/tmp/illbeback-{}.lockfile".format(name),
                    mode="w")
    try:
        lockf(lockfile, LOCK_EX | LOCK_NB)
    except BlockingIOError:
        print("error: another instance is running")
        sys.exit()

    global all_backups_cached
    all_backups_cached = None

    is_first_backup = "current" not in all_backups(backup_destination)
    if incomplete_backup(backup_destination) is not None:
        backup_date = re.compile("^incomplete-(.*?)$").match(
            incomplete_backup(backup_destination)).group(1)
        action = "resuming the previous"
    else:
        backup_date = datetime.now().strftime('%Y-%m-%dT%H_%M_%S')
        action = "starting a new"
        if is_first_backup:
            action += " (and first)"

    print("{} backup: {}".format(action, backup_date))

    sum_of_returncodes = 0
    for key in backup_sources:
        source = os.path.expanduser(backup_sources[key])
        if len(backup_sources) == 1:
            source = "{}/".format(source)
            destination = "{}/incomplete-{}".format(backup_destination,
                                                    backup_date)
        else:
            source = "{}/".format(source)
            destination = "{}/incomplete-{}/{}/".format(
                backup_destination,
                backup_date,
                key)
        rsync_params = ["-azvP", "--delete", "--delete-excluded"]
        if not is_first_backup:
            if len(backup_sources) == 1:
                rsync_params.append("--link-dest=../current")
            else:
                rsync_params.append("--link-dest=../../current/{}".format(key))
        for item in dont_backup:
            rsync_params.append("--exclude \"{}\"".format(item))
        rsync_params.append("{} {}".format(source, destination))
        newdir = backup_destination.split(':')[1]
        command = "mkdir -p {}".format(newdir)
        proc = run_at_destination(backup_destination, command)
        if proc.returncode != 0:
            print("Error: rc={} stdout={} command={}".format(
                proc.returncode, proc.stdout.read(), command))
            raise
        command = "rsync {} 2>&1".format(" ".join(rsync_params))
        proc = run_at_source(command)
        sum_of_returncodes += proc.returncode

    if sum_of_returncodes == 0:
        print("backup complete")
        print("updating the 'current' backup link")
        commands = []
        commands.append("mv {}/incomplete-{} {}/{}".format(
                        path(backup_destination),
                        backup_date,
                        path(backup_destination),
                        backup_date))
        commands.append("rm -f {}/current".format(path(backup_destination)))
        commands.append("ln -s {}/{} {}/current".format(
                        path(backup_destination),
                        backup_date,
                        path(backup_destination)))
        for command in commands:
            proc = run_at_destination(backup_destination, command)
            if proc.returncode != 0:
                print("Error: rc={} stdout={} command={}".format(
                    proc.returncode, proc.stdout.read(), command))
                raise

    delete_old_backups(backup_destination)

main()
