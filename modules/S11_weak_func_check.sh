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

# Description:  This module was the first module that existed in emba. The main idea was to identify the binaries that were using weak 
#               functions and to establish a ranking of areas to look at first.
#               It iterates through all executables and searches with objdump for interesting functions like strcpy (defined in helpers.cfg). 

S11_weak_func_check()
{
  module_log_init "${FUNCNAME[0]}"
  module_title "Check binaries for weak functions (intense)"

  LOG_FILE="$( get_log_file )"

  # OBJDMP_ARCH, READELF are set in dependency check
  # Test source: https://security.web.cern.ch/security/recommendations/en/codetools/c.shtml

  VULNERABLE_FUNCTIONS="$(config_list "$CONFIG_DIR""/functions.cfg")"
  print_output "[*] Vulnerable functions: ""$( echo -e "$VULNERABLE_FUNCTIONS" | sed ':a;N;$!ba;s/\n/ /g' )""\\n"
  IFS=" " read -r -a VULNERABLE_FUNCTIONS <<<"$( echo -e "$VULNERABLE_FUNCTIONS" | sed ':a;N;$!ba;s/\n/ /g' )"

  STRCPY_CNT=0
  for LINE in "${BINARIES[@]}" ; do
    if ( file "$LINE" | grep -q ELF ) ; then
      NAME=$(basename "$LINE" 2> /dev/null)
      # create disassembly of every binary file:
      #"$OBJDUMP" -d "$LINE" > "$OBJDUMP_LOG"

      if ( file "$LINE" | grep -q "x86-64" ) ; then
        if [[ "$THREADED" -eq 1 ]]; then
          function_check_x86_64 &
          WAIT_PIDS_S11+=( "$!" )
        else
          function_check_x86_64
        fi
      elif ( file "$LINE" | grep -q "Intel 80386" ) ; then
        if [[ "$THREADED" -eq 1 ]]; then
          function_check_x86 &
          WAIT_PIDS_S11+=( "$!" )
        else
          function_check_x86
        fi
      elif ( file "$LINE" | grep -q "32-bit.*ARM" ) ; then
        if [[ "$THREADED" -eq 1 ]]; then
          function_check_ARM32 &
          WAIT_PIDS_S11+=( "$!" )
        else
          function_check_ARM32
        fi
      elif ( file "$LINE" | grep -q "64-bit.*ARM" ) ; then
        # ARM 64 code is in alpha state and nearly not tested!
        if [[ "$THREADED" -eq 1 ]]; then
          function_check_ARM64 &
          WAIT_PIDS_S11+=( "$!" )
        else
          function_check_ARM64
        fi
      elif ( file "$LINE" | grep -q "MIPS" ) ; then
        if [[ "$THREADED" -eq 1 ]]; then
          function_check_MIPS32 &
          WAIT_PIDS_S11+=( "$!" )
        else
          function_check_MIPS32
        fi
      elif ( file "$LINE" | grep -q "PowerPC" ) ; then
        if [[ "$THREADED" -eq 1 ]]; then
          function_check_PPC32 &
          WAIT_PIDS_S11+=( "$!" )
        else
          function_check_PPC32
        fi
      else
        print_output "[-] Something went wrong ... no supported architecture available"
      fi
    fi
  done

  if [[ "$THREADED" -eq 1 ]]; then
    wait_for_pid "${WAIT_PIDS_S11[@]}"
  fi

  print_top10_statistics

  if [[ -f "$TMP_DIR"/S11_STRCPY_CNT.tmp ]]; then
    while read -r STRCPY; do
      (( STRCPY_CNT="$STRCPY_CNT"+"$STRCPY" ))
    done < "$TMP_DIR"/S11_STRCPY_CNT.tmp
  fi

  # shellcheck disable=SC2129
  write_log ""
  write_log "[*] Statistics:$STRCPY_CNT"
  write_log ""
  write_log "[*] Statistics1:$ARCH"

  module_end_log "${FUNCNAME[0]}" "${#RESULTS[@]}"
}

function_check_PPC32(){
  for FUNCTION in "${VULNERABLE_FUNCTIONS[@]}" ; do
    if ( readelf -r "$LINE" | awk '{print $5}' | grep -E -q "^$FUNCTION" 2> /dev/null ) ; then
      NAME=$(basename "$LINE" 2> /dev/null)
      if [[ "$FUNCTION" == "mmap" ]] ; then
        # For the mmap check we need the disasm after the call
        mapfile -t OBJ_DUMPS_ARR < <("$OBJDUMP" -d "$LINE" | grep -E -A 20 "bl.*<$FUNCTION" 2> /dev/null)
      else
        mapfile -t OBJ_DUMPS_ARR < <("$OBJDUMP" -d "$LINE" | grep -E -A 2 -B 20 "bl.*<$FUNCTION" 2> /dev/null)
      fi
      if [[ "$OBJ_DUMPS_OUT" != *"file format not recognized"* && "${#OBJ_DUMPS_ARR[@]}" -gt 0 ]] ; then
        FUNC_LOG="$LOG_PATH_MODULE""/vul_func_""$FUNCTION""-""$NAME"".txt"
        for E in "${OBJ_DUMPS_ARR[@]}" ; do
          echo "$E" >> "$FUNC_LOG"
        done
        COUNT_FUNC="$(grep -c "bl.*""$FUNCTION" "$FUNC_LOG"  2> /dev/null)"
        if [[ "$FUNCTION" == "strcpy" ]] ; then
          COUNT_STRLEN=$(grep -c "bl.*strlen" "$FUNC_LOG"  2> /dev/null)
          (( STRCPY_CNT="$STRCPY_CNT"+"$COUNT_FUNC" ))
        elif [[ "$FUNCTION" == "mmap" ]] ; then
          # Test source: https://www.golem.de/news/mmap-codeanalyse-mit-sechs-zeilen-bash-2006-148878-2.html
          COUNT_MMAP_OK=$(grep -c "cmpwi.*,r.*,-1" "$FUNC_LOG"  2> /dev/null)
        fi
        output_function_details
      fi
    fi
  done
  echo "$STRCPY_CNT" >> "$TMP_DIR"/S11_STRCPY_CNT.tmp
}

function_check_MIPS32() {
  for FUNCTION in "${VULNERABLE_FUNCTIONS[@]}" ; do
    FUNC_ADDR=$(readelf -A "$LINE" 2> /dev/null | grep -E \ "$FUNCTION" | grep gp | grep -m1 UND | cut -d\  -f4 | sed s/\(gp\)// | sed s/-// 2> /dev/null)
    STRLEN_ADDR=$(readelf -A "$LINE" 2> /dev/null | grep -E \ "strlen" | grep gp | grep -m1 UND | cut -d\  -f4 | sed s/\(gp\)// | sed s/-// 2> /dev/null)
    if [[ -n "$FUNC_ADDR" ]] ; then
      NAME=$(basename "$LINE" 2> /dev/null)
      if [[ "$FUNCTION" == "mmap" ]] ; then
        # For the mmap check we need the disasm after the call
        mapfile -t OBJ_DUMPS_ARR < <("$OBJDUMP" -d "$LINE" | grep -A 20 "$FUNC_ADDR""(gp)" | sed s/-"$FUNC_ADDR"\(gp\)/"$FUNCTION"/ )
      else
        mapfile -t OBJ_DUMPS_ARR < <("$OBJDUMP" -d "$LINE" | grep -A 2 -B 25 "$FUNC_ADDR""(gp)" | sed s/-"$FUNC_ADDR"\(gp\)/"$FUNCTION"/ | sed s/-"$STRLEN_ADDR"\(gp\)/strlen/ )
      fi
      if [[ "$OBJ_DUMPS_OUT" != *"file format not recognized"* && "${#OBJ_DUMPS_ARR[@]}" -gt 0 ]] ; then
        FUNC_LOG="$LOG_PATH_MODULE""/vul_func_""$FUNCTION""-""$NAME"".txt"
        for E in "${OBJ_DUMPS_ARR[@]}" ; do
          echo "$E" >> "$FUNC_LOG"
        done
        COUNT_FUNC="$(grep -c "lw.*""$FUNCTION" "$FUNC_LOG"  2> /dev/null)"
        if [[ "$FUNCTION" == "strcpy" ]] ; then
          COUNT_STRLEN=$(grep -c "lw.*strlen" "$FUNC_LOG"  2> /dev/null)
          (( STRCPY_CNT="$STRCPY_CNT"+"$COUNT_FUNC" ))
        elif [[ "$FUNCTION" == "mmap" ]] ; then
          # Test source: https://www.golem.de/news/mmap-codeanalyse-mit-sechs-zeilen-bash-2006-148878-2.html
          # Check this. This test is very rough:
          COUNT_MMAP_OK=$(grep -c ",-1$" "$FUNC_LOG"  2> /dev/null)
        fi
        output_function_details
      fi
    fi
  done
  echo "$STRCPY_CNT" >> "$TMP_DIR"/S11_STRCPY_CNT.tmp
}

function_check_ARM64() {
  for FUNCTION in "${VULNERABLE_FUNCTIONS[@]}" ; do
    NAME=$(basename "$LINE" 2> /dev/null)
    if [[ "$FUNCTION" == "mmap" ]] ; then
      mapfile -t OBJ_DUMPS_ARR < <("$OBJDUMP" -d "$LINE" | grep -A 20 "[[:blank:]]bl[[:blank:]].*<$FUNCTION" 2> /dev/null)
    else
      mapfile -t OBJ_DUMPS_ARR < <("$OBJDUMP" -d "$LINE" | grep -A 2 -B 20 "[[:blank:]]bl[[:blank:]].*<$FUNCTION" 2> /dev/null)
    fi
    if [[ "$OBJ_DUMPS_OUT" != *"file format not recognized"* && "${#OBJ_DUMPS_ARR[@]}" -gt 0 ]] ; then
      FUNC_LOG="$LOG_PATH_MODULE""/vul_func_""$FUNCTION""-""$NAME"".txt"
      for E in "${OBJ_DUMPS_ARR[@]}" ; do
        echo "$E" >> "$FUNC_LOG"
      done
      COUNT_FUNC="$(grep -c "[[:blank:]]bl[[:blank:]].*<$FUNCTION" "$FUNC_LOG"  2> /dev/null)"
      if [[ "$FUNCTION" == "strcpy" ]] ; then
        COUNT_STRLEN=$(grep -c "[[:blank:]]bl[[:blank:]].*<strlen" "$FUNC_LOG"  2> /dev/null)
        (( STRCPY_CNT="$STRCPY_CNT"+"$COUNT_FUNC" ))
      elif [[ "$FUNCTION" == "mmap" ]] ; then
        # Test source: https://www.golem.de/news/mmap-codeanalyse-mit-sechs-zeilen-bash-2006-148878-2.html
        # Test not implemented on ARM64
        #COUNT_MMAP_OK=$(grep -c "cm.*r.*,\ \#[01]" "$FUNC_LOG"  2> /dev/null)
        COUNT_MMAP_OK="NA"
      fi
      output_function_details
    fi
  done
  echo "$STRCPY_CNT" >> "$TMP_DIR"/S11_STRCPY_CNT.tmp
}

function_check_ARM32() {
  for FUNCTION in "${VULNERABLE_FUNCTIONS[@]}" ; do
    NAME=$(basename "$LINE" 2> /dev/null)
    if [[ "$FUNCTION" == "mmap" ]] ; then
      mapfile -t OBJ_DUMPS_ARR < <("$OBJDUMP" -d "$LINE" | grep -A 20 "[[:blank:]]bl[[:blank:]].*<$FUNCTION" 2> /dev/null)
    else
      mapfile -t OBJ_DUMPS_ARR < <("$OBJDUMP" -d "$LINE" | grep -A 2 -B 20 "[[:blank:]]bl[[:blank:]].*<$FUNCTION" 2> /dev/null)
    fi
    if [[ "$OBJ_DUMPS_OUT" != *"file format not recognized"* && "${#OBJ_DUMPS_ARR[@]}" -gt 0 ]] ; then
      FUNC_LOG="$LOG_PATH_MODULE""/vul_func_""$FUNCTION""-""$NAME"".txt"
      for E in "${OBJ_DUMPS_ARR[@]}" ; do
        echo "$E" >> "$FUNC_LOG"
      done
      COUNT_FUNC="$(grep -c "[[:blank:]]bl[[:blank:]].*<$FUNCTION" "$FUNC_LOG"  2> /dev/null)"
      if [[ "$FUNCTION" == "strcpy" ]] ; then
        COUNT_STRLEN=$(grep -c "[[:blank:]]bl[[:blank:]].*<strlen" "$FUNC_LOG"  2> /dev/null)
        (( STRCPY_CNT="$STRCPY_CNT"+"$COUNT_FUNC" ))
      elif [[ "$FUNCTION" == "mmap" ]] ; then
        # Test source: https://www.golem.de/news/mmap-codeanalyse-mit-sechs-zeilen-bash-2006-148878-2.html
        # Check this testcase. Not sure if it works in all cases! 
        COUNT_MMAP_OK=$(grep -c "cm.*r.*,\ \#[01]" "$FUNC_LOG"  2> /dev/null)
      fi
      output_function_details
    fi
  done
  echo "$STRCPY_CNT" >> "$TMP_DIR"/S11_STRCPY_CNT.tmp
}

function_check_x86() {
  for FUNCTION in "${VULNERABLE_FUNCTIONS[@]}" ; do
    if ( readelf -r "$LINE" | awk '{print $5}' | grep -E -q "^$FUNCTION" 2> /dev/null ) ; then
      if [[ "$FUNCTION" == "mmap" ]] ; then
        # For the mmap check we need the disasm after the call
        mapfile -t OBJ_DUMPS_ARR < <("$OBJDUMP" -d "$LINE" | grep -E -A 20 "call.*<$FUNCTION" 2> /dev/null)
      else
        mapfile -t OBJ_DUMPS_ARR < <("$OBJDUMP" -d "$LINE" | grep -E -A 2 -B 20 "call.*<$FUNCTION" 2> /dev/null)
      fi
      if [[ "$OBJ_DUMPS_OUT" != *"file format not recognized"* && "${#OBJ_DUMPS_ARR[@]}" -gt 0 ]] ; then
        FUNC_LOG="$LOG_PATH_MODULE""/vul_func_""$FUNCTION""-""$NAME"".txt"
        for E in "${OBJ_DUMPS_ARR[@]}" ; do
          echo "$E" >> "$FUNC_LOG"
        done
        COUNT_FUNC="$(grep -c -e "call.*$FUNCTION" "$FUNC_LOG"  2> /dev/null)"
        if [[ "$FUNCTION" == "strcpy" ]] ; then
          COUNT_STRLEN=$(grep -c "call.*strlen" "$FUNC_LOG"  2> /dev/null)
          (( STRCPY_CNT="$STRCPY_CNT"+"$COUNT_FUNC" ))
        elif [[ "$FUNCTION" == "mmap" ]] ; then
          # Test source: https://www.golem.de/news/mmap-codeanalyse-mit-sechs-zeilen-bash-2006-148878-2.html
          COUNT_MMAP_OK=$(grep -c "cmp.*0xffffffff" "$FUNC_LOG"  2> /dev/null)
        fi
        output_function_details
      fi
    fi
  done
  echo "$STRCPY_CNT" >> "$TMP_DIR"/S11_STRCPY_CNT.tmp
}

function_check_x86_64() {
   for FUNCTION in "${VULNERABLE_FUNCTIONS[@]}" ; do
    if ( readelf -r "$LINE" | awk '{print $5}' | grep -E -q "^$FUNCTION" 2> /dev/null ) ; then
      if [[ "$FUNCTION" == "mmap" ]] ; then
        # For the mmap check we need the disasm after the call
        mapfile -t OBJ_DUMPS_ARR < <("$OBJDUMP" -d "$LINE" | grep -E -A 20 "call.*<$FUNCTION" 2> /dev/null)
      else
        mapfile -t OBJ_DUMPS_ARR < <("$OBJDUMP" -d "$LINE" | grep -E -A 2 -B 20 "call.*<$FUNCTION" 2> /dev/null)
      fi
      if [[ "$OBJ_DUMPS_OUT" != *"file format not recognized"* && "${#OBJ_DUMPS_ARR[@]}" -gt 0 ]] ; then
        FUNC_LOG="$LOG_PATH_MODULE""/vul_func_""$FUNCTION""-""$NAME"".txt"
        for E in "${OBJ_DUMPS_ARR[@]}" ; do
          echo "$E" >> "$FUNC_LOG"
        done
        COUNT_FUNC="$(grep -c -e "call.*$FUNCTION" "$FUNC_LOG"  2> /dev/null)"
        if [[ "$FUNCTION" == "strcpy"  ]] ; then
          COUNT_STRLEN=$(grep -c "call.*strlen" "$FUNC_LOG"  2> /dev/null)
          (( STRCPY_CNT="$STRCPY_CNT"+"$COUNT_FUNC" ))
        elif [[ "$FUNCTION" == "mmap"  ]] ; then
          # Test source: https://www.golem.de/news/mmap-codeanalyse-mit-sechs-zeilen-bash-2006-148878-2.html
          COUNT_MMAP_OK=$(grep -c "cmp.*0xffffffffffffffff" "$FUNC_LOG"  2> /dev/null)
        fi
        output_function_details
      fi
    fi
  done
  echo "$STRCPY_CNT" >> "$TMP_DIR"/S11_STRCPY_CNT.tmp
}

print_top10_statistics() {
  if [[ "$(find "$LOG_PATH_MODULE" -xdev -iname "vul_func_*_*-*.txt" | wc -l)" -gt 0 ]]; then
    for FUNCTION in "${VULNERABLE_FUNCTIONS[@]}" ; do
      local SEARCH_TERM
      local F_COUNTER
      readarray -t RESULTS < <( find "$LOG_PATH_MODULE" -xdev -iname "vul_func_*_""$FUNCTION""-*.txt" 2> /dev/null | sed "s/.*vul_func_//" | sort -g -r | head -10 | sed "s/_""$FUNCTION""-/  /" | sed "s/\.txt//" 2> /dev/null)
  
      if [[ "${#RESULTS[@]}" -gt 0 ]]; then
        print_output ""
        print_output "[+] ""$FUNCTION"" - top 10 results:"
        write_anchor "strcpysummary"
        for LINE in "${RESULTS[@]}" ; do
          SEARCH_TERM="$(echo "$LINE" | cut -d\  -f3)"
          F_COUNTER="$(echo "$LINE" | cut -d\  -f1)"
          if [[ -f "$BASE_LINUX_FILES" ]]; then
            # if we have the base linux config file we are checking it:
            if grep -q "^$SEARCH_TERM\$" "$BASE_LINUX_FILES" 2>/dev/null; then
              printf "${GREEN}\t%-5.5s : %-15.15s : common linux file: yes${NC}\n" "$F_COUNTER" "$SEARCH_TERM" | tee -a "$LOG_FILE"
            else
              printf "${ORANGE}\t%-5.5s : %-15.15s : common linux file: no${NC}\n" "$F_COUNTER" "$SEARCH_TERM" | tee -a "$LOG_FILE"
            fi  
          else
            print_output "$(indent "$(orange "$F_COUNTER""\t:\t""$SEARCH_TERM")")"
          fi  
        done
      fi  
    done
  else
    #print_output "$LOG_PATH_MODULE"" ""$FUNCTION"
    print_output "$(indent "$(orange "No weak binary functions found - check it manually with readelf and objdump -D")")"
  fi
}

output_function_details()
{
  write_s11_log()
  {
    OLD_LOG_FILE="$LOG_FILE"
    LOG_FILE="$3"
    print_output "$1"
    write_link "$2"
    cat "$LOG_FILE" >> "$OLD_LOG_FILE"
    rm "$LOG_FILE" 2> /dev/null
    LOG_FILE="$OLD_LOG_FILE"
  }

  local LOG_FILE_LOC
  LOG_FILE_LOC="$LOG_PATH_MODULE"/vul_func_"$FUNCTION"-"$NAME".txt

  #check if this is common linux file:
  local COMMON_FILES_FOUND
  local SEARCH_TERM
  if [[ -f "$BASE_LINUX_FILES" ]]; then
    SEARCH_TERM=$(basename "$LINE")
    if grep -q "^$SEARCH_TERM\$" "$BASE_LINUX_FILES" 2>/dev/null; then
      COMMON_FILES_FOUND="${CYAN}"" - common linux file: yes - "
      echo -e "[$GREEN+$NC] ""$GREEN"File "$(print_path "$LINE") found in default Linux file dictionary""$NC" >> "$SUPPL_PATH"/common_linux_files.txt
    else
      echo -e "[$GREEN+$NC] ""$ORANGE"File "$(print_path "$LINE")""$NC""$GREEN"" not found in default Linux file dictionary""$NC" >> "$SUPPL_PATH"/common_linux_files.txt
      COMMON_FILES_FOUND="${RED}"" - common linux file: no -"
    fi
  else
    COMMON_FILES_FOUND=" -"
  fi

  LOG_FILE_LOC_OLD="$LOG_FILE_LOC"
  LOG_FILE_LOC="$LOG_PATH_MODULE"/vul_func_"$COUNT_FUNC"_"$FUNCTION"-"$NAME".txt
  mv "$LOG_FILE_LOC_OLD" "$LOG_FILE_LOC" 2> /dev/null
  
  if [[ $COUNT_FUNC -ne 0 ]] ; then
    if [[ "$FUNCTION" == "strcpy" ]] ; then
      OUTPUT="[+] ""$(print_path "$LINE")""$COMMON_FILES_FOUND""${NC}"" Vulnerable function: ""${CYAN}""$FUNCTION"" ""${NC}""/ ""${RED}""Function count: ""$COUNT_FUNC"" ""${NC}""/ ""${ORANGE}""strlen: ""$COUNT_STRLEN"" ""${NC}""\\n"
    elif [[ "$FUNCTION" == "mmap" ]] ; then
      OUTPUT="[+] ""$(print_path "$LINE")""$COMMON_FILES_FOUND""${NC}"" Vulnerable function: ""${CYAN}""$FUNCTION"" ""${NC}""/ ""${RED}""Function count: ""$COUNT_FUNC"" ""${NC}""/ ""${ORANGE}""Correct error handling: ""$COUNT_MMAP_OK"" ""${NC}""\\n"
    else
      OUTPUT="[+] ""$(print_path "$LINE")""$COMMON_FILES_FOUND""${NC}"" Vulnerable function: ""${CYAN}""$FUNCTION"" ""${NC}""/ ""${RED}""Function count: ""$COUNT_FUNC"" ""${NC}""\\n"
    fi
    write_s11_log "$OUTPUT" "$LOG_FILE_LOC" "$LOG_PATH_MODULE""/vul_func_tmp_""$FUNCTION"-"$NAME"".txt"
  fi

  
}

