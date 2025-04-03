# productivity
function remind.me {

  if ! [[ "$OSTYPE" =~ ".*darwin.*" ]]; then 
    echo "This works only on OSX";
    return 1
  fi

  if [[ ($# -lt 1) || ("$*" =~ ".*--help.*") ]];then 
    
    show_help $funcstack[1]

    echo """
    Examples: 
      ${FUNCNAME[0]} -to 'Submit TPS reports' -d $(date +%D' '%H:%M:%S%p)
      or
      ${FUNCNAME[0]} to 'Submit TPS reports' -d 30 minutes
      or
      ${FUNCNAME[0]} to 'Submit TPS reports' -d 1 hour
      or
      ${FUNCNAME[0]} to 'Submit TPS reports' -d 5:00PM
      or
      Specifying a Reminders List:
        ${FUNCNAME[0]} to 'Submit TPS reports' -d 5:00PM --list Personal
    """
    return
  fi

  local PREFIX=eval
  local args=""

  for arg in "${@}";do
    shift
    if [[ "$arg" =~ '^--to-do$|^-to$|@What you want to be reminded about - required' ]]; then local to_do=$1;args="${args} ${1}";continue;fi
    if [[ "$arg" =~ '^--date$|^-d$|@The date or time you want to be reminded on - required' ]]; then local date_time=$1;args="${args} ${1}";continue;fi
    if [[ "$arg" =~ '^--list$|^-l$|@The reminders list you want to target - optional' ]]; then local list=$1;args="${args} ${1}";continue;fi
    if [[ "$arg" =~ '^--dry$|@Dry run, only echo commands' ]]; then local PREFIX=echo;continue;fi
    set -- "$@" "$arg"
  done

  echo $args

  return

  $PREFIX osascript - ${args}<<END
    on run argv
      set AppleScript's text item delimiters to " "
      set reminder_text to item 2 thru item -4 of argv as string
      if item -3 of argv equals "at" then
        set reminder_text to item 2 thru item -4 of argv as string
        set reminder_date to date (item -2 of argv & " " & item -1 of argv)
      else if item -1 of argv contains "minute" then
        set minutes to item -2 of argv * 60
        set reminder_date to (current date + minutes)
        -- display dialog reminder_date as string
      else if item -1 of argv contains "hour" then
        set minutes to item -2 of argv * 3600
        set reminder_date to (current date + minutes)
      else
        set reminder_date to date (item -2 of argv & " " & item -1 of argv)
      end if
      set current_date to (current date + 3600) as string
      tell application "Reminders"
        set Reminders_List to list "${list}"
        tell Reminders_List
          make new reminder at end with properties {name:reminder_text, due date:reminder_date, remind me date:reminder_date }
        end tell
      end tell
    end run
END
args=""
}

word.lookup () {
  PREFIX=eval
  declare -A params=(
  ["--word|-w$"]="[word]"
  ["--help|-h$"]="Display usage and exit"
  ["--dry"]="Dry Run"
  )
  # Display help if no args
  if [[ $# -lt 1 ]];then help ${FUNCNAME[0]} "${params}";return;fi
  # Parse arguments
  eval $(create_params)
  # Display help if applicable
  if [[ -n $help ]];then help ${FUNCNAME[0]} "${params}";return;fi
  # DRY RUN LOGIC
  if [[ -n $dry ]];then 
    PREFIX=echo
  fi  
  ${PREFIX} rundll32.exe WWEB32.DLL,ShowRunDLL "${word}"
}

word.translate()
{
  if [ $# -lt 1 ]; then echo "Usage: ${FUNCNAME[0]} <word> <language, e.g. es>"; return 1; fi
  process="from PyDictionary import PyDictionary;dictionary=PyDictionary();import sys;
args = sys.stdin.readlines()
word = str(args[0]).strip()
language = str(args[1]).strip() if len(args) > 1 else 'es'
print (dictionary.translate(word,language))"
  echo $1 | python -c "$process"
}

