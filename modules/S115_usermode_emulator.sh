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

# Description:  Emulates executables from the firmware with qemu to get version information. 
#               Currently this is an experimental module and needs to be activated separately via the -E switch. 
#               It is also recommended to only use this technique in a dockerized or virtualized environment.

# Threading priority - if set to 1, these modules will be executed first
export THREAD_PRIO=1

S115_usermode_emulator() {
  module_log_init "${FUNCNAME[0]}"
  module_title "Emulation based software component and version detection."

  if [[ "$QEMULATION" -eq 1 && "$RTOS" -eq 0 ]]; then

    print_output "[!] This module is experimental and could harm your host environment."
    print_output "[!] This module creates a working copy of the firmware filesystem in the log directory $LOG_DIR.\\n"

    # some processes are running long and logging a lot
    # to protect the host we are going to kill them on a KILL_SIZE limit
    KILL_SIZE="50M"

    declare -a MISSING
    ROOT_CNT=0

    ## load blacklist of binaries that could cause troubles during emulation:
    readarray -t BIN_BLACKLIST < "$CONFIG_DIR"/emulation_blacklist.cfg

    # as we modify the firmware area, we copy it to the log directory and do the modifications in this area
    # Note: only for firmware directories - if we have already extracted the firmware we do not copy it again
    copy_firmware

    # we only need to detect the root directory again if we have copied it before
    if [[ -d "$FIRMWARE_PATH_BAK" ]]; then
      detect_root_dir_helper "$EMULATION_PATH_BASE" "$(get_log_file)"
    fi

    print_output "[*] Detected $ORANGE${#ROOT_PATH[@]}$NC root directories:"
    for R_PATH in "${ROOT_PATH[@]}" ; do
      print_output "[*] Detected root path: $ORANGE$R_PATH$NC"
    done

    # MD5_DONE_INT is the array of all MD5 checksums for all root paths -> this is needed to ensure that we do not test bins twice
    MD5_DONE_INT=()
    for R_PATH in "${ROOT_PATH[@]}" ; do
      BIN_CNT=0
      ((ROOT_CNT=ROOT_CNT+1))
      print_output "[*] Running emulation processes in $ORANGE$R_PATH$NC root path ($ORANGE$ROOT_CNT/${#ROOT_PATH[@]}$NC)."

      DIR=$(pwd)
      mapfile -t BIN_EMU_TMP < <(cd "$R_PATH" && find . -xdev -ignore_readdir_race -type f ! \( -name "*.ko" -o -name "*.so" \) -exec file {} \; 2>/dev/null | grep "ELF.*executable\|ELF.*shared\ object" | grep -v "version\ .\ (FreeBSD)" | cut -d: -f1 2>/dev/null && cd "$DIR" || exit)
      # we re-create the BIN_EMU array with all unique binaries for every root directory
      # as we have all tested MD5s in MD5_DONE_INT (for all root dirs) we test every bin only once
      BIN_EMU=()

      print_output "[*] Create unique binary array for $ORANGE$R_PATH$NC root path ($ORANGE$ROOT_CNT/${#ROOT_PATH[@]}$NC)."
      for BINARY in "${BIN_EMU_TMP[@]}"; do
        # we emulate every binary only once. So calculate the checksum and store it for checking
        BIN_MD5_=$(md5sum "$R_PATH"/"$BINARY" | cut -d\  -f1)
        if [[ ! " ${MD5_DONE_INT[*]} " =~ ${BIN_MD5_} ]]; then
          BIN_EMU+=( "$BINARY" )
          MD5_DONE_INT+=( "$BIN_MD5_" )
        fi
      done

      print_output "[*] Testing $ORANGE${#BIN_EMU[@]}$NC unique executables in root dirctory: $ORANGE$R_PATH$NC ($ORANGE$ROOT_CNT/${#ROOT_PATH[@]}$NC)."

      for BIN_ in "${BIN_EMU[@]}" ; do
        ((BIN_CNT=BIN_CNT+1))
        FULL_BIN_PATH="$R_PATH"/"$BIN_"
        if [[ "${BIN_BLACKLIST[*]}" == *"$(basename "$FULL_BIN_PATH")"* ]]; then
          print_output "[!] Blacklist triggered ... $ORANGE$BIN_$NC ($ORANGE$BIN_CNT/${#BIN_EMU[@]}$NC)"
          continue
        else
          if [[ "$THREADED" -eq 1 ]]; then
            # we adjust the max threads regularly. S115 respects the consumption of S09 and adjusts the threads
            MAX_THREADS_S115=$((7*"$(grep -c ^processor /proc/cpuinfo)"))
            if [[ $(grep -c S09_ "$LOG_DIR"/"$MAIN_LOG_FILE") -eq 1 ]]; then
              # if only one result for S09_ is found in emba.log means the S09 module is started and currently running
              MAX_THREADS_S115=$((3*"$(grep -c ^processor /proc/cpuinfo)"))
            fi
          fi
          if [[ "$BIN_" != './qemu-'*'-static' ]]; then
            if ( file "$FULL_BIN_PATH" | grep -q "version\ .\ (FreeBSD)" ) ; then
              # https://superuser.com/questions/1404806/running-a-freebsd-binary-on-linux-using-qemu-user
              print_output "[-] No working emulator found for FreeBSD binary $ORANGE$BIN_$NC."
              EMULATOR="NA"
              continue
            elif ( file "$FULL_BIN_PATH" | grep -q "x86-64" ) ; then
              EMULATOR="qemu-x86_64-static"
            elif ( file "$FULL_BIN_PATH" | grep -q "Intel 80386" ) ; then
              EMULATOR="qemu-i386-static"
            elif ( file "$FULL_BIN_PATH" | grep -q "32-bit LSB.*ARM" ) ; then
              EMULATOR="qemu-arm-static"
            elif ( file "$FULL_BIN_PATH" | grep -q "32-bit MSB.*ARM" ) ; then
              EMULATOR="qemu-armeb-static"
            elif ( file "$FULL_BIN_PATH" | grep -q "32-bit LSB.*MIPS" ) ; then
              EMULATOR="qemu-mipsel-static"
            elif ( file "$FULL_BIN_PATH" | grep -q "32-bit MSB.*MIPS" ) ; then
              EMULATOR="qemu-mips-static"
            elif ( file "$FULL_BIN_PATH" | grep -q "32-bit MSB.*PowerPC" ) ; then
              EMULATOR="qemu-ppc-static"
            else
              print_output "[-] No working emulator found for $BIN_"
              EMULATOR="NA"
              continue
            fi

            if [[ "$EMULATOR" != "NA" ]]; then
              print_output "[*] Emulator used: $ORANGE$EMULATOR$NC"
              prepare_emulator
              if [[ "$THREADED" -eq 1 ]]; then
                emulate_binary &
                WAIT_PIDS_S115_x+=( "$!" )
                max_pids_protection "$MAX_THREADS_S115" "${WAIT_PIDS_S115_x[@]}"
              else
                emulate_binary
              fi
            fi
          fi
          running_jobs
        fi
      done
    done

    if [[ "$THREADED" -eq 1 ]]; then
      wait_for_pid "${WAIT_PIDS_S115_x[@]}"
    fi

    s115_cleanup
    running_jobs
    print_filesystem_fixes
    version_detection

  else
    print_output ""
    print_output "[!] Automated emulation is disabled."
    print_output "[!] Enable it with the $ORANGE-E$MAGENTA switch.$NC"
  fi

  module_end_log "${FUNCNAME[0]}" "$QEMULATION"
}

print_filesystem_fixes() {
  if [[ "${#MISSING[@]}" -ne 0 ]]; then
    sub_module_title "Filesystem fixes"
    print_output "[*] Emba has auto-generated the files during runtime."
    print_output "[*] For persistence you could generate it manually in your filesystem.\\n"
    for MISSING_FILE in "${MISSING[@]}"; do
      print_output "[*] Missing file: $ORANGE$MISSING_FILE$NC"
    done
  fi
}

version_detection() {
  sub_module_title "Identified software components."

  while read -r VERSION_LINE; do 
    if [[ $THREADING -eq 1 ]]; then
      version_detection_thread &
      WAIT_PIDS_S115+=( "$!" )
    else
      version_detection_thread
    fi
  done < "$CONFIG_DIR"/bin_version_strings.cfg
  echo
  if [[ $THREADED -eq 1 ]]; then
    wait_for_pid "${WAIT_PIDS_S115[@]}"
  fi
}

version_detection_thread() {
  BINARY="$(echo "$VERSION_LINE" | cut -d: -f1)"
  STRICT="$(echo "$VERSION_LINE" | cut -d: -f2)"
  VERSION_IDENTIFIER="$(echo "$VERSION_LINE" | cut -d: -f3- | sed s/^\"// | sed s/\"$//)"
  if [[ -f "$LOG_PATH_MODULE"/qemu_"$BINARY".txt ]]; then
    mapfile -t BINARY_PATHS < <(grep -a "Emulating binary:" "$LOG_PATH_MODULE"/qemu_"$BINARY".txt | cut -d: -f2 | sed -e 's/^\ //' | sort -u 2>/dev/null)
  fi

  # if we have the key strict this version identifier only works for the defined binary and is not generic!
  if [[ $STRICT != "strict" ]]; then
    readarray -t VERSIONS_DETECTED < <(grep -a -o -E "$VERSION_IDENTIFIER" "$LOG_PATH_MODULE"/* 2>/dev/null)
  else
    if [[ -f "$LOG_PATH_MODULE"/qemu_"$BINARY".txt ]]; then
      VERSION_STRICT=$(grep -a -o -E "$VERSION_IDENTIFIER" "$LOG_PATH_MODULE"/qemu_"$BINARY".txt | sort -u | head -1 2>/dev/null)
      if [[ -n "$VERSION_STRICT" ]]; then
        if [[ "$BINARY" == "smbd" ]]; then
          # we log it as the original binary and the samba binary name
          VERSION_="$BINARY $VERSION_STRICT"
          VERSIONS_DETECTED+=("$VERSION_")
          BINARY="samba"
        fi
        VERSION_="$BINARY:$BINARY $VERSION_STRICT"
        VERSIONS_DETECTED+=("$VERSION_")
      fi
    fi
  fi

  if [[ ${#VERSIONS_DETECTED[@]} -ne 0 ]]; then
    for VERSION_DETECTED in "${VERSIONS_DETECTED[@]}"; do
      # if we have multiple detection of the same version details:
      if [ "$VERSION_DETECTED" != "$VERS_DET_OLD" ]; then
        VERS_DET_OLD="$VERSION_DETECTED"
        #VERSIONS_BIN="$(basename "$(echo "$VERSION_DETECTED" | cut -d: -f1)")"
        VERSION_DETECTED="$(echo "$VERSION_DETECTED" | cut -d: -f2-)"

        if [[ ${#BINARY_PATHS[@]} -eq 0 ]]; then
          print_output "[+] Version information found ${RED}""$VERSION_DETECTED""${NC}${GREEN} in qemu log file (emulation)."
          continue
        else
          for BINARY_PATH in "${BINARY_PATHS[@]}"; do
            print_output "[+] Version information found ${RED}""$VERSION_DETECTED""${NC}${GREEN} in binary $ORANGE$(print_path "$BINARY_PATH")$GREEN (emulation)."
          done
        fi
      fi
    done
  fi
}

copy_firmware() {
  # we just create a backup if the original firmware path was a root directory
  # if it was a binary file we already have extracted it and it is already messed up
  # so we can mess it up a bit more ;)
  # shellcheck disable=SC2154
  if [[ -d "$FIRMWARE_PATH_BAK" ]]; then
    print_output "[*] Create a firmware backup for emulation ..."
    cp -pri "$FIRMWARE_PATH" "$LOG_PATH_MODULE"/ 2> /dev/null
    EMULATION_DIR=$(basename "$FIRMWARE_PATH")
    EMULATION_PATH_BASE="$LOG_PATH_MODULE"/"$EMULATION_DIR"
    print_output "[*] Firmware backup for emulation created in $ORANGE$EMULATION_PATH_BASE$NC"
  else
    EMULATION_DIR=$(basename "$FIRMWARE_PATH")
    EMULATION_PATH_BASE="$LOG_DIR"/"$EMULATION_DIR"
    print_output "[*] Firmware used for emulation in $ORANGE$EMULATION_PATH_BASE$NC"
  fi
}

running_jobs() {
  # if no emulation at all was possible the $EMULATOR variable is not defined
  if [[ -n "$EMULATOR" ]]; then
    CJOBS=$(pgrep -a "$EMULATOR")
    if [[ -n "$CJOBS" ]] ; then
      echo
      print_output "[*] Currently running emulation jobs: $(echo "$CJOBS" | wc -l)"
      print_output "$(indent "$CJOBS")""\\n"
    else
      CJOBS="NA"
    fi
  fi
}

s115_cleanup() {
  # reset the terminal - after all the uncontrolled emulation it is typically messed up!
  reset
  rm "$LOG_PATH_MODULE""/stracer_*.txt"

  # if no emulation at all was possible the $EMULATOR variable is not defined
  if [[ -n "$EMULATOR" ]]; then
    print_output "[*] Terminating qemu processes - check it with ps"
    killall -9 --quiet -r .*qemu.*sta.*
  fi

  CJOBS_=$(pgrep qemu-)
  if [[ -n "$CJOBS_" ]] ; then
    print_output "[*] More emulation jobs are running ... we kill it with fire\\n"
    killall -9 "$EMULATOR" 2> /dev/null
  fi

  print_output "[*] Cleaning the emulation environment\\n"
  find "$EMULATION_PATH_BASE" -xdev -iname "qemu*static" -exec rm {} \; 2>/dev/null

  print_output ""
  print_output "[*] Umounting proc, sys and run"
  mapfile -t CHECK_MOUNTS < <(mount | grep "$EMULATION_PATH_BASE")
  for MOUNT in "${CHECK_MOUNTS[@]}"; do
    print_output "[*] Unmounting $MOUNT"
    MOUNT=$(echo "$MOUNT" | cut -d\  -f3)
    umount -l "$MOUNT"
  done

  mapfile -t FILES < <(find "$LOG_PATH_MODULE""/" -xdev -type f -name "qemu_*" 2>/dev/null)
  if [[ "${#FILES[@]}" -gt 0 ]] ; then
    print_output "[*] Cleanup empty log files.\\n\\n"
    for FILE in "${FILES[@]}" ; do
      if [[ ! -s "$FILE" ]] ; then
        rm "$FILE" 2> /dev/null
      else
        BIN=$(basename "$FILE")
        BIN=$(echo "$BIN" | cut -d_ -f2 | sed 's/.txt$//')
        print_output "[+]""${NC}"" Emulated binary ""${GREEN}""$BIN""${NC}"" generated output in ""${GREEN}""$FILE""${NC}"". Please check this manually."
      fi
    done
  fi
  # if we got a firmware directory then we have created a backup for emulation
  # lets delete it now
  if [[ -d "$FIRMWARE_PATH_BAK" ]]; then
    print_output "[*] Remove firmware copy from emulation directory.\\n\\n"
    rm -r "$EMULATION_PATH_BASE"
  fi
}

prepare_emulator() {

  if [[ ! -e "$R_PATH""/""$EMULATOR" ]]; then
    print_output "[*] Preparing the environment for usermode emulation"
    if ! command -v "$EMULATOR" > /dev/null ; then
      echo
      print_output "[!] Is the qemu package installed?"
      print_output "$(indent "We can't find it!")"
      print_output "$(indent "$(red "Terminating emba now.\\n")")"
      exit 1
    else
      cp "$(which $EMULATOR)" "$R_PATH"/
    fi

    if ! [[ -d "$R_PATH""/proc" ]] ; then
      mkdir "$R_PATH""/proc" 2> /dev/null
    fi

    if ! [[ -d "$R_PATH""/sys" ]] ; then
      mkdir "$R_PATH""/sys" 2> /dev/null
    fi

    if ! [[ -d "$R_PATH""/run" ]] ; then
      mkdir "$R_PATH""/run" 2> /dev/null
    fi

    if ! [[ -d "$R_PATH""/dev/" ]] ; then
      mkdir "$R_PATH""/dev/" 2> /dev/null
    fi

    if ! mount | grep "$R_PATH"/proc > /dev/null ; then
      mount proc "$R_PATH""/proc" -t proc 2> /dev/null
    fi
    if ! mount | grep "$R_PATH/run" > /dev/null ; then
      mount -o bind /run "$R_PATH""/run" 2> /dev/null
    fi
    if ! mount | grep "$R_PATH/sys" > /dev/null ; then
      mount -o bind /sys "$R_PATH""/sys" 2> /dev/null
    fi

    if ! [[ -e "$R_PATH""/dev/console" ]] ; then
      mknod -m 622 "$R_PATH""/dev/console" c 5 1 2> /dev/null
    fi

    if ! [[ -e "$R_PATH""/dev/null" ]] ; then
      mknod -m 666 "$R_PATH""/dev/null" c 1 3 2> /dev/null
    fi

    if ! [[ -e "$R_PATH""/dev/zero" ]] ; then
      mknod -m 666 "$R_PATH""/dev/zero" c 1 5 2> /dev/null
    fi

    if ! [[ -e "$R_PATH""/dev/ptmx" ]] ; then
      mknod -m 666 "$R_PATH""/dev/ptmx" c 5 2 2> /dev/null
    fi

    if ! [[ -e "$R_PATH""/dev/tty" ]] ; then
      mknod -m 666 "$R_PATH""/dev/tty" c 5 0 2> /dev/null
    fi

    if ! [[ -e "$R_PATH""/dev/random" ]] ; then
      mknod -m 444 "$R_PATH""/dev/random" c 1 8 2> /dev/null
    fi

    if ! [[ -e "$R_PATH""/dev/urandom" ]] ; then
      mknod -m 444 "$R_PATH""/dev/urandom" c 1 9 2> /dev/null
    fi

    chown -v root:tty "$R_PATH""/dev/"{console,ptmx,tty} > /dev/null 2>&1

    print_output ""
    print_output "[*] Currently mounted areas:"
    print_output "$(indent "$(mount | grep "$R_PATH" 2> /dev/null )")""\\n"

    # we disable core dumps in our docker environment. If running on the host without docker
    # the user is responsible for useful settings
    if [[ $IN_DOCKER -eq 1 ]] ; then
      print_output ""
      print_output "[*] We disable core dumps to prevent wasting our disk space."
      ulimit -c 0
    fi

  fi
}

emulate_strace_run() {
  print_output ""
  print_output "[*] Initial strace run on the command ${GREEN}$BIN_${NC} to identify missing areas"

  # currently we only look for file errors (errno=2) and try to fix this
  chroot "$R_PATH" ./"$EMULATOR" --strace "$BIN_" > "$LOG_PATH_MODULE""/stracer_""$BIN_EMU_NAME"".txt" 2>&1 &
  PID=$!

  # wait a second and then kill it
  sleep 1
  kill -0 -9 "$PID" 2> /dev/null

  # extract missing files, exclude *.so files:
  mapfile -t MISSING_AREAS < <(grep -a "open" "$LOG_PATH_MODULE""/stracer_""$BIN_EMU_NAME"".txt" | grep -a "errno=2\ " 2>&1 | cut -d\" -f2 2>&1 | sort -u | grep -v ".*\.so")

  for MISSING_AREA in "${MISSING_AREAS[@]}"; do
    MISSING+=("$MISSING_AREA")
    if [[ "$MISSING_AREA" != */proc/* || "$MISSING_AREA" != */sys/* ]]; then
      print_output "[*] Found missing area: $MISSING_AREA"
  
      FILENAME_MISSING=$(basename "$MISSING_AREA")
      print_output "[*] Trying to create this missing file: $FILENAME_MISSING"
      PATH_MISSING=$(dirname "$MISSING_AREA")

      FILENAME_FOUND=$(find "$R_PATH" -xdev -ignore_readdir_race -path "$R_PATH"/sys -prune -false -o -path "$R_PATH"/proc -prune -false -o -type f -name "$FILENAME_MISSING" 2>/dev/null)
      if [[ -n "$FILENAME_FOUND" ]]; then
        print_output "[*] Possible matching file found: $FILENAME_FOUND"
      fi
    
      if [[ ! -d "$R_PATH""$PATH_MISSING" ]]; then
        print_output "[*] Creating directory $R_PATH$PATH_MISSING"
        mkdir -p "$R_PATH""$PATH_MISSING" 2> /dev/null
        continue
      fi
      if [[ -n "$FILENAME_FOUND" ]]; then
        print_output "[*] Copy file $FILENAME_FOUND to $R_PATH$PATH_MISSING/"
        cp "$FILENAME_FOUND" "$R_PATH""$PATH_MISSING"/ 2> /dev/null
        continue
      else
        print_output "[*] Creating empty file $R_PATH$PATH_MISSING/$FILENAME_MISSING"
        touch "$R_PATH""$PATH_MISSING"/"$FILENAME_MISSING" 2> /dev/null
        continue
      fi
    fi
  done
}

check_disk_space() {

  mapfile -t CRITICAL_FILES < <(find "$LOG_PATH_MODULE"/ -xdev -type f -size +"$KILL_SIZE" -exec basename {} \; 2>/dev/null| cut -d\. -f1 | cut -d_ -f2)
  for KILLER in "${CRITICAL_FILES[@]}"; do
    if pgrep -f "$EMULATOR.*$KILLER" > /dev/null; then
      print_output "[!] Qemu processes are wasting disk space ... we try to kill it"
      print_output "[*] Killing process ${ORANGE}$EMULATOR.*$KILLER.*${NC}"
      pkill -f "$EMULATOR.*$KILLER.*"
      #rm "$LOG_DIR"/qemu_emulator/*"$KILLER"*
    fi
  done
}

emulate_binary() {
  BIN_EMU_NAME=$(basename "$FULL_BIN_PATH")
  OLD_LOG_FILE="$LOG_FILE"
  LOG_FILE="$LOG_PATH_MODULE""/qemu_tmp_""$BIN_EMU_NAME"".txt"

  print_output ""
  print_output "[*] Emulating binary: $ORANGE$BIN_$NC ($ORANGE$BIN_CNT/${#BIN_EMU[@]}$NC)"
  write_link "$LOG_PATH_MODULE""/qemu_""$BIN_EMU_NAME"".txt"
  print_output "[*] Using root directory: $ORANGE$R_PATH$NC ($ORANGE$ROOT_CNT/${#ROOT_PATH[@]}$NC)"
  write_log "[*] Emulating binary: $FULL_BIN_PATH" "$LOG_PATH_MODULE""/qemu_""$BIN_EMU_NAME"".txt"
  write_log "[*] Emulating binary name: $BIN_EMU_NAME" "$LOG_PATH_MODULE""/qemu_""$BIN_EMU_NAME"".txt"

  # lets assume we now have only ELF files. Sometimes the permissions of firmware updates are completely weird
  # we are going to give all ELF files exec permissions to execute it in the emulator
  if ! [[ -x "$FULL_BIN_PATH" ]]; then
    print_output "[*] Change permissions +x to $ORANGE$FULL_BIN_PATH$NC."
    chmod +x "$FULL_BIN_PATH"
  fi
  emulate_strace_run
  
  # emulate binary with different command line parameters:
  if [[ "$BIN_" == *"bash"* ]]; then
    EMULATION_PARAMS=("--help" "--version")
  else
    EMULATION_PARAMS=("" "-v" "-V" "-h" "-help" "--help" "--version" "version")
  fi
  
  for PARAM in "${EMULATION_PARAMS[@]}"; do
    if [[ -z "$PARAM" ]]; then
      print_output "[*] Trying to emulate binary ${GREEN}$BIN_${NC} with no parameter"
    else
      print_output "[*] Trying to emulate binary ${GREEN}$BIN_${NC} with parameter $PARAM"
    fi
    write_log "[*] Trying to emulate binary $BIN_ with parameter $PARAM" "$LOG_PATH_MODULE""/qemu_""$BIN_EMU_NAME"".txt"
    chroot "$R_PATH" ./"$EMULATOR" "$BIN_" "$PARAM" 2>&1 | tee -a "$LOG_PATH_MODULE""/qemu_""$BIN_EMU_NAME"".txt" &
    print_output ""
    check_disk_space
  done

  cat "$LOG_FILE" >> "$OLD_LOG_FILE"
  rm "$LOG_FILE" 2> /dev/null
  LOG_FILE="$OLD_LOG_FILE"
  
  # now we kill all older qemu-processes:
  # if we use the correct identifier $EMULATOR it will not work ...
  killall -9 --quiet --older-than "$QRUNTIME" -r .*qemu.*sta.*
  
  # reset the terminal - after all the uncontrolled emulation it is typically broken!
  reset
}
