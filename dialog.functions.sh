# dialog

# Directory of this library, used to locate helper scripts
BERT_ZSH_DIALOG_DIR="${${(%):-%x}:A:h}"

proceed(){
read PROCEED
if [[ $PROCEED =~ ".*n.* || $PROCEED = ''" ]]; then \
  echo 'Terminating by your request...';return 1;fi
if [[ $PROCEED =~ ".*y.*" ]]; then echo 'Proceeding ...';fi  
}

imessage.search(){
  # Thin wrapper; see scripts/imessage_search.py --help for all options
  local script="${BERT_ZSH_DIALOG_DIR}/scripts/imessage_search.py"
  if [[ ! -f "${script}" ]];then
    echo "imessage.search: cannot find ${script}" >&2
    return 1
  fi
  IMESSAGE_SEARCH_PROG="${0}" python3 "${script}" "$@"
}
