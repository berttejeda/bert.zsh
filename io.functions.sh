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