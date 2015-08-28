
# This file is a stub
# It will only be run if the 'god' configuration is out of date

p [:config_out_of_date, :updating_now]
puts `/home/pi/PrintToPi/update/update_all.sh`
