#!/bin/bash
# Multi folder sync

DEBUG=1
usage="Usage: $0 -t [server|client|count]"

# Close background tasks when exiting
trap "exit" INT TERM ERR
trap "kill 0" EXIT

# Check if script is run with argument
if [[ $# -eq 0 ]]; then
  echo "No arguments given."; echo $usage; exit 1;
fi

# Read given argument
while getopts ':ht:' arg; do
  case "$arg" in
  h)
    echo $usage
    ;;
  :)
    echo "You must use an argument with -$OPTARG."
    exit 1
    ;;
  t)
    task="$OPTARG"
    [ $DEBUG -eq 1 ] && echo "Task= $OPTARG"
    ;;
  ?)
    echo "Invalid option: -$OPTARG."
    exit 1
    ;;
  esac
done
#shift "$(($OPTIND -1))"

# Script roles
case $task in
  # Server segment
  server)
    # Get info from user
    read -p "Port for receiving: " port
    read -p "Folder to receive in: " folder
    
    # Set default data if non provided and condition the data
    setport="${port:-9090}"
    tempfolder="${folder:-./}"
    setfolder="${tempfolder%/}"
    
    # If port is not a number, exit
    [[ ! "$setport" =~ ^[0-9]+$ ]] && { echo "Port is not a number"; exit 1; }
    # Check folder exists and is writable, else exit
    [ -d "$setfolder" -a -w "$setfolder/" ] && echo "Folder found and writable" || { echo "Can't write to folder"; exit 1; }
    
    [ $DEBUG -eq 1 ] && echo "Port= $setport"
    [ $DEBUG -eq 1 ] && echo "Folder= $setfolder"
    
#    echo "Starting receiving server..."
#    nc -l -p $setport | pv | tar -C $setfolder -x

    echo "Server start on port $setport"
    rm -f out
    mkfifo out # TODO fifo in /tmp
    trap "rm -f out" EXIT
    while :; do
    # Parse netcat output, to build the answer redirected to the pipe "out".
    cat out | nc -w3 -l $setport > >(
      export REQUEST=
      # Listen for incoming requests
      while read line; do
        # Transform request into one-liner
        line=$(echo "$line" | tr -d '[\r\n]')
        [ $DEBUG -eq 1 ] && echo "Request line=" $line
        
        # Check if request is GET
        if echo "$line" | grep -qE '^GET /'; then
          # Extract the request
          REQUEST=$(echo "$line" | cut -d ' ' -f2)
          [ $DEBUG -eq 1 ] && echo "Request full item=" $REQUEST
          # Strip first character (/)
          RequestNumber=${REQUEST:1}
          [ $DEBUG -eq 1 ] && echo "Request trimmed item=" $RequestNumber
          
        # Empty line / end of request
        elif [ "x$line" = x ]; then
          HTTP_200="HTTP/1.1 200 OK"
          HTTP_404="HTTP/1.1 404 Not Found"
          HTTP_LOCATION="Location:"
          [ $DEBUG -eq 1 ] && echo "Request processed"
          
          # Check if the request is a number
          if [[ "$RequestNumber" =~ ^[0-9]+$ ]]; then
            printf "%s\n%s %s\n\n%s\n" "$HTTP_200" "$HTTP_LOCATION" > out
          [ $DEBUG -eq 1 ] && echo "Request on=" $REQUEST
            
            ### Start server receivers
# BG process monitor implementeren
            for (( i=1; i<=$RequestNumber; i++ )); do
              # Start on total required ports
              ncport=$(($setport + $i))
              echo "Starting receiver for $setfolder on: $ncport"
              nc -l -p $ncport | tar -C $setfolder -x &
            done
            
          elif echo $REQUEST | grep -qE '^/stop'; then
            printf "%s\n%s %s\n\n%s\n" "$HTTP_200" "$HTTP_LOCATION" > out
            [ $DEBUG -eq 1 ] && echo "Request on=" $REQUEST
            
## TODO Stop server NC background tasks
            
          elif echo $REQUEST | grep -qE '^/stats'; then
            printf "%s\n%s %s\n\n%s\n" "$HTTP_200" "$HTTP_LOCATION" > out
            [ $DEBUG -eq 1 ] && echo "Request on=" $REQUEST
            
            du -hs $setfolder > out
            
          elif echo $REQUEST | grep -qE '^/'; then
            printf "%s\n%s %s\n\n%s\n" "$HTTP_200" "$HTTP_LOCATION" > out
            [ $DEBUG -eq 1 ] && echo "Request on / =" $REQUEST
            
            echo $usage > out
            echo "http:// URL /stats" > out
            
          else
            printf "%s\n%s %s\n\n%s\n" "$HTTP_404" "$HTTP_LOCATION" $REQUEST "Not Found" > out
            [ $DEBUG -eq 1 ] && echo "Request 404=" $REQUEST
          fi
        fi
      done
    )
  done
  ;;
  # Client segment
  client)
    read -p "IP of server: " ip
    read -p "Port of server: " port
    read -p "Folder to send: " folder
    read -p "Depth of index [0/1/2]: " depth
    
    # Set port 9090 if none given
    setport="${port:-9090}"
    # Set current directory is none given
    setfolder="${folder:-./}"
    depthoptions=(0 1 2)
    # Check depth with: -Fixed-strings, -eXact-match, -Quite-output, -Zero-byte-end
    [ printf '%s\0' "${depthoptions[@]}" | grep -Fxqz "$depth" ] && setdepth=$depth || $setdepth=0
    
    # Check $setport is number
    [[ ! "$setport" =~ ^[0-9]+$ ]] && { echo "Port is not a number"; exit 1; }
    # Check folder exists and is readable, else exit
    [ -d "$setfolder" -a -r "$setfolder" ] && echo "Folder found and readable" || { echo "Can't read from folder"; exit 1; }
    
    [ $DEBUG -eq 1 ] && echo "Server IP= $ip"
    [ $DEBUG -eq 1 ] && echo "Port= $setport"
    [ $DEBUG -eq 1 ] && echo "Folder= $setfolder"
    [ $DEBUG -eq 1 ] && echo "Depth= $setdepth"
    
    case $setdepth in
      0)
        echo "Pinging server..."
        serverConnect=$(curl -o /dev/null --silent --get --write-out '%{http_code}\n' $ip:$setport/1)
        if [[ $serverConnect == "200" ]]; then
          echo "Starting sending client..."
          sleep 1
          tar -C $setfolder -cf - . | pv -s $(du -sb . | awk '{print $1}') | nc $ip $setport
          echo "Reached end of data"
        elif [[ $serverConnect == "404" ]]; then
          echo "Server gave a 404 Not Found. Something went wrong"; exit
        else echo "Couldn't find the server. Tried on $serverip:$port"
        fi
      ;;
      1)
        # Read directories into array
        readarray -t manifestd < <(find $setfolder -maxdepth 1 -type d)
        # Read 1st lvl files into array
        readarray -t manifestf < <(find $setfolder -maxdepth 1 -type f)
        
        # Removing setfolder from manifestd
        for ((i=0; i<=${#manifestd[@]}; i++)); do
          [[ ${manifestd[$i]} == $setfolder ]] && unset 'manifestd[$i]' || { manifestd=( "${manifestd[@]/"$setfolder/"}" ); } # TODO check last part
        done
        
        # Set counter for transfertunnels
        manifestcount=${#manifestd[@]}
        # If there are files, add 1 transfertunnel
        [ "${#manifestd[@]}" -gt "0" ] && manifestcount=$(( $manifestcount + 1 ));
        
        echo "Pinging server..."
        serverConnect=$(curl -o /dev/null --silent --get --write-out '%{http_code}\n' $ip:$setport/$manifestcount)
        if [[ $serverConnect == "200" ]]; then
          echo "Starting sending client folders..."
###          

          
        elif [[ $serverConnect == "404" ]]; then
          echo "Server gave a 404 Not Found. Something went wrong"; exit
        else echo "Couldn't find the server. Tried on $serverip:$port"
        fi
      ;;
      2)
      
        
      ;;
      *)
        echo "Something went wrong with the folder depth"; exit 1;
      ;;
    esac
    

  ;;
  count)
    read -p "Folder to count: " folder
    
    setfolder="${folder:-./}"

    [ -d "$setfolder" -a -r "$setfolder" ] && echo "Folder found and readable" || { echo "Can't read from folder"; }
    
    [ $DEBUG -eq 1 ] && echo "Folder= $setfolder"
    
    du -hs $setfolder
    ;;
  *)
    
  ;;
esac





#####
#####
#####


    
  elif [ "$4" == 2 ]; then
    [ $DEBUG -eq 1 ] && echo "Depth=" $4
    # List only files in top & x lvl deep
    readarray -t manifestf < <(find $rootFolder -maxdepth $4 -type f -printf '%P\n')
    # List only dirs in top & x lvl deep
    readarray -t manifest1 < <(find $rootFolder -mindepth $4 -maxdepth $4 -type d -printf '%P\n')
    # List empty dirs in top & x lvl deep
    readarray -t manifest2 < <(find $rootFolder -maxdepth $4 -type d -empty -printf '%P\n')
    
    readarray -t manifestd < <(printf '%s\n' "${manifest1[@]}" "${manifest2[@]}" | sort -u)

    [ $DEBUG -eq 1 ] && echo "Manifestf=" $(printf "'%s' " "${manifestf[@]}")
    [ $DEBUG -eq 1 ] && echo "Manifest1=" $(printf "'%s' " "${manifest1[@]}")
    [ $DEBUG -eq 1 ] && echo "Manifest2=" $(printf "'%s' " "${manifest2[@]}")
    [ $DEBUG -eq 1 ] && echo "Manifestd=" $(printf "'%s' " "${manifestd[@]}")
    

client)
  echo "Client start"
  # Check if there are files indexed
# TODO fix read for 0 and the TRUE state
  if (( ${#manifestf[@]} )); then
    # Add one for a transfer
    manifestCount=$((${#manifestd[@]}+1))
  else manifestCount=${#manifest[@]}
  fi
  echo "Total transfers awaiting:" $manifestCount
  # Get server IP
  echo "Enter the server IP:"
  read serverip
  [ $DEBUG -eq 1 ] && echo "Provided IP=" $serverip
  # Ping server with total transfers
  serverConnect=$(curl -o /dev/null --silent --get --write-out '%{http_code}\n' $serverip:$port/$manifestCount)
# TODO Fetch server data, like available disk space
  
  if [[ $serverConnect == "200" ]]; then
    echo "Server found!"
    sleep 1
    
    ### Start client senders
    # For all folders, start transfer on its own port
    for ((i=0; i<${#manifest[@]}; i++)); do
      [ $DEBUG -eq 1 ] && echo "i=" $i
      
      # Set port for sender
      ncport=$(($port + $i + 1))
      [ $DEBUG -eq 1 ] && echo "NC port=" $ncport
      
      echo "Start sender for ${manifestd[$i]} on $ncport"
      # Start tar piped through NetCat
#      (cd ${manifestd[$i]} && tar -cf - * | nc $serverip $ncport &)
#      tar -cf - ${manifestd[$i]} | nc $serverip $ncport &
      sleep 1
    done
