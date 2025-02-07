#!/bin/bash

# emba - EMBEDDED LINUX ANALYZER
#
# Copyright 2020-2021 Siemens Energy AG
# Copyright 2020-2021 Siemens AG
#
# emba comes with ABSOLUTELY NO WARRANTY. This is free software, and you are
# welcome to redistribute it under the terms of the GNU General Public License.
# See LICENSE file for usage of this software.
#
# emba is licensed under GPLv3
#
# Author(s): Michael Messner, Pascal Eckmann

# Description:  Iterates through a static list with version details layout 
#               (e.g. busybox:binary:"BusyBox\ v[0-9]\.[0-9][0-9]\.[0-9]\ .*\ multi-call\ binary" ) of all executables and 
#               checks if these fit on a binary in the firmware. 

# Threading priority - if set to 1, these modules will be executed first
export THREAD_PRIO=1

S09_firmware_base_version_check() {

  # this module check for version details statically.
  # this module is designed for *x based systems
  # for other systems (eg RTOS) we have the R09

  module_log_init "${FUNCNAME[0]}"
  module_title "Binary firmware versions detection"

  EXTRACTOR_LOG="$LOG_DIR"/p05_firmware_bin_extractor.txt

  print_output "[*] Static version detection running ..." | tr -d "\n"
  while read -r VERSION_LINE; do
    echo "." | tr -d "\n"

    STRICT="$(echo "$VERSION_LINE" | cut -d: -f2)"
    BIN_NAME="$(echo "$VERSION_LINE" | cut -d: -f1)"

    # as we do not have a typical linux executable we can't use strict version details
    # but to not exhaust the run time we only search for stuff that we know is possible to detect
    # on the other hand, if we do not use emulation for deeper detection we run all checks

    VERSION_IDENTIFIER="$(echo "$VERSION_LINE" | cut -d: -f3- | sed s/^\"// | sed s/\"$//)"

    if [[ $STRICT != "strict" ]]; then
      echo "." | tr -d "\n"

      # check binwalk files sometimes we can find kernel version information or something else in it
      VERSION_FINDER=$(grep -o -a -E "$VERSION_IDENTIFIER" "$EXTRACTOR_LOG" 2>/dev/null | head -1 2>/dev/null)
      if [[ -n $VERSION_FINDER ]]; then
        echo ""
        print_output "[+] Version information found ${RED}""$VERSION_FINDER""${NC}${GREEN} in binwalk logs."
        echo "." | tr -d "\n"
      fi
      
      echo "." | tr -d "\n"

      if [[ $FIRMWARE -eq 0 || -f $FIRMWARE_PATH ]]; then
        VERSION_FINDER=$(find "$FIRMWARE_PATH" -xdev -type f -print0 2>/dev/null | xargs -0 strings | grep -o -a -E "$VERSION_IDENTIFIER" | head -1 2>/dev/null)

        if [[ -n $VERSION_FINDER ]]; then
          echo ""
          print_output "[+] Version information found ${RED}""$VERSION_FINDER""${NC}${GREEN} in original firmware file (static)."
        fi  
        echo "." | tr -d "\n"
      fi  

      if [[ "$THREADED" -eq 1 ]]; then
        MAX_THREADS_S09=$((7*"$(grep -c ^processor /proc/cpuinfo)"))
        if [[ $(grep -c S115_ "$LOG_DIR"/"$MAIN_LOG_FILE") -eq 1 ]]; then
          MAX_THREADS_S09=$((4*"$(grep -c ^processor /proc/cpuinfo)"))
        fi
        #print_output "[*] Max threads for static version detection: $MAX_THREADS_S09"

        # this will burn the CPU but in most cases the time of testing is cut into half
        bin_string_checker &
        WAIT_PIDS_S09+=( "$!" )
      else
        bin_string_checker
      fi

     echo "." | tr -d "\n"
    else
      if [[ $RTOS -eq 1 ]]; then
        continue
      fi

      mapfile -t STRICT_BINS < <(find "$OUTPUT_DIR" -xdev -executable -type f -name "$BIN_NAME" -exec md5sum {} \; 2>/dev/null | sort -u -k1,1 | cut -d\  -f3)
      for BIN in "${STRICT_BINS[@]}"; do
        # as the STRICT_BINS array could also include executable scripts we have to check for ELF files now:
        if file "$BIN" | grep -q ELF ; then
          VERSION_FINDER=$(strings "$BIN" | grep -E "$VERSION_IDENTIFIER" | sort -u)
          if [[ -n $VERSION_FINDER ]]; then
            echo ""
            print_output "[+] Version information found ${RED}$BIN_NAME $VERSION_FINDER${NC}${GREEN} in binary $ORANGE$(print_path "$BIN")$GREEN (static - strict)."
            continue
          fi
        fi
      done
      echo "." | tr -d "\n"
    fi

    if [[ "${#WAIT_PIDS_S09[@]}" -gt "$MAX_THREADS_S09" ]]; then
      recover_wait_pids "${WAIT_PIDS_S09[@]}"
      if [[ "${#WAIT_PIDS_S09[@]}" -gt "$MAX_THREADS_S09" ]]; then
        max_pids_protection "$MAX_THREADS_S09" "${WAIT_PIDS_S09[@]}"
      fi
    fi

  done  < "$CONFIG_DIR"/bin_version_strings.cfg

  echo "." | tr -d "\n"

  if [[ "$THREADED" -eq 1 ]]; then
    wait_for_pid "${WAIT_PIDS_S09[@]}"
  fi

  VERSIONS_DETECTED=$(grep -c "Version information found" "$( get_log_file )")

  module_end_log "${FUNCNAME[0]}" "$VERSIONS_DETECTED"
}

bin_string_checker() {
  for BIN in "${FILE_ARR[@]}"; do
    if [[ $RTOS -eq 1 ]]; then
      BIN_FILE=$(file "$BIN")
      # as the FILE_ARR array also includes non binary stuff we have to check for relevant files now:
      if ! [[ "$BIN_FILE" == *uImage* || "$BIN_FILE" == *Kernel\ Image* || "$BIN_FILE" == *ELF* ]] ; then
        continue
      fi
      if [[ "$BIN_FILE" == *ELF* ]] ; then
        VERSION_FINDER=$(strings "$BIN" | grep -o -a -E "$VERSION_IDENTIFIER" | head -1 2> /dev/null)
        if [[ -n $VERSION_FINDER ]]; then
          echo ""
          print_output "[+] Version information found ${RED}$VERSION_FINDER${NC}${GREEN} in binary $ORANGE$(print_path "$BIN")$GREEN (static)."
          continue
        fi
      elif [[ "$BIN_FILE" == *uImage* || "$BIN_FILE" == *Kernel\ Image* ]] ; then
        VERSION_FINDER=$(strings "$BIN" | grep -o -a -E "$VERSION_IDENTIFIER" | head -1 2> /dev/null)
        if [[ -n $VERSION_FINDER ]]; then
          echo ""
          print_output "[+] Version information found ${RED}$VERSION_FINDER${NC}${GREEN} in kernel image $ORANGE$(print_path "$BIN")$GREEN (static)."
          continue
        fi
      fi
    else
      VERSION_FINDER=$(strings "$BIN" | grep -o -a -E "$VERSION_IDENTIFIER" | head -1 2> /dev/null)
      if [[ -n $VERSION_FINDER ]]; then
        echo ""
        print_output "[+] Version information found ${RED}$VERSION_FINDER${NC}${GREEN} in binary $ORANGE$(print_path "$BIN")$GREEN (static)."
        continue
      fi
    fi
  done
}

recover_wait_pids() {
  local TEMP_PIDS=()
  local PID
  # check for really running PIDs and re-create the array
  for PID in ${WAIT_PIDS_S09[*]}; do
    #print_output "[*] max pid protection: ${#WAIT_PIDS[@]}"
    if [[ -e /proc/"$PID" ]]; then
      TEMP_PIDS+=( "$PID" )
    fi
  done
  #print_output "[!] S09 - really running pids: ${#TEMP_PIDS[@]}"

  # recreate the arry with the current running PIDS
  WAIT_PIDS_S09=()
  WAIT_PIDS_S09=("${TEMP_PIDS[@]}")
}

