#!/usr/bin/env bash
conf_file="conf.json"
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

## Functions Section
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

  jq --arg key "${1}" --arg value "${new_value}" --arg timestamp "$(date +%s)" '. + {($key): $value, updatedat: $timestamp}' $conf_file > $tmp_file  
  mv "${tmp_file}" "${conf_file}"
}
jq_get_define()
{
  if [ $(jq_exists "${1}") == true ]; then
    jq_get "${1}"
  else
    jq_set "${1}"
    jq_get "${1}"
  fi
}

# Read the variables from the file using jq
group=$(jq_get_define 'group')
tolerance=$(jq_get_define 'tolerance')
cust_command=$(jq_get_define 'cust_command')
# End of User Defined Variables

tol_sec=$(( $tolerance *60 ))
day=""
status=0
curl -s https://raw.githubusercontent.com/nickkossolapov/pta-load-shedding/master/scripts/data.json --output data.json
get_status(){
  local timestamp=$(jq_get "updatedat")
  local timestamp_end=$(($timestamp+$tol_sec))
  local current_timestamp=$(date +%s)
  if [ $current_timestamp -gt $timestamp_end ]; then
    echo "Updating status"
    timestamp=$(TZ=Africa/Johannesburg date +%s%N | cut -b1-13)
    cur_hour=$(TZ=Africa/Johannesburg date +%-H)
    cur_min=$(TZ=Africa/Johannesburg date +%-M)
    cur_time=$(( ${cur_hour} * 60 * 60 + ${cur_min} * 60 ))
    day=$(TZ=Africa/Johannesburg date +%-d)
    status=$(curl -s https://loadshedding.eskom.co.za/LoadShedding/GetStatus?_=${timestamp})
    # check if the status returned is an integer
    if ! [[ $status =~ ^[0-9]+$ ]]; then
      status=0
    fi
    jq_set "status" "${status}"
  else
    status=$(jq_get "status")
  fi
  echo "timestamp: ${timestamp}"
  echo "Current Hour: ${cur_hour}"
  echo "Current Min: ${cur_min}"
  echo "Day: ${day}"
}
retries=0
while [ "${status}" -lt 1 -a "${retries}" -lt 3 ]
do
  get_status
  echo $status
  ((retries=$retries+1))
done
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
exit
stage=$(( $status - 1 ))
x=1
time_slots=()
start_times=()
while [ $x -le $stage ]
do
  query=$(jq -r --arg group ${group} --arg stage ${x} --arg day ${day} '.[$group] | .[$stage] | .[$day][0]' data.json)
  if [ "$query" != "null" ];
    then time_slots+=("${query}");
    end_time=($(echo ${query} | awk -F ' - ' '{print $2}'));
    end_times+=("${end_time}");
    time=($(echo ${query} | awk -F ' - ' '{print $1}'));
    start_times+=("${time}");
    temp=$(echo ${time} | awk -F':' '{print $1 * 60 * 60 + $2 * 60 + $3}');
    if (( "$cur_time" >= "(( ${temp} - ${tol_sec} ))" && "$cur_time" <=   "(( ${temp} + ${tol_sec} ))" ));
      then $("${cust_command}");
    fi
  fi
  x=$(( $x + 1 ))
done





