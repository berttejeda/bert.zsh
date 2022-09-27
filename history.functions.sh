# history
# "Adjusting HISTORY behavior ..."
alias rr="!:0 $1 !!:$"
alias rr='!!:gs/$1/$2'

bindkey -s '^T' 'uptime'
bindkey '^R' history-incremental-search-backward


history.search () { history | grep -i $1 | cut -d' ' -f8- | grep -vi history | sort -u; } 

history.recall() { 
    if [ ! $@ ] ; then 
       echo "Usage: ${FUNCNAME[0]} <PATTERN>" 
       echo "where PATTERN is a part of previously given command" 
    else 
        history | grep $@ | grep -vi "${FUNCNAME[0]}" | more; 
    fi 
}

history.servers.retrieve(){
    trap '[ "$?" -eq 0 ] || echo -e "Looks like something went wrong. \nPlease Review step ´$STEP´. \nPress any key to continue..."' return 1
    if [[ ($# -lt 2) ]]; then 
        echo "Usage: ${FUNCNAME[0]} --server [HOST_NAME]";return 1
    fi  
    PREFIX=""
    while (( $# )); do
        if [[ "$1" =~ ".*--server.*" ]]; then local HOST_NAME=$2;fi    
        if [[ "$1" =~ ".*--dry.*" ]]; then local PREFIX="echo";fi
        shift
    done
    STEP="GETALLHISTORY"
    $PREFIX ssh $HOST_NAME "for dir in $(ls / | grep -e '^home\|^root');do sudo find /$dir -type f -iname '.bash_history' -exec cat {} \;;done" | tee -a "${HOST_NAME}.history.log"
    return 0
}

