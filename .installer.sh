function bert.zsh.install() {

 argscount=$#
  allargs=${@}

  USAGE="""
  ${BASH_SOURCE[0]}
    --bert-bash-home|-b </path/to/dir>
    --update
    --help
  """

  BERT_ZSH_GIT_URL="https://github.com/berttejeda/bert.zsh.git"

  while (( $# )); do
      if [[ $1 =~ "'--bert-bash-git-url|^-g$'" ]]; then BERT_ZSH_GIT_URL=$2;fi    
      if [[ $1 =~ "'--bert-bash-home|^-b$'" ]]; then BERT_ZSH_HOME=$2;fi    
      if [[ $1 =~ "'^--update$'" ]]; then BERT_ZSH_UPDATE=true;shift;fi
      if [[ $1 =~ "'^--help$'" ]]; then help=true;shift;fi
      shift
  done

  if [[ -n $help ]];then
    echo -e "${USAGE}"
    return
  fi

  BERT_ZSH_HOME="${HOME}/.bert.zsh"

  echo -n "Checking if bert.zsh is installed ... "

  if [[ ! -d "${HOME}/.bert.zsh" ]];then
      echo 'Installing bert.zsh'
      git clone $BERT_ZSH_GIT_URL "${BERT_ZSH_HOME}"
      echo "source '${BERT_ZSH_HOME}/.installer.sh'" >> "${HOME}/.zshrc"
  elif [[ (-d "${BERT_ZSH_HOME}") && ($BERT_ZSH_UPDATE) ]];then
      echo -n "updating bert.zsh ... "
      pushd "${PWD}"
      cd "${BERT_ZSH_HOME}"
      git clean -f
      git checkout .
      git pull
      echo "done"
      popd
  else
      echo 'no need to install or update'
  fi

  echo "Commencing imports!"

  for script in ${BERT_ZSH_HOME}/*.sh; do
  start=`date +%s`
  if eval source $script;then
      end=`date +%s`
      runtime=$((end-start))      
      echo -e "${green}${runtime}s: Imported ${script}${reset}"
  else
      echo -e "${red}Failed to import ${script}${reset}"
  fi
  done
}

bert.zsh.install

echo -e "${yellow}Wassup home skillet!${reset}"
echo -e "You are logged in as ${bold}${USER-$USERNAME}${reset}"
echo -e "Today's date is `date "+%A %d.%m.%Y %H:%M, %Z %z"`"