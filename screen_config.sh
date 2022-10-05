#!/bin/bash

declare -a schedule_array
declare -a temp_array
declare -a screen_array
declare -a variation_array

jq_path=/usr/local/bin
file=$(pwd)/config.json
new_file=$HOME/.working/new_file.json
new_json=$(pwd)/temp_config.json
new_config_file=$(pwd)/new_config.json
content_config=$(pwd)/content.cfg
publish_path=/var/www/html/publishConfig/htmlApps/btmosaic/staging

# Functions

# Create working directory
function working_directory {
  if [[ ! -d $HOME/.working ]]
  then
    mkdir $HOME/.working
  else
    rm -f $HOME/.working/*
  fi
}

# Get number of schedules in config file
function get_number_of_schedules {
  echo $(grep -c variation $file)
}

# Get the length of the schedule array
function get_schedule_array_length {
  echo ${#schedule_array[@]}
}

# Iterate through config file and build out schedules to display
function build_schedule_array {
  for i in $( seq 1 $(get_number_of_schedules))
  do
    start_date=$(grep -A2 start $file | grep date | head -$i | tail -1 | cut -d\" -f4)
    start_time=$(grep -A2 start $file | grep time | head -$i | tail -1 | cut -d\" -f4)
    start=$(echo $start_date " " $start_time)
    end_date=$(grep -A2 end $file | grep date | head -$i | tail -1 | cut -d\" -f4)
    end_time=$(grep -A2 end $file | grep time | head -$i | tail -1 | cut -d\" -f4)
    end=$(echo $end_date " " $end_time)
    type=$(grep type $file | head -$i | tail -1 | awk '{print $2}' | tr -d ',')
    variation=$(grep variation $file | head -$i | tail -1 | cut -d\" -f4)
    schedule_array[$i]="$start, $end, $type, $variation"
  done
}

# Rebuild array we can write it out
function rebuild_array {
  # Create new array without any missing gaps created by the delete
  # remove the line to delete
  if [[ $1 != "" ]]
  then
    unset schedule_array[$1]
  fi
  # empty the temporary array so we don't create huge exponential arrays
  temp_array=()
  # Because the date sequence matters we have to sort the dates
  # Given that they're all dd/mm/yyyy format we can't do that as things stand
  # We have to convert the dates to yyyymmddhhmmss for the sorting to work.
  index=0

  while read list
  do
    line=$(echo $list | cut -d" " -f2-)
    startdate=$(echo $line | cut -d" " -f1 | cut -d\[ -f2)
    starttime=$(echo $line | cut -d" " -f2 | cut -d, -f1)
    enddate=$(echo $line | cut -d, -f2 | cut -d" " -f2)
    endtime=$(echo $line | cut -d, -f2 | cut -d" " -f3)
    screen=$(echo $line | cut -d, -f3 | tr -d " ")
    variation=$(echo $line | cut -d, -f4 | cut -d\] -f1 | tr -d " ")
    new_line="$startdate $starttime, $enddate $endtime, $screen, $variation"
    temp_array[index]+=$new_line
    index=$(($index+1))
  done < <(for i in "${schedule_array[@]}"
  do
    echo $temp_array[$i] | while read line
    do
      day=$(echo $line | cut -d/ -f1 | cut -d[ -f2)
      month=$(echo $line | cut -d/ -f2)
      year=$(echo $line | cut -d/ -f3 | cut -d" " -f1)
      hour=$(echo $line | cut -d" " -f2 | cut -d: -f1)
      minute=$(echo $line | cut -d: -f2- | cut -c1-2)
      echo $year$month$day$hour$minute $line
    done
  done | sort)


echo printing array
echo "${temp_array[@]}"

  # empty the proper array
  schedule_array=()

  # copy temp_array back to schdule array
  index=1
  for i in "${temp_array[@]}"
  do
    schedule_array[$index]+=$i
    index=$(($index+1))
  done

  # healthy paranoia
  temp_array=()
}

function publish_new_config {
  user=$(grep user $content_config | cut -d= -f2)
  echo $user
  grep "server" $content_config | cut -d= -f2 | while read list
  do
    echo "Publishing to $list"
    scp -q $new_config_file ${user}@${list}:${publish_path}/config.json < /dev/null
  done
  mv $new_config_file $file
}

# Write out the schedule and make it look pretty too
function schedule_writer {

  header='{
  "mosaicVmSid": 1846,
  "mosaicSchedule": ['
  
  footer=$(cat $file | sed -e"s/^{//" | tr -d '\n' | sed -e"s/.*\"noEventSlateUrl/\"noEventSlateUrl/")
  
  echo $header > $new_file
  size=$(get_schedule_array_length)
  counter=0

  for i in "${schedule_array[@]}"
  do
    echo "{ \"start\": { \"date\": \"$(echo $i | cut -d, -f1 | cut -d' ' -f1)\", \"time\": \"$(echo $i | cut -d, -f1 | cut -d' ' -f2)\" }," >> $new_file
    echo "\"end\": { \"date\": \"$(echo $i | cut -d, -f2 | cut -d' ' -f2)\", \"time\": \"$(echo $i | cut -d, -f2 | cut -d' ' -f3)\" }," >> $new_file
    echo "\"type\": $(echo $i | cut -d, -f3)," >> $new_file
    echo "\"variation\": \"$(echo $i | cut -d, -f4)\"" >> $new_file
    counter=$(($counter+1))
    if [[ $counter == $size ]]
    then
      echo '} ],' >> $new_file
    else
      echo '},' >> $new_file
    fi
  done

  echo $footer >> $new_file
  cat $new_file | ${jq_path}/jq . > $new_config_file
  rm $new_file

  echo "Publishing new configuration."
  publish_new_config

  echo "Schedule written!"
  sleep 3
}

function validate_date {
  day_check=0
  month_check=0
  year_check=0
  year_now=$(date +%Y)
  year_ahead=$(( $year_now + 1 ))
  day=$(echo $1 | cut -d/ -f1)
  month=$(echo $1 | cut -d/ -f2)
  year=$(echo $1 | cut -d/ -f3)
  rest=$(echo $1 | cut -d/ -f4)

  if [[ $rest != "" ]]
  then
    echo "Incorrect date".
  fi

  if (( $year >= $year_now && $year <= $year_ahead ))
  then
    if [[ ${#year} -eq 4 ]]
    then
      year_check=1
    fi
  fi

   if (( 10#${month} >= 01 && 10#${month} <= 12 ))
   then
     if [[ ${#month} -eq 2 ]]
     then
       month_check=1
     fi
   fi

   if [[ ${month} == 01 || ${month} == 03 || ${month} == 05 || ${month} == 07 || ${month} == 08 || ${month} == 10 || ${month} == 12 ]]
   then
     if (( 10#${day} >= 01 && 10#${day} <= 31 ))
     then
       day_check=1
     fi
   fi

  if [[ $month == 04 || $month == 06 || $month == 09 || $month == 11 ]]
  then
    if [[ 10#${day} -ge 01 && 10#${day} -le 30 ]]
    then
      day_check=1
    fi
  fi

  if [[ $month == "02" ]]
  then
    if [[ $(( $year % 4 )) == "0" ]]
    then
      if [[ 10#${day} -ge 01 && 10#${day} -le 29 ]]
      then
        day_check=1
      fi
    elif [[ $(( $year % 4 )) != "0" ]]
    then
      if [[ $day -ge 01 && $day -le 28 ]]
      then
        day_check=1
      fi
    fi
  fi

  if [[ $year_check == 1 && $month_check == 1 && $day_check == 1 ]]
  then
    echo $1 > ${HOME}/.working/${2}date
    break
  else
    echo "Invalid date"
  fi
}

function get_date {
  until false
  do
    if [[ $1 == start ]]
    then
      echo "Please enter the $1 date (dd/mm/yyyy)"
      read -p "Press Return for a start date of \"today\": " getdate
    else 
      echo ""
      read -p "Please enter the $1 date (dd/mm/yyyy): " getdate
    fi

    if [[ $getdate == "" && $1 == "start" ]]
    then
      getdate=$(date +"%d/%m/%Y")
      echo $getdate > ${HOME}/.working/${1}date
      break
    elif [[ $getdate =~ '/' ]]
    then
      validate_date $getdate $1
    fi
  done
}

function validate_time {
  hour_check=0
  minute_check=0
  hour=$(echo $1 | cut -d: -f1)
  minute=$(echo $1 | cut -d: -f2)
  rest=$(echo $1 | cut -d: -f3)
  if [[ $rest != "" ]]
  then
    echo "Incorrect time."
  fi

  if (( 10#${hour} >= 00 && 10#${hour} <= 23 ))
  then
    if [[ ${#hour} -eq 2 ]]
    then
      hour_check=1
    fi
  fi

  if (( 10#${minute} >= 00 && 10#${minute} <= 59 ))
  then
    if [[ ${#minute} -eq 2 ]]
    then
      minute_check=1
    fi
  fi

  if [[ $hour_check == 1 && $minute_check == 1 ]]
  then
    echo $1 > ${HOME}/.working/${2}time
    break
  fi
}

function get_time {
  until false
  do
    echo ""
    if [[ $1 == start ]]
    then
      echo "Please enter the $1 time (HH:MM)"
      read -p "Press Return for a start time of \"now\": " time
    else
      read -p "Please enter the $1 time (HH:MM): " time
    fi
    if [[ $time == "" ]]
    then
      time=$(date +"%H:%M")
      echo $time > ${HOME}/.working/${1}time
      break
    elif [[ $time =~ ':' ]]
    then
      validate_time $time $1
    fi
  done
}

function get_start_date {
  get_date start
  startdate=$getdate
  echo start date = $startdate
  get_time start
  starttime=$time
  echo start time = $starttime
}

function get_end_date {
  get_date end
  enddate=$getdate
  echo end date = $enddate
  get_time end
  endtime=$time
  echo end time = $endtime
}

function add_schedule {
  line="$startdate $starttime, $enddate $endtime, $screen, $variation"
  echo ""
  schedule_array+=$line
  rebuild_array
  break
}

function get_screen {
  screen_array=$(cat $file | ${jq_path}/jq '.mosaicVariations | keys' | grep '"' | cut -d\" -f2 | while read list
  do
    echo -n "$list "
  done)

  echo -n "Possible screen values are: "
  for i in "${screen_array[@]}"
  do
    echo $i
  done

  echo ""
  until false
  do
    read -p  "Please enter a screen number: " screen
    if [[ $screen != "" ]]
    then
      if [[ " ${screen_array[*]} " =~ " ${screen} " ]]
      then
        echo screen number = $screen
        echo $screen > ${HOME}/.working/screen
        break 
      fi
    fi
  done
}

function get_variation {
  echo screen for variation = $screen
  variation_array=$(cat config.json | ${jq_path}/jq ".mosaicVariations[\"${screen}\"] | keys" | grep '"' | cut -d\" -f2 | while read list
  do
    echo -n "$list "
  done)

  echo -n "Possible screen variations are: "
  for i in "${variation_array[@]}"
  do
    echo $i
  done

  echo ""
  until false
  do
    read -p "Please enter a variation: " var
     
    if [[ $var != "" ]]
    then
      variation=$(echo $var | tr '[:lower:]' '[:upper:]')
      if [[ " ${variation_array[*]} " =~ " ${variation} " ]]
      then 
        echo variation = $variation
        echo $variation > ${HOME}/.working/variation
        break
      fi
    fi
  done
}

function confirm_addition {
  echo ""
  echo "Adding the following schedule: "
  echo ""
  echo Start = $startdate $starttime
  echo End = $enddate $endtime
  echo Screen = $screen
  echo Variation = $variation

  until false
  do
    read -p "Add schedule (y/n): " prompt
     
    response=$(echo $prompt | tr '[:upper:]' '[:lower:]')
    if [[ $response == y ]]
    then
      echo "Adding schedule"
      add_schedule
    elif [[ $response == n ]]
    then
      echo "Not adding schedule"
      break
    fi
  done
}

# Show the currently configured schedules.
function show_schedules {
  clear
  index=1
  for i in "${schedule_array[@]}"
  do
    echo Schedule $index - $i | tr -d '\r'
    index=$(($index+1))
  done
  echo ""
  echo "Press any key to continue."
}

function create_schedule {
  echo "Creating a schedule"
  echo ""
  
  show_schedules
  echo ""
  get_start_date
  get_end_date
  get_screen
  get_variation

  confirm_addition
}

# Delete an existing schedule
function delete_schedule {
  echo "Deleting a schedule"
  echo ""
  show_schedules
  size=$(get_schedule_array_length)
  echo ""
  until false
  do
    size=$(get_schedule_array_length)
    read -p "Select a schedule to delete (or any key to return to main menu): " delete_row
    
    if [[ $size == 1 ]]
    then
      echo ""
      echo "Cannot delete - At least one schdule must exist"
      sleep 3
      break
    elif (( $delete_row >= 1 && $delete_row <= $size ))
    then
      echo ""
      echo "Deleting row $delete_row"
      echo ""
      rebuild_array $delete_row
      show_schedules
      echo ""
    elif [[ $delete_row != [0-9] ]]
    then
      break
    else
      echo "Out of range"
      echo ""
      show_schedules
      echo ""
    fi
  done
}

function confirm_edit {
  startdate=$(cat ${HOME}/.working/startdate)
  starttime=$(cat ${HOME}/.working/starttime)
  enddate=$(cat ${HOME}/.working/enddate)
  endtime=$(cat ${HOME}/.working/endtime)
  screen=$(cat ${HOME}/.working/screen)
  variation=$(cat ${HOME}/.working/variation)
  echo ""
  echo "Altered schedule"
  echo ""
  echo "From:"

  echo ${schedule_array[$1]}
  echo ""
  echo "To: "
  echo $startdate $starttime, $enddate $endtime, $screen, $variation
  line="$startdate $starttime, $enddate $endtime, $screen, $variation"

  until false
  do
    read -p "Are you sure you want to change this schedule (y/n): " prompt
     
    response=$(echo $prompt | tr '[:upper:]' '[:lower:]')
    if [[ $response == y ]]
    then
      echo "Changing schedule"
      schedule_array+=$line
      rebuild_array $1
      break
    elif [[ $response == n ]]
    then
      echo "Not adding schedule"
      break
    fi
  done
}

function schedule_editor {
  echo Editing schdule: ${schedule_array[$schedule]}

  startdate=$(echo ${schedule_array[$schedule]} | cut -d, -f1)
  echo $startdate | awk '{print $1}' > ${HOME}/.working/startdate
  echo $startdate | awk '{print $2}' > ${HOME}/.working/starttime
        
  enddate=$(echo ${schedule_array[$schedule]} | cut -d, -f2 | sed -e"s/^ //" )
  echo $enddate | awk '{print $1}' > ${HOME}/.working/enddate
  echo $enddate | awk '{print $2}' > ${HOME}/.working/endtime
        
  screen=$(echo ${schedule_array[$schedule]} | cut -d, -f3 | tr -d ' ')
  echo $screen > ${HOME}/.working/screen
        
  variation=$(echo ${schedule_array[$schedule]} | cut -d, -f4 | tr -d ' ')
  echo $variation > ${HOME}/.working/variation

  until false
  do
    read -p "Edit start date of $startdate [y/n] " answer
    response=$(echo $answer | tr '[:upper:]' '[:lower:]')
    if [[ $response != "" ]]
    then
      if [[ $response == y ]]
      then
        get_date start
        get_time start
        break
      fi
      if [[ $response == n ]]
      then
        break
      fi
    fi
  done

  until false
  do
    read -p "Edit end date of $enddate [y/n] " answer
    response=$(echo $answer | tr '[:upper:]' '[:lower:]')
    if [[ $response != "" ]]
    then
      if [[ $response == y ]]
      then
        get_date end
        get_time end
        break
      fi
      if [[ $response == n ]]
      then
        break
      fi
    fi
  done

  until false
  do
    screen=$(cat ${HOME}/.working/screen)
    read -p "Edit screen value of $screen [y/n] " answer
    response=$(echo $answer | tr '[:upper:]' '[:lower:]')
    if [[ $response != "" ]]
    then
      if [[ $response == y ]]
      then
        get_screen $screen
        get_variation $variation
        break
      fi
      if [[ $response == n ]]
      then
        break
      fi
    fi
  done

  confirm_edit $schedule
  echo "New schedule:"
  show_schedules
  echo ""
}

# Edit an existing schedule
function edit_schedule {
  size=$(get_schedule_array_length)

  show_schedules

  until false
  do
    read -p "Select a schedule to edit ('l' to relist or 'r' to return to main menu): " schedule
    echo $schedule
    if [[ $schedule == [0-9] ]] && [[ $schedule > 0 ]] && [[ $schedule < $(($size+1)) ]]
    then
      clear
      schedule_editor $schedule
    elif [[ $schedule == 'r' ]]
    then
      break
    elif [[ $schedule == 'l' ]]
    then
      show_schedules
    elif [[ $schedule == [0-9] ]]
    then
      echo "Invalid schedule selection"
    fi
  done
}

# Write out the current schedule
function write_schedule {
  until false
  do
    echo ""
    echo Current Schedule:
    echo ""
    show_schedules
    echo ""
    read -p "Are you sure you want to write this schedule? (y/n) " answer
    echo ""
    response=$(echo $answer | tr '[:upper:]' '[:lower:]')
    if [[ $response != "" ]]
    then
      if [[ $response == y ]]
      then
        schedule_writer
        break
      fi
      if [[ $response == n ]]
      then
        break
      fi
    fi
 done
}

# Start of actually doing stuff
working_directory
build_schedule_array

# Main menu for configuring screen applications
 
while :
do
 clear
 echo "   -- Screen Manager --"
 echo ""
 echo "1. Show current configuration"
 echo "2. Add schedule"
 echo "3. Delete schedule"
 echo "4. Edit schedule"
 echo "5. Publish schedule"
 echo "6. Exit"
 echo ""
 echo -n "Please enter option [1 - 6]: "
 read opt
 case $opt in
   1) echo "************ Configured Schedules *************";
      show_schedules;
      echo "";
      read enterKey;;
   2) echo "*********** Add a Schedule ***********";
      create_schedule ;;
   3) echo "*********** Delete a Schedule ***********";
      delete_schedule ;;
   4) echo "*********** Edit a Schedule ***********";   
      edit_schedule ;;
   5) echo "*********** Write Schedule ***********";  
      write_schedule ;;
   6) echo "Bye $USER";
      rm -rf $HOME/.working
      exit;;
   *) echo "Invaild option. Please select an above option";
      echo "Press [enter] key to continue. . .";
      read enterKey;;
esac
done
