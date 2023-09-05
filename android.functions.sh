adb.install () { adb install $1 ;}

adb.push () { adb push $1 $2 ;}

android.backup.personal () { 
	folder_root="/storage/emulated/0/"
	folders=$(adb shell ls $folder_root | grep -ie 'dcim\|pictures\|video\|download')
	for folder in $(echo -e "${folders}");do
		echo adb shell "ls -R ${folder_root}${folder}" | grep -vi '.*thumb*' | tr '\r' ' ' | while read file; do adb pull $file;done
	done
}

adb.pull () {

if [[ ($# -lt 1) || ("$*" =~ ".*--help.*") ]];then 
  show_help $funcstack[1]
  return
fi

local PREFIX=eval

for arg in "${@}";do
  shift
  if [[ "$arg" =~ '^--source-dir$|^-s$|@The source directory to pull files from - required' ]]; then local source_dir=$1;continue;fi
  if [[ "$arg" =~ '^--destination_dir$|^-d$|@The destination directory to store the pulled files - required' ]]; then local destination_dir=$1;continue;fi
  if [[ "$arg" =~ '^--device-id$|^-id$|@The android device id to target - required' ]]; then local android_device_id="${1}";continue;fi
  if [[ "$arg" =~ '^--dry$|@Dry run, only echo commands' ]]; then local PREFIX=echo;continue;fi
  set -- "$@" "$arg"
done

echo "Attempting to pull from ${source_dir}"

source_files=$(adb -s ${android_device_id} shell find "${source_dir}" -type f)

if ! (echo -e "${source_files}" | while read source_file;do 
    echo "Pulling ${source_file} ..."
    if [[ ! $($PREFIX adb -s ${android_device_id} pull "${source_file}" "${2}") ]];then
      err=true
    fi
done);then 
  err=true;
fi

if [[ -z $err ]];then
  echo "Success: Pulled all files from ${source_dir}"
  if [[ $PREFIX == 'echo' ]];then
    echo "Operating in Dry Mode, nothing left to do"
    return
  fi
  if confirm -p "Delete pulled files?";then
    echo "Deleting files from ${source_dir}"
    adb -s ${android_device_id} shell rm -f "${source_dir}/*."
  fi
else
  echo "Failed: There was at least one error when pulling files from ${source_dir}"
fi

}
