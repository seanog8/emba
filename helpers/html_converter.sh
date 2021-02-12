#!/bin/bash

# emba - EMBEDDED LINUX ANALYZER
#
# Copyright 2020-2021 Siemens AG
#
# emba comes with ABSOLUTELY NO WARRANTY. This is free software, and you are
# welcome to redistribute it under the terms of the GNU General Public License.
# See LICENSE file for usage of this software.
#
# emba is licensed under GPLv3
#
# Author(s): Stefan Haboeck

declare -a MENU_LIST

build_index_file(){
  
  local TOP10_FORMAT_COUNTER
  local HTML_FILE
  FILE=$1
  FILENAME=$(basename "$FILE")
  HTML_FILE="$(basename "${FILE%.txt}"".html")"
  COULORLESS_FILE_LINE=$(head -1 "$FILE" | tail -n 1 | cut -c27-)
  
  if [[ ${FILENAME%.txt} == "s05"* ]] || [[ ${FILENAME%.txt} == "s25"* ]]; then
    if [[ "$(wc -l "$FILE" | cut -d\  -f1 2>/dev/null)" -gt 0 ]] ;  then
      readarray -t STRING_LIST <"$FILE"
      INDEX_CONTENT_ARR+=("${STRING_LIST[@]}")
    fi
  elif [[ ${FILENAME%.txt} == "f50"* ]]; then
    if [[ "$(wc -l "$FILE" | cut -d\  -f1 2>/dev/null)" -gt 0 ]] ;  then
      readarray -t STRING_LIST <"$FILE"
      INDEX_CONTENT_ARR=("${STRING_LIST[@]}")
    fi
  fi
 
  MENU_LIST+=("<li><a href=\"$HTML_FILE\">$COULORLESS_FILE_LINE</a></li>")

  if [ ${#FILENAMES[@]} -ne 0 ]; then
    FILENAMES[${#FILENAMES[@]}]="${FILENAME%.txt}"
  else
    FILENAMES[0]="${FILENAME%.txt}"
  fi

  echo "$HTML_FILE_HEADER<div><ul>" | tee -a "$HTML_PATH""/index.txt" >/dev/null
      	
  if [[ -n ${MENU_LIST[*]} ]]; then
    for OUTPUT in "${MENU_LIST[@]}"; do
      echo -e "$OUTPUT" | tee -a "$HTML_PATH""/index.txt" >/dev/null	
    done
  fi
  
  if test -f "$HTML_PATH""/collection.html"; then
    echo "<li><a href=""$HTML_PATH""/collection.html"">""Nothing found""</a></li>" | tee -a "$HTML_PATH""/index.txt" >/dev/null
  fi
  
  echo "</ul></div><div class=\"main\">"| tee -a "$HTML_PATH""/index.txt" >/dev/null
  if [[ ${FILENAME%.txt} != "f"* ]]; then
    echo "<h2>[[0;34m+[0m] [0;36m[1mGerneral Information[0m[1m[0m</h2>
      File: $(basename "$FIRMWARE_PATH")<br>
      Architecture: $ARCH<br>
      Date: $(date) <br>
      Duration time: $(date -d@$SECONDS -u +%H:%M:%S) <br>
      EMBA Command: $EMBACOMMAND <br>
      " | tee -a "$HTML_PATH""/index.txt" >/dev/null
  fi
     	
  i=0
  TOP10_FORMAT_COUNTER=0
  if [[ -n ${INDEX_CONTENT_ARR[*]} ]]; then
    for OUTPUT in "${INDEX_CONTENT_ARR[@]}"; do
      if [[ "$OUTPUT" == *"entropy.png"* ]]; then
        #heigth=\"300px\" width=\"300px\"
	OUTPUT=${OUTPUT//"33m"/"33m <br> <img id=\"entropypic\" heigth=\"380px\" width=\"540px\" src=\""}
	OUTPUT="${OUTPUT:0:${#OUTPUT}-3}"" \">"
      fi
     
      if [[ "$OUTPUT" == *"Kernel vulnerabilities"* ]]; then
        break
      fi
      if [[ "$OUTPUT" == *"top 10"* ]]; then
        TOP10_FORMAT_COUNTER=$(( TOP10_FORMAT_COUNTER+1 ))
      elif [ "$TOP10_FORMAT_COUNTER" -gt 10 ]; then
	TOP10_FORMAT_COUNTER=0
      elif [ "$TOP10_FORMAT_COUNTER" -ne 0 ]; then
	TOP10_FORMAT_COUNTER=$(( TOP10_FORMAT_COUNTER+1 ))
	OUTPUT="<span  style=\"white-space: pre\">""$OUTPUT""</span>"
      fi
	
      if [[ "$OUTPUT" == *"0;34m+"*"0;36m"* ]] && [[ "$OUTPUT" != *"h2 id"* ]]; then
        echo -e "<h2 id=""${FILENAMES[$i]}"">""$OUTPUT""</h2><br>" | tee -a "$HTML_PATH""/index.txt" >/dev/null
        i=$(( i+1 ))
      else
	echo -e "$OUTPUT""<br>" | tee -a "$HTML_PATH""/index.txt" >/dev/null
      fi
    done
  fi

  $AHA_PATH > "$HTML_PATH""/index.html" < "$HTML_PATH""/index.txt"
  rm "$HTML_PATH""/index.txt"

  sed -i 's/&lt;/</g; s/&quot;/"/g; s/&gt;/>/g; s/<pre>//g; s/<\/pre>//g' "$HTML_PATH""/index.html"
  ESCAPED_CONFIG_DIR=${CONFIG_DIR//\//\\\/}
  sed -i "s/<head>/<head><br><link rel=\"stylesheet\" href=\"$ESCAPED_CONFIG_DIR\/style.css\" type=\"text\/css\"\/>/g" "$HTML_PATH""/index.html"
}


build_collection_file(){
  FILE=$1
  local FILENAME
  FILENAME=$(basename "$FILE")
  if [[ "$(wc -l "$FILE" | cut -d\  -f1 2>/dev/null)" -gt 0 ]] ;  then
    readarray -t STRING_LIST <"$FILE"
    NOT_FINDINGS_CONTENT_ARR+=("${STRING_LIST[@]}")
  fi

  HTML_FILE="${FILE%.txt}.html"
  COULORLESS_FILE_LINE=$(head -1 "$FILE" | tail -n 1 | cut -c27-)
  LINKNAME="${COULORLESS_FILE_LINE// /_}"
  NOT_FINDINGS_MENU_LIST+="<li><a href=\"collection.html#$LINKNAME\">$COULORLESS_FILE_LINE</a></li>"
  if [ ${#NOT_FINDINGS_FILENAMES[@]} -ne 0 ]; then
    NOT_FINDINGS_FILENAMES[${#NOT_FINDINGS_FILENAMES[@]}]="$LINKNAME"
  else
    NOT_FINDINGS_FILENAMES[0]="$LINKNAME"
  fi

  echo "$HTML_FILE_HEADER
    <ul>
    $NOT_FINDINGS_MENU_LIST
    </ul>
    </div>
    <div class=\"main\">" | tee -a "$HTML_PATH""/collection.txt" >/dev/null
     	
  i=0
  if [[ -n ${NOT_FINDINGS_CONTENT_ARR[*]} ]]; then
    for OUTPUT in "${NOT_FINDINGS_CONTENT_ARR[@]}"; do
      if [[ "$OUTPUT" == *"0;34m+"*"0;36m"* ]] && [[ "$OUTPUT" != *"h2 id"* ]]; then
        echo -e "<h2 id=""${NOT_FINDINGS_FILENAMES[$i]}"">""$OUTPUT""</h2><br>" | tee -a "$HTML_PATH""/collection.txt" >/dev/null
        i=$(( i+1 ))
      else
        echo -e "$OUTPUT""<br>" | tee -a "$HTML_PATH""/collection.txt" >/dev/null
      fi
    done
  fi
  
  $AHA_PATH > "$HTML_PATH""/collection.html" < "$HTML_PATH""/collection.txt" 
  rm "$HTML_PATH""/collection.txt"

  sed -i 's/&lt;/</g; s/&quot;/"/g; s/&gt;/>/g; s/<pre>//g; s/<\/pre>//g' "$HTML_PATH""/collection.html"
  ESCAPED_CONFIG_DIR=${CONFIG_DIR//\//\\\/}
  sed -i "s/<head>/<head><br><link rel=\"stylesheet\" href=\"$ESCAPED_CONFIG_DIR\/style.css\" type=\"text\/css\"\/>/g" "$HTML_PATH""/collection.html"
}

build_report_files(){
 
  local SUB_MENU_LIST
  local FILE=$1
  local FILENAME
  local HTML_FILE
  local REPORT_ARRAY
  local HEADLINE
  local TOP10_FORMAT_COUNTER
  
  FILENAME=$(basename "$FILE")
  HTML_FILE="$(basename "${FILE%.txt}".html)"
  HEADLINE=${FILENAME%.txt}
 
  if [[ "$(wc -l "$FILE" | cut -d\  -f1 2>/dev/null)" -gt 0 ]] ;  then
    readarray -t STRING_LIST <"$FILE"
    REPORT_ARRAY+=("${STRING_LIST[@]}")
  fi
  
  if [[ -n ${REPORT_ARRAY[*]} ]]; then
    for FILE_LINE in "${REPORT_ARRAY[@]}"; do
      if [[ $FILE_LINE == *"[[0;34m+[0m] [0;36m[1m"* ]]; then
 	COLORLESS_FILE_LINE=${FILE_LINE:26:${#FILE_LINE}-3}	
 	SUB_MENU_LIST="$SUB_MENU_LIST<li><a href=\"$HTML_FILE#${COLORLESS_FILE_LINE// /_}\">$COLORLESS_FILE_LINE</a></li>"
      elif [[ $FILE_LINE == *"0;34m==>[0m [0;36m"* ]]; then
        COLORLESS_FILE_LINE=${FILE_LINE:22:${#FILE_LINE}-4}
        SUB_MENU_LIST="$SUB_MENU_LIST<li><a href=\"""$HTML_FILE#${COLORLESS_FILE_LINE// /_}""\">""$COLORLESS_FILE_LINE""</a></li>"
      fi
    done
  fi
 
  echo "<header><div class=\"pictureleft\"><img src=\"$CONFIG_DIR/emba.png\"></div>
    <div class=\"headline\"><h1>$HEADLINE</h1></div><div class=\"pictureright\"><img src=\"$CONFIG_DIR/emba.png\">
    </div></header><div><ul>$SUB_MENU_LIST</ul></div><div class=\"main\">" | tee -a "$HTML_PATH""/$FILENAME" >/dev/null
 
  TOP10_FORMAT_COUNTER=0
  if [[ -n ${REPORT_ARRAY[*]} ]]; then
    for FILE_LINE in "${REPORT_ARRAY[@]}"; do
      if [[ "$FILE_LINE" == *"entropy.png"* ]]; then
	FILE_LINE=${FILE_LINE//"33m"/"33m <br> <img id=\"entropypic\" heigth=\"380px\" width=\"540px\" src=\""}
	FILE_LINE="${FILE_LINE:0:${#FILE_LINE}-3}"" \">"
      fi
	
      if [[ "$FILE_LINE" == *"top 10"* ]]; then
	TOP10_FORMAT_COUNTER=$(( TOP10_FORMAT_COUNTER+1 ))
      elif [ "$TOP10_FORMAT_COUNTER" -gt 10 ]; then
	TOP10_FORMAT_COUNTER=0
      elif [ "$TOP10_FORMAT_COUNTER" -ne 0 ]; then
	TOP10_FORMAT_COUNTER=$(( TOP10_FORMAT_COUNTER+1 ))
	FILE_LINE="<span  style=\"white-space: pre\">""$FILE_LINE""</span>"
      fi
	
      if [[ $FILE_LINE == *"[[0;34m+[0m] [0;36m[1m"* ]]; then
 	COLORLESS_FILE_LINE=${FILE_LINE:26:${#FILE_LINE}-3}	
 	echo "<h2 id=""${COLORLESS_FILE_LINE// /_}"">$FILE_LINE</h2>" | tee -a "$HTML_PATH""/$FILENAME" >/dev/null
 	SUB_MENU_LIST="$SUB_MENU_LIST<li><a href=\"$HTML_FILE#${COLORLESS_FILE_LINE// /_}\">$COLORLESS_FILE_LINE</a></li>"
      elif [[ $FILE_LINE == *"0;34m==>[0m [0;36m"* ]]; then
 	COLORLESS_FILE_LINE=${FILE_LINE:22:${#FILE_LINE}-4}
	echo "<h4 id=""${COLORLESS_FILE_LINE// /_}"">$FILE_LINE</h4>" | tee -a "$HTML_PATH""/$FILENAME" >/dev/null
	SUB_MENU_LIST="$SUB_MENU_LIST<li><a href=\"""$HTML_FILE#${COLORLESS_FILE_LINE// /_}""\">""$COLORLESS_FILE_LINE""</a></li>"
      else
	echo "<br> $FILE_LINE" | tee -a "$HTML_PATH""/$FILENAME" >/dev/null
      fi
    done
  fi
  echo "</div>" | tee -a "$HTML_PATH""/$FILENAME" >/dev/null
  $AHA_PATH > "$HTML_PATH""/$HTML_FILE" <"$HTML_PATH""/$FILENAME"
  rm "$HTML_PATH""/$FILENAME"
  sed -i 's/&lt;/</g; s/&gt;/>/g; s/&quot;/"/g; s/<pre>//g; s/<\/pre>//g' "$HTML_PATH""/$HTML_FILE"
  ESCAPED_CONFIG_DIR=${CONFIG_DIR//\//\\\/}
  ESCAPED_SUB_MENU_LIST=${SUB_MENU_LIST//\//\\\/}
  sed -i "s/<ul><\/ul>/<ul>$ESCAPED_SUB_MENU_LIST<\/ul>/g" "$HTML_PATH""/$HTML_FILE"
  sed -i "s/<head>/<head><br><link rel=\"stylesheet\" href=\"$ESCAPED_CONFIG_DIR\/style.css\" type=\"text\/css\"\/>/g" "$HTML_PATH""/$HTML_FILE"
}

generate_html_file(){
   
  HTML_FILE_HEADER="<header>
    <div class=\"pictureleft\"><img src=\"$CONFIG_DIR/emba.png\"></div>
    <div class=\"headline\">
    <h1>EMBA Report Manager</h1> 
    </div>
    <div class=\"pictureright\">
    <img src=\"$CONFIG_DIR/emba.png\">
    </div>
    </header>"

  if [[ $2 == 1 ]]; then
    build_report_files "$1"
    build_index_file "$1"
  else
    build_collection_file "$1"
  fi
}
