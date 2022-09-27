export TF_PLUGIN_CACHE_DIR="$HOME/.terraform.d/plugin-cache"
if [[ ! -d "${TF_PLUGIN_CACHE_DIR}" ]];then
  mkdir -p "${TF_PLUGIN_CACHE_DIR}"
fi

function tvm()
{ 
  TERRAFORM_BIN=$(which terraform)
  TERRAFORM_DIR=${TERRAFORM_DIR-${TERRAFORM_BIN%/*}}
  PLATFORM=${PLATFORM-'windows_amd64'}
    
  if [ -z "$1" ]
  then
    echo -e """Current:
    ${TERRAFORM_BIN}"""
    return
  fi
  
  if [ "$1" == "checkupdates" ]
  then
    curl -s https://releases.hashicorp.com/terraform/?_ga=2.242595202.1674966510.1509370400-1120994974.1509370400 | awk '/\s*<a href="\/terra/ { start=index($2,">")+1;end=index($2,"<"); tver=substr($2,start, end - start); print tver; }'
    return
  fi
  
  if [ "$1" == "install" ]
  then
    if [ -z "$2" ]
    then
      echo "You must specify a terraform version!"
      return
    fi

    SOURCE="https://releases.hashicorp.com/terraform/$2/terraform_$2_$PLATFORM.zip"
    TARGET="$TERRAFORM_DIR/$2"
    CURL_OUTPUT="./terraform_$2_$PLATFORM.zip"

    mkdir $TARGET
    pushd $TARGET

    echo -e " $SOURCE -> $TARGET..."
    curl --output $CURL_OUTPUT $SOURCE
    unzip $CURL_OUTPUT

    popd

    return
  fi

  if [ "$1" == "remove" ]
  then
    TARGET="$TERRAFORM_DIR/$2"

    echo "Removing $TARGET..."

    if [ -z "$2" ]
    then
      return
    fi

    rm -r $TARGET


  fi

  if [ ! -d "$TERRAFORM_DIR/$1" ]
  then
   echo -e "Terraform version $1 not found"
   return
  fi

  echo Setting Terraform Version $1

  for d in $(ls -l $TERRAFORM_DIR | awk '/^d/{print $9;}')
  do
    DIR="$TERRAFORM_DIR/$d"
    ESCAPED_DIR=$(echo $DIR | sed -e 's/\//\\\//g')
    SED_CMD="s/$ESCAPED_DIR://"
    PATH=$(echo $PATH | sed -e "$SED_CMD")
  done

  PATH="$(echo -e "$TERRAFORM_DIR/$1/:$PATH")"  
} 

function tf.plan.nocolor {
  USAGE="""
  Description: Outputs terraform plan to output file
  Usage:
    ${FUNCNAME[0]} [--plan-prefix|-pp] <plan_prefix> --- <extra_args>
  Examples:
    ${FUNCNAME[0]} -pp vpc-changes
    ${FUNCNAME[0]} -pp vpc-changes --- -var myvar=myvalue
  """

  # args
  local num_args=$#
  local allargs=$*
  
  while (( $# )); do
    if [[ "$1" =~ "^--plan-name-prefix$|^-pp$" ]]; then local plan_prefix="-${2}";shift;fi
    if [[ "$1" =~ "^--help$|^-h$" ]]; then local help=true;fi
    shift
  done
  
  # Display help if applicable
  if [[ -n $help ]];then 
    echo -e "${USAGE}"
    return
  fi

  if [[ $allargs =~ "' --- '" ]];then
    nargs=${allargs##*---}
    local nargs=${nargs//--dry/}
  fi

  local plan_prefix_w_branch="$(git rev-parse --abbrev-ref HEAD | head -1)"
  if [[ -n $plan_prefix ]];then
   local effective_plan_prefix="${plan_prefix_w_branch}${plan_prefix}"
  else
   local effective_plan_prefix="${plan_prefix_w_branch}"
  fi
  local plan_file=${effective_plan_prefix}-plan-$(date +%Y-%m-%d-%H-%M).txt
  echo "Saving output of 'terraform plan' to ${plan_file}"
  terraform plan -no-color $nargs | tee ${plan_file}
}

# function tf.variables.sort {
#   USAGE="""
#   Description: Alphabetically sorts a terraform variables file according to variable names
#   Usage:
#     ${FUNCNAME[0]} [--vars-file|-f] <variables_file> --- <extra_args>
#   Examples:
#     ${FUNCNAME[0]} -f variables.tf
#   """
# 
#   # args
#   num_args=$#
#   allargs=$*
#   plan_prefix=
#   
#   while (( $# )); do
#     if [[ "$1" =~ "^--vars-file$|^-f$" ]]; then vars_file="${2}";shift;fi
#     if [[ "$1" =~ "^--help$|^-h$" ]]; then help=true;fi
#     shift
#   done
#   
#   # Display help if applicable
#   if [[ -n $help ]];then 
#     echo -e "${USAGE}"
#     return
#   fi
# 
#   if [[ $allargs =~ "' --- '" ]];then
#     nargs=${allargs##*---}
#     nargs=${nargs//--dry/}
#   fi
#   
#   echo "Sorting ${vars_file} ..."
#   hcltool.py ${vars_file} | jq . | json2hcl
#   return
#   
#     process="from __future__ import print_function
# import sys
# import re
# 
# # this regex matches terraform variable definitions
# # we capture the variable name so we can sort on it
# pattern = r'(variable \")([^\"]+)(\" {[^{]+})'
# 
# def process(content):
#     # sort the content (a list of tuples) on the second item of the tuple
#     # (which is the variable name)
#     matches = sorted(re.findall(pattern, content), key=lambda x: x[1])
# 
#     # iterate over the sorted list and output them
#     for match in matches:
#         print(''.join(map(str, match)))
# 
#         # don't print the newline on the last item
#         if match != matches[-1]:
#             print()
# 
# 
# # check if we're reading from stdin
# if not sys.stdin.isatty():
#     stdin = sys.stdin.read()
#     if stdin:
#         process(stdin)
# 
# # process any filenames on the command line
# with open('${vars_file}') as f:
#   process(f.read())
# "
#   sorted_content=$(python -c "$process" | tr -d '\r')
#   echo "${sorted_content}" | tee ${vars_file}
# 
# }

alias tf=terraform
alias tf.apply="terraform apply"
