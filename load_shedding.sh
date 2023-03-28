#!/usr/bin/env bash

## Define Variables
conf_file="conf.json"
timestamp=$(date +%s)
day=$(date +%d)
status=0
uptime=$(awk '{print $1}' /proc/uptime)

## Define functions
conf_exists()
{
  # Check if the file exists
  if [ ! -f $conf_file ]; then
    # If the file doesn't exist, ask the user if they want to create it
    read -p "The file '${conf_file}' doesn't exist. Do you want to create it? [y/n] " answer
    if [[ $answer =~ ^[Yy]$ ]]; then
      # Create an empty JSON object and write it to the file
      echo "{}" > $conf_file
    else
      # Exit the script if the user doesn't want to create the file
      exit 1
    fi
  fi
}

jq_exists()
{
  jq -r ". | has(\"${1}\")" $conf_file
}
jq_get()
{
  jq -r ".${1}" $conf_file
}
jq_set()
{
  local tmp_file=$(mktemp)

  # Check if an argument was supplied
  if [ $# -eq 2 ]; then
    new_value=$2
  else
    # Prompt the user for a new variable value
    read -p "Enter value for ${1}: " new_value
  fi
  jq --arg key "${1}" --arg value "${new_value}" --arg timestamp "$(date +%s)" --arg ts_expires "$(date -d "+ ${update_int}" +%s)" '. + {($key): $value, updated_at: $timestamp, expires_at: $ts_expires}' $conf_file > $tmp_file  
  mv "${tmp_file}" "${conf_file}"
}
jq_get_define()
{
  if [ $(jq_exists "${1}") == true ]; then
    jq_get "${1}"
  else
    jq_set "${@}"
    jq_get "${1}"
  fi
}

custom_command()
{
  cmd_ts=$(date -d "${1}" +%s)
  #If forced run the command now
  if [ $# -gt 1 ]; then
    echo "Running ${cust_command} now"
    $cust_command now
  elif [ "$cmd_ts" -ne "$next_cmd_run" ]; then
    #If scheduled then schedule the command and jq_set next_cmd_run to timestamp
    jq_set "next_cmd_run" $cmd_ts
    echo "${cust_command} scheduled for ${1}"
    $cust_command ${1}
  fi
}

## User Defined Variables
# Read the variables from the file using jq
conf_read()
{
  conf_exists
  group=$(jq_get_define 'group')
  tolerance=$(jq_get_define 'tolerance')
  offset=$(jq_get_define 'offset')
  update_int=$(jq_get_define 'update_interval')
  updated_at=$(jq_get 'updated_at')
  expires_at=$(jq_get 'expires_at')
  cust_command=$(jq_get_define 'cust_command')
  last_status=$(jq_get_define 'status' '0')
  next_cmd_run=$(jq_get_define 'next_cmd_run' '0')
}
## End of User Defined Variables

# Check if config file exists
conf_read
# Get all the start times of every stage including and below current as a list of
get_status()
{
  local retries=0
  #Check if force update or old status still vailid
  if [ "$#" -eq 0 ] && [ "$expires_at" -gt "$timestamp" ]; then
    # Return old status
    status="$last_status"
  else
    while [ "$status" -eq 0 ] && [ "$retries" -lt 3 ]; do
      status=$(curl -s "https://loadshedding.eskom.co.za/LoadShedding/GetStatus?_=$(date +%s)")
      if [[ $status =~ ^[0-9]+$ ]]; then
        jq_set "status" "${status}"
        break
      fi
      status=0
      ((retries++))
    done
  fi
}

print_status()
{
  #Print out current stage
  case $status in
  
    1)
      echo "Currently not load shedding"
      ;;
  
    2)
      echo "Currently Stage 1"
      ;;
  
    3)
      echo "Currently Stage 2"
      ;;
  
    4)
      echo "Currently Stage 3"
      ;;
  
    5)
      echo "Currently Stage 4"
      ;;
  
    6)
      echo "Currently Stage 5"
      ;;
  
    7)
      echo "Currently Stage 6"
      ;;
  
    8)
      echo "Currently Stage 7"
      ;;
  
    9)
      echo "Currently Stage 8"
      ;;
  esac
}

#Check if time now is on the hour
if [ "$(date -d "@${timestamp}" +%M)" == "00" ]; then
  get_status true
else
  get_status
fi

#If the status is 0 and last_status 0 then exit
if [ $status -eq 0 ] && [ $last_status -eq 0 ]; then
  echo "Unable to get status"
  exit 1
fi

#If the status is 0 and last_status not 0 set status to last_status
if [ "$status" -eq 0 ] && [ "$last_status" -ne 0 ]; then
  status=$last_status
fi

#Check if last stutus lower than current and if cmd_run timestamp greater than ts
if [ "$last_status" -gt "$status" ] && [ "$timestamp" -lt "$next_cmd_run" ]; then
  echo "Canceling previous ${cust_command}"
  $cust_command -c
fi

#Print status change
if [ "$last_status" != "$status" ]; then
  print_status
fi

#Go through each stage till current stage
x=1
stage=$(( status-1 ))
day=$(date +%-d)
time_slots=()
while [ "$x" -lt "$status" ]; do
  query=$(jq -r --arg group ${group} --arg stage ${x} --arg day ${day} '.[$group] | .[$stage] | .[$day][0]' data.json)
  if [ "$query" != "null" ]; then
    start_time=$(echo ${query} | awk -F ' - ' '{print $1}')
    start_hour=$(date -d "${start_time}" +%H)
    tolerance_ts=$(date -d "${start_hour} - ${tolerance}" +%s)
    command_at=$(date -d "${start_hour} - ${offset}" +%H:%M)
    command_start=$(date -d "${start_hour} - ${offset}" +%s)
    command_end=$(date -d "${start_hour} + ${offset}" +%s)
    boot_tol=$(date -d "+ ${offset} - $uptime seconds" +%s)
    if [ "$timestamp" -ge "$tolerance_ts" ] && [ "$timestamp" -le "$command_end" ] && [ "$timestamp" -gt "$boot_tol" ]; then
      if [ "$timestamp" -ge "$command_start" ]; then
        # Emergency command run
        custom_command ${command_at} true
      else
        # Normal command run
        custom_command ${command_at}
      fi
    fi
  fi
  ((x++))
done
exit 0