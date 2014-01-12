#!/usr/bin/env ruby
# based on: http://blog.interlinked.org/tutorials/rsync_time_machine.html

# customize these settings before you use this script
host        = ARGV[0] || ''
user        = ''
local_root  = ''
remote_root = ''
dont_backup = []



require 'open3'
require 'pry'

# figure out whether to start a new backup or continue an old one
list_of_backups = `ssh #{host} "ls #{remote_root}"`
is_first_backup = !list_of_backups.include?('current')
incomplete_backup_date = list_of_backups.match(/incomplete-(.*?)$(\n)/)
incomplete_backup_date = incomplete_backup_date[1] if incomplete_backup_date
if incomplete_backup_date
  backup_date = incomplete_backup_date
  puts "resuming the previous #{is_first_backup ? '(and first) ' : ''}backup: #{backup_date}"
else
  backup_date = Time.now.strftime('%Y-%m-%dT%H_%M_%S')
  puts "starting a new #{is_first_backup ? '(and first) ' : ''}backup: #{backup_date}"
end

# perform the backup
rsync_params  = ['-azvP', '--delete', '--delete-excluded'] 
rsync_params << '--link-dest=../current' if !is_first_backup
rsync_params += dont_backup.map {|a| "--exclude \"#{a}\""}
rsync_params << "#{local_root}/ #{user}@#{host}:#{remote_root}/incomplete-#{backup_date}"
command1 = "/usr/local/bin/rsync #{rsync_params.join(' ')} 2>&1"
stdin, stdout, stderr, wait_thr = Open3.popen3(command1) 
until stdout.eof?
  putc stdout.getc
end

# cleanup after the backup is finished
if wait_thr.value.success?
  puts "backup complete"
  puts "updating the 'current' backup link"
  command2 = "ssh #{user}@#{host} \"mv #{remote_root}/incomplete-#{backup_date} #{remote_root}/#{backup_date} && rm -f #{remote_root}/current && ln -s #{remote_root}/#{backup_date} #{remote_root}/current\""
  stdin, stdout, stderr, wait_thr = Open3.popen3(command2) 
  until stdout.eof?
    putc stdout.getc
  end
end
