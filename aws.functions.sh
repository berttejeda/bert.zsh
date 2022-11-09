function aws.profile.list(){
  aws configure list-profiles
}

function aws.profile.login(){

  argscount=$#
  allargs=${@}

  USAGE="""
  ${FUNCNAME[0]}
    -p <aws_profile_name>
    --help
  """

  while (( $# )); do
      if [[ "$1" =~ "^-p$" ]]; then aws_profile_name=$2;fi    
      if [[ "$1" =~ "^--help$" ]]; then help=true;fi    
      shift
  done

  if [[ (-n $help) || ($argscount -lt 1) ]];then
    echo -e "${USAGE}"
    return
  fi

  echo "Logging into ${aws_profile_name?'Must specify profile name (-p)'}"

  if $(aws configure list-profiles | grep -q "${aws_profile_name}" 2>/dev/null);then
    aws sso login --profile "${aws_profile_name}"
    export AWS_PROFILE="${aws_profile_name}"
    return
  else
    echo "The specified profile '${aws_profile_name}' does not exist"
    return 1
  fi
  unset aws_profile_name
}

function aws.secrets.create(){

  argscount=$#
  allargs=${@}

  USAGE="""
  ${FUNCNAME[0]}
    -n <secret_name>
    -d <secret_description>
    -s <secret_string>
    [-p <aws_profile>]
    --help
  """

  while (( $# )); do
      if [[ "$1" =~ "^-n$" ]]; then secret_name=$2;fi    
      if [[ "$1" =~ "^-d$" ]]; then secret_description=$2;fi    
      if [[ "$1" =~ "^-s$" ]]; then secret_string=$2;fi    
      if [[ "$1" =~ "^-p$" ]]; then aws_profile_arg="--profile ${2}";fi    
      if [[ "$1" =~ "^--help$" ]]; then help=true;fi    
      shift
  done

  if [[ (-n $help) || ($argscount -lt 1) ]];then
    echo -e "${USAGE}"
    return
  fi

  echo "Creating ${secret_name?'Must specify the secrent name (-n)'}"
  aws ${aws_profile_arg} secretsmanager create-secret \
  --name ${secret_name} \
  --description "${secret_description?'Must specify description for the secrent (-d)'}" \
  --secret-string "${secret_string?'Must specify the value for the secret (-s)'}"
}

function aws.ec2.list.volumes(){

  if [[ ($# -lt 1) || ("$*" =~ ".*--help.*") ]];then 
    show_help $funcstack[1]
    return
  fi

  local PREFIX=eval

  for arg in "${@}";do
    shift
    if [[ "$arg" =~ '^--ec2-ebs-name-pattern$|^-n$|@The naming pattern to use in your search - required' ]]; then local ec2_ebs_vol_naming_pattern=$1;continue;fi
    if [[ "$arg" =~ '^--dry$|@Dry run, only echo commands' ]]; then local PREFIX=echo;continue;fi
    set -- "$@" "$arg"
  done

  if [[ -z $ec2_ebs_vol_naming_pattern ]];then
    show_help $funcstack[1]
  fi

  $PREFIX """
  aws ec2 describe-volumes --filters \
  'Name=tag:Name,Values=${ec2_ebs_vol_naming_pattern}' \
  --query 'Volumes[*].{Name:Tags[?Key==\`Name\`].Value[] | [0],VolumeId: VolumeId, AttachedInstanceId: Attachments[0].InstanceId, AvailabilityZone: AvailabilityZone, Size: Size}' \
  --output yaml | tee"""
}

function aws.ec2.list(){

  if [[ ($# -lt 1) || ("$*" =~ ".*--help.*") ]];then 
    show_help $funcstack[1]
    return
  fi

  local PREFIX=eval

  for arg in "${@}";do
    shift
    if [[ "$arg" =~ '^--ec2-name-pattern$|^-n$|@The naming pattern to use in your search - required' ]]; then local ec2_naming_pattern=$1;continue;fi
    if [[ "$arg" =~ '^--dry$|@Dry run, only echo commands' ]]; then local PREFIX=echo;continue;fi
    set -- "$@" "$arg"
  done

  if [[ -z $ec2_naming_pattern ]];then
    show_help $funcstack[1]
  fi

  $PREFIX """
  aws ec2 describe-instances \
  --filters 'Name=tag:Name,Values=${ec2_naming_pattern}' \
  --query 'Reservations[].Instances[].{ID:InstanceId, Name:Tags[?Key==\`Name\`].Value[] | [0],State:State.Name}' \
  --output yaml | tee"""
}

function aws.ec2.clone {

  argscount=$#
  allargs=${@}

  USAGE="""
  ${FUNCNAME[0]}
    -i <instance_name>
    -r <region_name>
    --help
  """

  while (( $# )); do
      if [[ "$1" =~ "^-i$" ]]; then awsinstanceid=$2;fi    
      if [[ "$1" =~ "^-r$" ]]; then region=$2;fi    
      if [[ "$1" =~ "^--help$" ]]; then help=true;fi    
      shift
  done

  if [[ (-n $help) || ($argscount -lt 1) ]];then
    echo -e "${USAGE}"
    return
  fi

  export AWS_DEFAULT_REGION=${region?Error: Must define region}
  ami=$(aws ec2 describe-instances --instance-ids $awsinstanceid | grep INSTANCES | awk '{print $7}')
  privatekey=$(aws ec2 describe-instances --instance-ids $awsinstanceid | grep INSTANCES | awk '{print $10}')
  securitygroup=$(aws ec2 describe-instances --instance-ids $awsinstanceid | grep SECURITYGROUPS | awk '{print $2}')
  instancetype=$(aws ec2 describe-instances --instance-ids $awsinstanceid | grep INSTANCES | awk '{print $9}')
  subnet=$(aws ec2 describe-instances --instance-ids $awsinstanceid | grep NETWORKINTERFACES | awk '{print $9}')

  awsinstancedata=$(aws ec2 run-instances --image-id $ami --key-name $privatekey --security-group-ids $securitygroup --instance-type $instancetype --subnet-id $subnet)
  awsinstanceid=$(echo $awsinstancedata | awk '{print $9}')

  # AWS CLI sucks and doesn't return error codes so have to look for a valid id
  if [[ "$awsinstanceid" == i-* ]]; then 
    echo -e "\t\tSuccessfully created. Instance ID: $awsinstanceid";
  else 
    echo -e "\t\tSomething went wrong. Check your configuration."; 
    return; 
  fi 
  echo -e "\t\tWaiting for ec2 instance to come up..."
  aws ec2 wait instance-running --instance-ids $awsinstanceid
  echo -e "\t\Instance is up and ready"
}

