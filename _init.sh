if [[ "$OSTYPE" =~ ".*darwin.*" ]];then
  os_is_osx=true
elif [[ "$OSTYPE" =~ ".*linux.*" ]];then
  os_is_linux=true
elif [[ "$OSTYPE" =~ ".*msys.*" ]];then
  os_is_windows=true
fi

if [[ -n $os_is_windows ]];then
  if [[ -z $EDITOR_PATH ]];then
    export EDITOR_PATH="C:\Program Files\Sublime Text\subl.exe"
  fi
else
  export EDITOR_PATH=${EDITOR_PATH-$(which subl)}
fi  

export EDITOR_COMMAND="${EDITOR_COMMAND-'${EDITOR_PATH}' -a}"
export EDITOR_COMMAND_W_WAIT="${EDITOR_COMMAND_W_WAIT-'${EDITOR_PATH}' -w}"

function edit() { 
  eval "${EDITOR_COMMAND}" "'${*}'"
}

# per-directory automation routines
cd() { builtin cd "$@" &&
if [ -f ".dir-exec.sh" ]; then
   source ".dir-exec.sh"
fi
}

a() { alias $1=cd\ $PWD; }

topuniq(){ sort|uniq -c|sort "${@:--rn}"; }

if [ -t 1 ] ; then
  red='\033[0;31m'
  green='\033[0;32m'
  blue='\033[0;34m'
  black='\033[0;30m'
  yellow='\033[0;33m'  
  reset='\033[0m' # reset to no color
  nc='\033[0m' # reset to no color
else
  red=''
  green=''
  blue=''
  yellow=''
  black=''
  reset=''
  nc=''
fi

function confirm() {
  
  if [[ "$*" =~ ".*--help.*" ]];then 
    show_help $funcstack[1]
    return
  fi

  local PREFIX=eval
  local response

  for arg in "${@}";do
    shift
    if [[ "$arg" =~ '^--prompt$|^-p$|@The message to prompt with' ]]; then local msg=$1;continue;fi
    if [[ "$arg" =~ '^--graphical$|@Confirm via GUI - optional' ]]; then local via_gui=true;continue;fi
    if [[ "$arg" =~ '^--dry$|@Dry run, only echo commands' ]]; then local PREFIX=echo;continue;fi
    if [[ "$arg" =~ '^--help$|@Show Help' ]]; then help=true;continue;fi
    set -- "$@" "$arg"
  done  

  if [[ (-n $via_gui) && ("${os_is_osx}" == "true") ]];then  
    process='''
      on run argv
        display dialog "Proceed?" buttons {"Yes", "No"}
      end run  
    '''
    response=$(osascript - < <(echo -e "${process}"))
    if echo "${response}" | grep -qE ".*[yY][eE][sS]|[yY].*"; then
      return 0
    else
      return 1
    fi
  else
    local msg="${"${msg}":-Are you sure?} [y/N] "
    read "response?${msg}"
    case "$response" in
    [yY][eE][sS]|[yY]) (exit 0) ;;
    *) (exit 1) ;;
    esac
  fi
}


# Accepts a prefix, ANSI-control format string, and message. Primarily meant for
# building other output functions.
message() {
  local prefix="$1"
  local ansi_format="$2"
  local message=''
  if [[ -z "$3" ]]; then
    read -r -d '' message
  else
    message="$3"
  fi
  local padding="$(echo "$prefix" | perl -pe 's/./ /g')"
  message="$(echo "$message" | perl -pe "s/^/$padding/ unless 1")"
  printf "%b%s %s%b\n" "$ansi_format" "$prefix" "$message" "$FMT_NONE" >&2
}

# Accepts a message either via stdin or as the first argument. Does not exit.
info() {
  message '==>' "$FMT_BOLD" "$@"
}

# Accepts a message either via stdin or as the first argument. Does not exit.
warn() {
  message 'WARNING:' "$FMT_YELLOW" "$@"
}

# Accepts a message either via stdin or as the first argument. Does not exit.
fatal() {
  message 'FATAL:' "$FMT_RED" "$@"
}

# Like `fatal`, but also exits with non-zero status.
abort() {
  fatal "$1"
  exit 1
}

# Indents the given text (via stdin). Defaults to two spaces, takes optional
# argument for number of spaces to indent by.
indent() {
  local num=${1:-2}
  local str="$(printf "%${num}s" '')"
  perl -pe "s/^/$str/"
}


#@ colors
#@ common
#@ prompt
#@ confirm

#@ colors
#@ common
#@ prompt
#@ confirm


function create_params(){
  echo -e '''
  while (( $# )); do
      for param in "${!params[@]}";do
          if [[ "$1" =~ "$param" ]]; then
              var=${param//-/_};
              var=${var%|*};
              var=${var//__/};
              if [[ $var ]];then
                  declare ${var%|*}+="${2}";
              else
                  eval "local ${var%|*}=${2}";
              fi;
          fi;
      done;
  shift;
  done
  '''
}

function show_help(){

  local arg_pattern=$(whence -f $1 | egrep -i '(if \[\[ .\$arg)')
  echo -e "${arg_pattern}" | while read arg;do
    local pattern=$(cut -d@ -f1 <<< ${arg##*=~})
    local help_txt=$(cut -d@ -f2 <<< ${arg##*=~})
    echo $pattern ${help_txt//]/}
  done
}

help(){
    #
    # Display Help/Usage
    #
    echo -e "Usage: ${1}"
    params="${2}"
    for param in "${!params[@]}";do
        if [[ $param != 0 ]];then
          echo "param: ${param} ${params[${param}]}"
        fi
    done
}

function secret.set(){
  echo -n "Enter in value for the variable '${1}': "
  eval "export $1=\$(read -s value;echo \$value)"
}