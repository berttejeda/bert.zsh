# PS1='\[\033[0;32m\]\[\033[0m\033[0;32m\]\u\[\033[0;36m\] @ \w\[\033[0;32m\]\n[$(git branch 2>/dev/null | grep "^*" | cut -c 2-)\[\033[0;32m\] ]\[\033[0m\033[0;32m\] \$\[\033[0m\033[0;32m\]\[\033[0m\]'

ZSH_THEME_GIT_PROMPT_PREFIX="%{$fg[white]%}("
ZSH_THEME_GIT_PROMPT_SUFFIX="%{$fg[white]%})%{$reset_color%}"
ZSH_THEME_GIT_PROMPT_DIRTY="*"
ZSH_THEME_GIT_PROMPT_CLEAN=""

# %~ is the current working directory relative to the home directory
PROMPT='[$FG[228]%~%{$reset_color%}]'
PROMPT+=' $(git_prompt_info)'
PROMPT+=' %(?.$FG[154].$FG[009])€%{$reset_color%} '


git.configure.global.hooks.only_pr(){

  USAGE="""
  Description: Sets the global pre-commit hook to disallow
  merging directly into branch, according to branch name pattern
  Usage:
    ${FUNCNAME[0]} [--branch-pattern|-p <pattern1|pattern2|pattern3>]
  """

  # args
  num_args=$#
  allargs=$*
  
  while (( $# )); do
    if [[ "$1" =~ "^--branch-pattern$|^-p$" ]]; then branch_pattern="${2}";shift;fi
    if [[ "$1" =~ "^--help$|^-h$" ]]; then help=true;fi
    shift
  done
  
  # Display help if applicable
  if [[ (-n $help) || (-z $branch_pattern) ]];then 
    echo -e "${USAGE}"
    return
  fi

  global_hooks_dir="${HOME}/.githooks"
  global_pre_commit_hook="${global_hooks_dir}/pre-commit"

  echo "Setting git global hooks dir to ${global_hooks_dir}"
  git config --global core.hooksPath "${global_hooks_dir}"
  echo "Checking for global hooks dir: ${global_hooks_dir}"
  if [[ ! -d "${global_hooks_dir}" ]];then
    echo "Creating global hooks dir: ${global_hooks_dir}"
    mkdir -p "${global_hooks_dir}"
  else
    echo "Global hooks dir already present"
  fi

ONLY_PR_CONTENT="""#!/usr/bin/env bash
IGNORE_PRECOMMIT=\${IGNORE_PRECOMMIT-false}

if [[ \$IGNORE_PRECOMMIT == "true" ]];then
  exit 0
fi

branch=\"\$(git rev-parse --abbrev-ref HEAD)\"

branch_pattern=\"${branch_pattern}\"


if [[ \"\${branch}\" =~ "\$branch_pattern" ]]; then
  echo \"PRE-COMMIT VIOLATION: You can't commit directly to branches matching \${branch_pattern}\"
  exit 1
fi
"""

echo "Checking for global pre-commit hook: ${global_pre_commit_hook}"

if [[ ! -f "${global_pre_commit_hook}" ]];then
  echo "Creating global pre-commit hook: ${global_pre_commit_hook}"
  echo -e "${ONLY_PR_CONTENT}" > "${global_pre_commit_hook}"
else
  echo "Global pre-commit hook file already present: ${global_pre_commit_hook}"
fi

}

git.set.tracking(){


  USAGE="""
  Description: Sets the remote tracking for the current branch
  If now arguments specified, it will set the remote to 'origin'
  Usage:
    ${FUNCNAME[0]} [--origin|-o <name_of_origin>]
  """
  # args
  num_args=$#
  allargs=$*
  
  while (( $# )); do
    if [[ "$1" =~ "^--origin$|^-o$" ]]; then origin_name="${2}";shift;fi
    if [[ "$1" =~ "^--help$|^-h$" ]]; then help=true;fi
    shift
  done
  
  # Display help if applicable
  if [[ (-n $help) ]];then 
    echo -e "${USAGE}"
    return
  fi

  current_branch_name=$(git rev-parse --abbrev-ref HEAD)
  git branch --set-upstream-to=${origin_name-origin}/${current_branch_name} ${current_branch_name}

}

git.log.by_file(){

  COMMITS=$(git log --oneline | awk '{print $1}')
  for COMMIT in $COMMITS; do
      #echo $COMMIT
      FILES=$(git show --name-only --oneline $COMMIT| egrep -v ^$COMMIT)
      for FILE in $FILES; do
          echo "$COMMIT:$FILE"
      done
  done
  
}

git.branches.clean(){

  # args
  num_args=$#
  allargs=$*
  
  while (( $# )); do
    if [[ "$1" =~ "^--older-than$|^-o$" ]]; then older_than="${2}";shift;fi
    if [[ "$1" =~ "^--help$|^-h$" ]]; then help=true;fi
    shift
  done
  
  # Display help if applicable
  if [[ (-n $help) || ($num_args -lt 1) ]];then 
    help ${FUNCNAME[0]} "${params}";
    return
  fi
  
  branches=$(git branch | grep ${USERNAME-USER} | awk '{print $NF}')
  
  if [[ -n $branches ]];then
    for branch in $branches;do 
      current_branch_age=$(date -d $(echo $branch | cut -d/ -f4) +%s)
      vs_branch_age=$(date -d "${older_than}" +%s)
      branch_target=${branch//origin\//}
      if [ $vs_branch_age -ge $current_branch_age ];
      then
        echo "Deleting ${branch_target}"
        git branch -D ${branch_target}
      else
        echo "Not deleting ${branch_target} as it is not older than ${older_than}"
      fi     
    done
  else
    echo "No branches found"
  fi

}


git.branch.size(){

  git rev-list HEAD |                     # list commits
  xargs -n1 git ls-tree -rl |             # expand their trees
  sed -e 's/[^ ]* [^ ]* \(.*\)\t.*/\1/' | # keep only sha-1 and size
  sort -u |                               # eliminate duplicates
  awk '{ sum += $2 } END { print sum }'

}

git.preview.markdown() {
  PREFIX=eval
  declare -A params=(
  ["--markdown-file|-f$"]="[Markdown-formatted file]"
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
  $PREFIX grip ${markdown_file} -b
}

git.wincred(){
  git config --global credential.helper wincred
}

git.biggest() {

  git rev-list --all --objects | \
  sed -n $(git rev-list --objects --all | \
  cut -f1 -d' ' | \
  git cat-file --batch-check | \
  grep blob | \
  sort -n -k 3 | \
  tail -n40 | \
  while read hash type size; do
       echo -n "-e s/$hash/$size/p ";
  done) | \
  sort -n -k1
}

git.branch.list() {
  for branch in `git branch -r | grep -v HEAD`;do echo -e `git show --format="%ai %ar by %an" $branch | head -n 1` \\t$branch; done | sort -r;
}

git.issue.branch.create (){

  if [[ ($# -lt 1) || ("$*" =~ ".*--help.*") ]];then 
    show_help $funcstack[1]
    return
  fi

  local PREFIX=eval

  for arg in "${@}";do
    shift
    if [[ "$arg" =~ '^--branch-name$|^-b$|@Name of the Git Branch - required' ]]; then local branch_name=$1;continue;fi
    if [[ "$arg" =~ '^--branch-prefix$|^-p$|@Prefix to use for the git branch' ]]; then local branch_prefix=$1;continue;fi
    if [[ "$arg" =~ '^--branch-type$|^-t$|@Type of branch, e.g. feature, bugfix, hotfix - required' ]]; then local branch_type=$1;continue;fi
    if [[ "$arg" =~ '^--change-context$|^-c$|@Name of the change context, e.g. IAM - required' ]]; then local change_context=$1;continue;fi
    if [[ "$arg" =~ '^--dry$|@Dry run, only echo commands' ]]; then local PREFIX=echo;continue;fi
    set -- "$@" "$arg"
  done

  # Display help if insufficient args
  if [[ $# -lt 3 ]];then show_help $funcstack[1];return;fi
  # DRY RUN LOGIC
  dtm=$(date +%Y%m%d.%H%M)
  default_branch_name=$(git rev-parse --abbrev-ref HEAD)
  if [[ -z $branch_prefix ]];then
    branch_prefix=${USERNAME-$USER}
  fi
  final_branch_prefix=${branch_prefix:l}
  final_branch_name=${final_branch_prefix}-${branch_name-$default_branch_name}-${branch_type}-${dtm}-${change_context}
  $PREFIX git checkout -b ${final_branch_name}
}

git.branch.status (){
  git for-each-ref --format="%(refname:short) %(upstream:short)" refs/heads | \
  while read local remote
  do
      [ -z "$remote" ] && continue
      git rev-list --left-right ${local}...${remote} -- 2>/dev/null >/tmp/git_upstream_status_delta || continue
      LEFT_AHEAD=$(grep -c '^<' /tmp/git_upstream_status_delta)
      RIGHT_AHEAD=$(grep -c '^>' /tmp/git_upstream_status_delta)
      echo "$local (ahead $LEFT_AHEAD) | (behind $RIGHT_AHEAD) $remote"
  done
}

function git.release_notes()
{

  # defaults
  local PREFIX=eval
  local remote_name=origin
  local end_tag_or_commit=$(git rev-parse --short HEAD)

  for arg in "${@}";do
    shift
    if [[ "$arg" =~ '^--start-tag-or-commit$|^-s$|@Tag Name to Start From - required' ]]; then local start_tag_or_commit=$1;continue;fi
    if [[ "$arg" =~ '^--remote-name$|^-r$|@Name Of Your Remote Git Repo' ]]; then local remote_name=$1;continue;fi
    if [[ "$arg" =~ '^--end-tag-or-commit$|^-e$|@Tag Name to End At' ]]; then local end_tag_or_commit=$1;continue;fi
    if [[ "$arg" =~ '^--dry$|@Dry run, only echo commands' ]]; then local PREFIX=echo;continue;fi
    set -- "$@" "$arg"
  done
  
  if [[ ($# -lt 1) || (-z $start_tag_or_commit) || ("$*" =~ ".*--help.*") ]];then 
    show_help $funcstack[1]
    return
  fi

  # DRY RUN LOGIC
  git_branch=$(git rev-parse --abbrev-ref HEAD)
  repo_url=$(git config --get remote.${remote_name}.url | sed 's/\.git//' | sed 's/:\/\/.*@/:\/\//');
  git log --no-merges ${start_tag_or_commit}..${end_tag_or_commit} --format="* %s [%h]($repo_url/commit/%H)" | sed 's/      / /'
} 

git.c () { git commit -m "${1}" ;}

git.redo.commit () {
  [ $# -lt 1 ] && echo "Usage: ${FUNCNAME[0]} <file/dir>" >&2 && return 1
  git add $1
  git commit --amend
  git push -f
}

git.permissions.fix () { cd $(git rev-parse --show-toplevel);sudo chown -R $USER . ;}

git.logs(){
  [ $# -lt 1 ] && echo "Usage: ${FUNCNAME[0]} [date] <branch (optional)>" >&2 && return 1
  # git log --since="${1}" --pretty=oneline $2
  git log --since="${1}" --pretty=format:"%h %ad | %s%d [%an]" --graph --date=short $2

}

git.log.tree(){
  # See the history of the current branch laid out in a tree
  local all=""
  while (( $# )); do
      if [[ "$1" =~ ".*--all*" ]]; then local all="--all";fi
      shift
  done
  git log --graph --pretty=oneline --abbrev-commit --decorate --color $all
}

git.get.last.commit () {
  if [[ -z $1 ]];then branch=$(git rev-parse --abbrev-ref HEAD);else branch=$1;fi
  git log -n 1 --pretty=format:%H $branch
}

git.get.first.commit () {
  if [[ -z $1 ]];then branch=$(git rev-parse --abbrev-ref HEAD);else branch=$1;fi
  git rev-list --max-parents=0 $branch
}

git.reset(){
  git reset --hard origin/$(git rev-parse --abbrev-ref HEAD) && git pull origin $(git rev-parse --abbrev-ref HEAD)
}

git.search(){

  USAGE="""Usage: 
    ${FUNCNAME[0]} [pattern]
  """

  # args
  num_args=$#
  allargs=$*
  
  while (( $# )); do
    if [[ "$1" =~ "^--search-string$|^-s$" ]]; then search_string="${2}";shift;fi
    if [[ "$1" =~ "^--case-sensitive$|^-c$" ]]; then case_sensitive=true;fi
    if [[ "$1" =~ "^--help$|^-h$" ]]; then help=true;fi
    shift
  done
  
  # Display help if applicable
  if [[ (-n $help) || ($num_args -lt 1) ]];then 
    echo -e "${USAGE}"
    return
  fi

  if [[ $allargs =~ "' --- '" ]];then
    extraparams=${allargs##*---}
  fi

  git log -E --grep="${search_string?Must specify search string}" $extraparams
}

git.show() {
    cd $1
    branch=`git branch 2> /dev/null | grep -e ^* | sed -E  s/^\\\\\*\ \(.+\)$/\\\\\1/`
    if [ -n "`git status 2> /dev/null | grep 'nothing to commit'`" ]; then
        status="\e[32mok\e[0m"
    else
        status="\e[31mmodified\e[0m"
    fi
    echo -e "\e[1m$1\e[0m (\e[34m$branch\e[0m): \e[1m$status\e[0m"
    cd ..
}

git.whatchanged(){
  [ $# -lt 1 ] && echo "Usage: ${FUNCNAME[0]} <date?" >&2 && return 1
  git whatchanged --since="${1}" --pretty=oneline
}

git.branches.remote() {
  # https://gist.github.com/jasonrudolph/1810768
  for branch in `git branch -r | grep -v HEAD`;do 
    echo -e `git show --format="%ci %cr" $branch | head -n 1` \\t$branch; 
  done | sort -r
}

git.show.commits() {
  # from https://github.com/trimstray/the-book-of-secret-knowledge?tab=readme-ov-file#tool-git
  # git log --oneline --decorate --graph --all
  git log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit
}

git.clean() {
  echo "Resetting local git repo ..."
  cd $(git rev-parse --show-toplevel)
  git clean -f .
  git checkout .
  if ! $(git checkout ${1-master} 2> /dev/null);then 
    git checkout ${1-main}
  fi
  git pull
  echo "Done!"
}

git.cherry-pick.selective() {
    local OPTIND=1
    local dry_run=false

    while getopts "n" opt; do
        case "$opt" in
            n) dry_run=true ;;
            *) echo "Usage: git-selective-pick [-n] <source-branch> <start-point> [exclude-pattern]"; return 1 ;;
        esac
    done
    shift $((OPTIND-1))

    local source_branch="$1"
    local start_point="$2"
    local exclude_pattern="$3"

    if [[ -z "$source_branch" || -z "$start_point" ]]; then
        echo "Usage: git-selective-pick [-n] <source-branch> <start-point> [exclude-pattern]"
        return 1
    fi

    # 1. Get the list of commits
    local commit_list
    commit_list=$(git rev-list "${start_point}..${source_branch}" --reverse --oneline | \
        if [[ -n "$exclude_pattern" ]]; then
            grep -vEi "$exclude_pattern"
        else
            cat
        fi)

    if [[ -z "$commit_list" ]]; then
        echo "No commits found matching those criteria."
        return 0
    fi

    echo "------------------------------------------"
    if [ "$dry_run" = true ]; then
        echo "DRY RUN MODE: The following would be picked:"
    else
        echo "Commencing cherry-pick for:"
    fi
    echo "------------------------------------------"
    echo "$commit_list"
    echo "------------------------------------------"

    if [ "$dry_run" = true ]; then
        echo "Dry run complete. No changes made."
        return 0
    fi

    # 2. Extract hashes
    local hashes
    hashes=$(echo "$commit_list" | awk '{print $1}')

    # 3. Handle Word Splitting for both shells
    # Bash splits on spaces by default; Zsh requires explicit expansion.
    if [ -n "$ZSH_VERSION" ]; then
        git cherry-pick ${=hashes}
    else
        git cherry-pick $hashes
    fi
}

#--------------------------------------------------------------------------------------------------#
# Git shortcuts
alias git.undocommit='git reset --soft HEAD^'
alias git.recommit='git commit -c ORIG_HEAD'
alias git.ll='ls -alF'
alias git.la='ls -A'
alias git.l='ls -CF'
alias git.ls.untracked='git ls-files --others --exclude-standard'
alias git.ls.delta='(git diff-index --name-only HEAD --;git ls-files --others --exclude-standard)'
alias git.status='git status --short'
alias git.up='git smart-pull'
alias git.L='git smart-log'
alias git.m='git smart-merge'
alias git.b='git branch -rav'
alias git.fmod='git status --porcelain -uno | cut -c4-' # Only the filenames of modified files
alias git.today='git log --since="6am" --pretty=oneline'
alias git.umod='git status --porcelain -u | cut -c4-' # Only the filenames of unversioned files
alias gad='git add'
alias gci='git commit -v'
alias gst='git status'
alias gco='git checkout'
alias gb='git branch -v'
alias gba='git branch -a -v'
alias gl='git pull'
alias gcn='git clone'
alias gp='git push'
alias gP='git push --set-upstream origin $(git rev-parse --abbrev-ref HEAD)'
alias gdiff='git diff | mate'
alias gup='git svn rebase'
alias gm='git checkout master'
alias gd='git diff master'
