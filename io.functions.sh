system.keep-alive(){
  #
  # Keep the PC alive, will prevent screen lock and sleep.
  # Works by pressing Print Screen every 60 minutes, side effect is that a screenshot will overwrite the clipboard contents
  #
  if [[ $os_is_windows ]];then
  command='''
  clear host;
  $opt = (Get-Host).PrivateData;
  $opt.WarningBackgroundColor = "DarkCyan";
  $opt.WarningForegroundColor = "white";
  $progressBar = ":| ",":[]"
  Do {[void][System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms");
  [System.Windows.Forms.SendKeys]::SendWait("+{F15}");
    ForEach ($c in $progressBar){
      Write-Host -NoNewLine $c`b`b`b;
      Start-Sleep "'"${1-10}"'"
    }
  } While ($true)
  '''
  eval powershell -noprofile -command "'${command}'"
  elif [[ $os_is_osx ]];then
    screen -dm caffeinate -d
  fi
}

function io.marquee(){
  # Scroll a message across the terminal like a marquee
  local text="${1:-  SYSTEM ALERT: UPDATE REQUIRED  }"
  local width=${2:-15}
  local padded_text="${text}${text}"
  local i

  tput civis
  trap "tput cnorm; exit" INT TERM

  for ((i=0; i<${#text}; i++)); do
    # Extract a slice of the text and rewrite the line
    printf "\r[%s] %s" "$(date '+%F %T')" "${padded_text:$i:$width}"
    sleep 0.15
  done

  tput cnorm
  printf "\n"
}