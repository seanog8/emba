#!/bin/bash

# emba - EMBEDDED LINUX ANALYZER
#
# Copyright 2020-2021 Siemens AG
# Copyright 2020-2021 Siemens Energy AG
#
# emba comes with ABSOLUTELY NO WARRANTY. This is free software, and you are
# welcome to redistribute it under the terms of the GNU General Public License.
# See LICENSE file for usage of this software.
#
# emba is licensed under GPLv3
#
# Author(s): Michael Messner, Pascal Eckmann

# Description:  Searches for files with a specified string pattern inside.

S106_deep_key_search()
{
  module_log_init "${FUNCNAME[0]}"
  module_title "Deep analysis of files for private keys"

  local PATTERNS
  PATTERNS="$(config_list "$CONFIG_DIR""/deep_key_search.cfg" "")"

  readarray -t PATTERN_LIST < <(printf '%s' "$PATTERNS")

  for PATTERN in "${PATTERN_LIST[@]}";do
    print_output "[*] Pattern: $PATTERN"
  done

  OCC_LIST=()

  deep_key_search
  deep_key_reporter

  module_end_log "${FUNCNAME[0]}" "${#OCC_LIST[@]}"
}

deep_key_search() {
  local WAIT_PIDS_S106=()
  GREP_PATTERN_COMMAND=()
  for PATTERN in "${PATTERN_LIST[@]}" ; do
    GREP_PATTERN_COMMAND=( "${GREP_PATTERN_COMMAND[@]}" "-e" ".{0,15}""$PATTERN"".{0,15}" )
  done
  echo
  for DEEP_S_FILE in "${FILE_ARR[@]}"; do
    if [[ $THREADED -eq 1 ]]; then
      deep_key_searcher &
      WAIT_PIDS_S106+=( "$!" )
    else
      deep_key_searcher
    fi
  done

  if [[ $THREADED -eq 1 ]]; then
    wait_for_pid "${WAIT_PIDS_S106[@]}"
  fi
}

deep_key_searcher() {
  if [[ -e "$DEEP_S_FILE" ]] ; then
    local S_OUTPUT
    readarray -t S_OUTPUT < <(grep -A 2 -E -n -a -h "${GREP_PATTERN_COMMAND[@]}" -D skip "$DEEP_S_FILE" | tr -d '\0' | cut -c-100)
    if [[ ${#S_OUTPUT[@]} -gt 0 ]] ; then
      echo "[+] $DEEP_S_FILE" >> "$LOG_PATH_MODULE"/deep_key_search_"$(basename "$DEEP_S_FILE")"".txt"
      for DEEP_S_LINE in "${S_OUTPUT[@]}" ; do
        DEEP_S_LINE="$( echo "$DEEP_S_LINE" | tr "\000-\037\177-\377" "." )"
        echo "$DEEP_S_LINE" >> "$LOG_PATH_MODULE"/deep_key_search_"$(basename "$DEEP_S_FILE")"".txt"
      done
      local D_S_FINDINGS=""
      for PATTERN in "${PATTERN_LIST[@]}" ; do
        F_COUNT=$(grep -c "$PATTERN" "$LOG_PATH_MODULE"/deep_key_search_"$(basename "$DEEP_S_FILE")"".txt" )
        if [[ $F_COUNT -gt 0 ]] ; then
          D_S_FINDINGS="$D_S_FINDINGS""    ""$F_COUNT""\t:\t""$PATTERN""\n"
        fi
      done
      # we have to write the file link manually, because threading is messing with the file (wrong order of entries and such awful stuff)
      OLD_LOG_FILE="$LOG_FILE"
      LOG_FILE="$LOG_PATH_MODULE""/deep_key_search_tmp_""$(basename "$DEEP_S_FILE")"".txt"
      print_output "[+] ""$DEEP_S_FILE" 
      write_link "$LOG_PATH_MODULE""/deep_key_search_""$(basename "$DEEP_S_FILE")"".txt"
      print_output "$D_S_FINDINGS" 
      cat "$LOG_FILE" >> "$OLD_LOG_FILE"
      rm "$LOG_FILE" 2> /dev/null
      LOG_FILE="$OLD_LOG_FILE"
    fi
  fi
}

deep_key_reporter() {
  for PATTERN in "${PATTERN_LIST[@]}" ; do
    P_COUNT=$(grep -c "$PATTERN" "$LOG_PATH_MODULE"/deep_key_search_* 2>/dev/null | cut -d: -f2 | awk '{ SUM += $1} END { print SUM }' )
    OCC_LIST=( "${OCC_LIST[@]}" "$P_COUNT"": ""$PATTERN" )
  done

  if [[ "${#PATTERN_LIST[@]}" -gt 0 ]] ; then
    print_output ""
    print_output "[*] Occurences of pattern:"
    SORTED_OCC_LIST=("$(printf '%s\n' "${OCC_LIST[@]}" | sort -r --version-sort)")
    for OCC in "${SORTED_OCC_LIST[@]}"; do
      print_output "$( indent "$(orange "$OCC" )")""\n"
    done
  fi
}
