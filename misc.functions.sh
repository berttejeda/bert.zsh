export BASH_PROFILE="~/.bash_profile"
alias profile.edit="${EDITOR_COMMAND} $BASH_PROFILE;echo Reloading bash profile;source $BASH_PROFILE && echo Reloading of bash profile was successful."
alias profile.reload="source $BASH_PROFILE || echo Reloading of bash profile was successful."
alias watch="watch "
alias recv='nc -4l 6502 | pv -ebr | tar -xvvpf -'
alias remind="export Reminders_List=Personal;remind.me to $*;export Reminders_List=Reminders;"
alias edit.pyqerc="${EDITOR_COMMAND} ~/.pyqerc"


function remind.me {
  if ! [[ "$OSTYPE" =~ ".*darwin.*" ]]; then echo "This works only on OSX";return 1;fi
  usage="""Usage: 
  ${FUNCNAME[0]}"""
  if [[ "$*" =~ ".*--help.*" ]];then echo -e "${usage}";return 0;fi
  osascript - $* <<END
    display dialog "REMINDER: DO THE THING NOW!" with title "ANNOYING ALERT" buttons {"Done", "Snooze"} default button "Snooze" with icon caution
    if button returned of result is "Snooze" then
        delay 300 -- waits 5 minutes
        run script (me) -- runs itself again
    end if
END
}