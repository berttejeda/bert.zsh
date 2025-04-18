# python # conda

# conda on Windows (vanilla install)
if [[ $os_is_windows ]]; then
  if [[ -f /c/ProgramData/Anaconda3/Scripts/conda.exe ]];then
    alias conda='/c/ProgramData/Anaconda3/Scripts/conda.exe'
  fi
  if [[ -f /c/ProgramData/Anaconda3/Scripts/activate ]];then
    alias activate='source /c/ProgramData/Anaconda3/Scripts/activate'
  fi
fi

if [[ $os_is_windows ]]; then
  conda.fix.windows(){
    sed -i "s|^C:.*|$(cygpath $(cat $(which conda) | egrep 'C:\\') | tr '\n' ' ')|" $(which conda)
    sed -i "s|^source C:.*|$(cygpath $(cat $(which activate) | egrep 'C:\\') | tr '\n' ' ')|" $(which activate)
  }
fi

conda.init(){
  conda init bash
}

conda.install(){
  echo "Downloading Anaconda python env manager ..."
  if [[ "$OSTYPE" =~ ".*darwin.*" ]]; then installer_url="https://repo.continuum.io/archive/Anaconda2-4.2.0-MacOSX-x86_64.sh";fi
  if [[ "$OSTYPE" =~ ".*linux.*" ]]; then installer_url="https://repo.continuum.io/archive/Anaconda3-4.2.0-Linux-x86_64.sh";fi
  if wget -q ${installer_url} ; then
    echo "Download finished. Installing Anaconda python env manager ..."
    bash Anaconda3-4.2.0-Linux-x86_64.sh -b && rm -f Anaconda3-4.2.0-Linux-x86_64.sh
  fi
}

conda.env.create(){

  BINARY=conda
  if ! [[ ($(type /usr/{,local/}{,s}bin/${BINARY} 2> /dev/null)) || ($(which $BINARY)) ]];then
    echo "This function requires $BINARY, see installation instructions: https://www.continuum.io/downloads"
    return 1
  fi

  local USAGE="""Usage: ${FUNCNAME[0]} 
  --environment-name|-n <virtualenv_name> 
  --python-version$ |-v <python_version> (optional)
  """

  # args
  local num_args=$#
  local allargs=$*
  local python_version_default=3.7

  while (( $# )); do
    if [[ "$1" =~ "^--environment-name$|^-n$" ]]; then local environment_name="${2}";shift;fi
    if [[ "$1" =~ "^--python-version$|^-v$" ]]; then local python_version="${2}";shift;fi
    if [[ "$1" =~ "^--help$|^-h$" ]]; then local help=true;fi
    shift
  done
  
  # Display help if applicable
  if [[ (-n $help) || (-z $environment_name) ]];then 
    echo -e "${USAGE}"
    return
  fi

  conda create --name "${environment_name}" python="${python_version-$python_version_default}"

}

conda.env.remove(){
  BINARY=conda
  if ! [[ ($(type /usr/{,local/}{,s}bin/${BINARY} 2> /dev/null)) || ($(which $BINARY)) ]];then
    echo "This function requires $BINARY, see installation instructions: https://www.continuum.io/downloads"
    return 1
  fi

  local USAGE="""Usage: ${FUNCNAME[0]} 
  --environment-name|-n <virtualenv_name> 
  """

  # args
  local num_args=$#
  local allargs=$*
  local python_version_default=3.7

  while (( $# )); do
    if [[ "$1" =~ "^--environment-name$|^-n$" ]]; then local environment_name="${2}";shift;fi
    if [[ "$1" =~ "^--help$|^-h$" ]]; then local help=true;fi
    shift
  done
  
  # Display help if applicable
  if [[ (-n $help) || (-z $environment_name) ]];then 
    echo -e "${USAGE}"
    return
  fi

  conda env remove --name "${environment_name}"

}

conda.env.list(){
  BINARY=conda
  if ! [[ ($(type /usr/{,local/}{,s}bin/${BINARY} 2> /dev/null)) || ($(which $BINARY)) ]];then
    echo "This function requires $BINARY, see installation instructions: https://www.continuum.io/downloads"
    return 1
  else
    envs=$(conda info --envs | grep -v '^#' | awk '{print $1}')
    echo "${envs}"
  fi
}

# define some handy aliases
for conda_environment in $(ls $(which python | cut -d/ -f1-5)); do 
  namespace="conda.env.activate.";method=${conda_environment//\//}
  alias "${namespace}${method}=conda.env.activate ${conda_environment//\//}"
done

conda.env.activate(){
  if [ $# -lt 1 ]; then echo "Usage: ${FUNCNAME[0]} <virtualenv_name>"; return 1; fi
  BINARY=conda
  environment_name=$1
  if ! [[ ($(type /usr/{,local/}{,s}bin/${BINARY} 2> /dev/null)) || ($(which $BINARY)) ]];then
    echo "This function requires $BINARY, see installation instructions: https://www.continuum.io/downloads"
    return 1
  else
    if [[ $os_is_windows ]];then
        python_path=$(conda info --envs | grep $environment_name | awk '{print $2}')        
        python_path_as_posix=$(cygpath -u $python_path)
        python_scripts_path="${python_path}/Scripts"
        python_scripts_path_as_posix=$(cygpath -u $python_scripts_path)
        export PATH="${python_path_as_posix}:${python_scripts_path_as_posix}:${PATH}"
    elif [[ ($os_is_osx) || ($os_is_linux) ]];then
        source activate $environment
    fi    
  fi
}

pip.freeze.requirements(){
  requirements_file=${1-requirements.txt}
  pip freeze -r "${requirements_file}" | sed '/freeze/,$ d'
}