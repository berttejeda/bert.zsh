# media
## imagemagick
image.split () {
  if [[ $# -lt 1 ]]; then echo "Usage: ${FUNCNAME[0]} <imagefile>";return 1;fi  
  image=$1
  BINARY=convert
  if ! [[ ($(type /usr/{,local/}{,s}bin/${BINARY} 2> /dev/null)) || ($(which $BINARY)) ]];then
    echo "This function requires $binary, brew install imagemagick"
    return 1
  else
    convert "${image}" -crop 2x3@ +repage +adjoin "${image%.*}_%d.${image#*.}"
  fi  
}

## music
mp3.play () {
  [ $# -lt 1 ] && echo "Usage: ${FUNCNAME[0]} <folderofmp3s>" && return 1
  folder=$1
  ls "${folder}"/*.mp3 | while read mp3;do echo playing $mp3;afplay "$mp3";done
}

mp3.play.next () { pkill afplay ;}

youtube.get.mp3() {

  if [ $# -lt 1 ]; then echo "Usage: ${FUNCNAME[0]} <url>";return 1;fi
  binary=youtube-dl
  if ! (which $binary || type -all $binary || [ -f $binary ]) >/dev/null 2>&1;then
    echo "This function requires $binary, see installation instructions: https://www.continuum.io/downloads"
    return 1
  else
    $binary --extract-audio --audio-format mp3 "${1}"
  fi
}

youtube.get.mp4() {
  if [[ $# -lt 1 ]]; then echo "Usage: ${FUNCNAME[0]} <url>";return 1;fi
  binary=youtube-dl
  for path in `echo $PATH | tr ':' '\n'`;do type ${path}/${binary} 2>/dev/null;done
  if ! [[ ($(type /usr/{,local/}{,s}bin/${BINARY} 2> /dev/null)) || ($(which $BINARY)) ]];then
    echo "This function requires $binary, sudo pip install youtube-dl"
    return 1
  else
    youtube-dl -f mp4 "${1}"
  fi
}

video.mux()
{
  [ $# -lt 2 ] && echo "Usage: ${FUNCNAME[0]} [video.ext] [audio.ext] [output.ext](optional) (--match_length)" && return 1
  video=$1
  audio=$2
  video_filename=${1%.**}
  video_extention=${1#**.}
  if [[ "$*" =~ ".*--match_length.*" ]];then
    audio_duration=$(ffprobe -i ${audio} -show_entries format=duration -v quiet -of csv="p=0")
    video_duration=$(ffprobe -i ${video} -show_entries format=duration -v quiet -of csv="p=0")
    muxed_filename="${video_filename%.**}_muxed"
    n_loops=$(echo "(${audio_duration} / ${video_duration}) + 1"|bc)
    >files.txt
    for i in $(seq 1 $n_loops); do echo -e "file ${video}"; done >> files.txt
    ffmpeg -i ${audio} -f concat -i files.txt -c:v copy -shortest ${muxed_filename}.${video_extention}
  else
    if [[ -z $3 ]];then muxed_filename="${video_filename%.**}_muxed";else muxed_filename=${3%.**}_muxed;fi
    muxed_output_file="${muxed_filename}.${video_extention}"
    if [[ ! -f "${video}" ]];then echo "I couldn't find ${video}";return 1;fi
    if [[ ! -f "${audio}" ]];then echo "I couldn't find ${audio}";return 1;fi
    ffmpeg -i "${video}" -i "${audio}" -c:v copy -shortest "${muxed_output_file}"
  fi
}


video.convert()
{
  [ $# -lt 1 ] && echo "Usage: ${FUNCNAME[0]} [file]" && return 1
  media_file=${1%.*}
  if [[ $os_is_windows ]];then
    pre=""
  else
    pre=screen.send
  fi
  if [[ "$1" =~ ".*mkv" ]];then
    screen.send ffmpeg -i "${$1}" -strict experimental -y -c copy -c:a aac -movflags +faststart -crf 22 "${media_file}.mp4"
  else
    screen.send ffmpeg -i $1 -vcodec h264 -acodec aac -strict -2 $media_file.mp4
  fi
}

video.to.images(){

  if [[ ($# -lt 1) || ("$*" =~ ".*--help.*") ]];then 
    show_help $funcstack[1]
    return
  fi

  local PREFIX=eval

  for arg in "${@}";do
    shift
    if [[ "$arg" =~ '^--video-file$|^-f$|@The video file to process - required' ]]; then local video_file=$1;continue;fi
    if [[ "$arg" =~ '^--output-dir$|^-d$|@Output directory, default is $video_file' ]]; then local output_dir=$1;continue;fi
    if [[ "$arg" =~ '^--output-image-batch-size$|^-z$|@Batch size used when grouping images, default is 100' ]]; then local image_batch_size=$1;continue;fi
    if [[ "$arg" =~ '^--clip-seek-time$|^-ss$|@Seeks to the timestamp specified in the video, default is 00:00:00' ]]; then local clip_seek_time=$1;continue;fi
    if [[ "$arg" =~ '^--clip-duration$|^-t$|@Specify the duration of the clip, e.g. 00:00:05 for 5 seconds' ]]; then local clip_duration_arg="-t ${1}";continue;fi
    if [[ "$arg" =~ '^--dry$|@Dry run, only echo commands' ]]; then local PREFIX=echo;continue;fi
    set -- "$@" "$arg"
  done  
  
  local output_dir=${output_dir-${video_file%%.*}}

  if ! [[ -d $output_dir ]];then 
    $PREFIX mkdir ${output_dir}
  fi


  $PREFIX docker run --rm -v $PWD/:/workdir --workdir /workdir jrottenberg/ffmpeg \
  -i ${video_file} -ss ${clip_seek_time-00:00:00} $clip_duration_arg \
  "${output_dir}/img_%03d.jpg"

  $PREFIX files.batch -p ${output_dir} -b ${image_batch_size-100} -n batch
}

mp4.compress()
{
  [ $# -lt 1 ] && echo "Usage: ${FUNCNAME[0]} [input_file] [output_file]" && return 1
  ffmpeg -y -i $1 -c:v libx264 -preset medium -b:v 555k -pass 1 -c:a libfdk_aac -b:a 128k -f mp4 /dev/null && \
  ffmpeg -i $1 -c:v libx264 -preset medium -b:v 555k -pass 2 -c:a libfdk_aac -b:a 128k $2
}

mp4.thumb() {
  [ $# -lt 1 ] && echo "Usage: ${FUNCNAME[0]} [input_file] [thumbnail]" && return 1  
  ffmpeg -loglevel panic -ss 00:00:01.500 -i "$1" -frames:v 1 "$2" 
}

media.organize() {

  process="import argparse;
from PIL import Image
from PIL.ExifTags import TAGS
from pathlib import Path, PurePath
import datetime
import logging
import logging.handlers
import coloredlogs
import os
import sys

class Logger:

  def __init__(self, **kwargs):
    env_debug_is_on = os.environ.get('WEBTERMINAL_DEBUG', '').lower() in [
    't', 'true', '1', 'on', 'y', 'yes']
    self.debug = kwargs.get('debug', False) or env_debug_is_on
    self.FORMAT_STR = '%(asctime)s %(name)s [%(levelname)s]: %(message)s'
    self.formatter = logging.Formatter(
      self.FORMAT_STR,
      datefmt='%Y-%m-%d %H:%M:%S'
    )
    self.logfile_path = kwargs.get('logfile_path')
    self.logfile_write_mode = kwargs.get('logfile_write_mode', 'a')

  def init_logger(self, name=None, debug=False):
    # Setup Logging
    logger = logging.getLogger(name)
    # TODO Find a better approach to this hacky method
    if '--debug' in ' '.join(sys.argv) or self.debug:
        logging_level = logging.DEBUG
    else:
        logging_level = logging.INFO
    logger.setLevel(logging_level)
    stdout_handler = logging.StreamHandler(sys.stdout)
    stdout_handler.setFormatter(self.formatter)
    logger.addHandler(stdout_handler)
    if self.logfile_path:
        # create one handler for print and one for export
        file_handler = logging.FileHandler(self.logfile_path, self.logfile_write_mode)
        file_handler.setFormatter(self.formatter)
        logger.addHandler(file_handler)
    coloredlogs.install(logger=logger,
                        fmt=self.FORMAT_STR,
                        level=logging_level)
    return logger

logger_obj = Logger()
logger = logger_obj.init_logger(__name__)

def parse_args(**kwargs):

  parser = argparse.ArgumentParser(description='organize pictures & videos')
  parser.add_argument('--source-media-path', '-s', help='Path to the source media files', required=True)
  parser.add_argument('--destination-media-path', '-d', help='Path under which source media files are to be stored', required=True)
  parser.add_argument('--media-file-extension', '-x', help='File extension for the source media files', default='jpg')
  parser.add_argument('--debug', action='store_true')
  parser.add_argument('--recursive','-r', action='store_true', help='Search recursively', default=False)
  return parser.parse_args()

args = parse_args()

source_media_path = Path(args.source_media_path).expanduser()
destination_media_path = Path(args.destination_media_path).expanduser()
media_file_extension = args.media_file_extension
recursive = args.recursive

organizational_index = {
    '{year}_January-April': [1,2,3,4],
    '{year}_May-August': [5,6,7,8],
    '{year}_September-December': [9,10,11,12]
}

# https://www.lifewithpython.com/2014/12/python-extract-exif-data-like-data-from-images.html
def get_exif_of_image(file):
    '''Get EXIF of an image if exists.

Function to retrieve EXIF data of the specified image
    @return exif_table Exif dictionary containing data
    '''
    im = Image.open(file)

    #Get Exif data
    #If it does not exist, it ends as it is. Returns an empty dictionary.
    try:
        exif = im._getexif()
    except AttributeError:
        return {}

    #Since the tag ID itself cannot be read by people, decode it
    #Store in table
    exif_table = {}
    for tag_id, value in exif.items():
        tag = TAGS.get(tag_id, tag_id)
        exif_table[tag] = value

    return exif_table

def get_destination_dir(year, month):
    for dir_name, index in organizational_index.items():
        if month in index:
            return dir_name.format(year=year)

video_file_suffixes = ['.mp4']
if recursive:
    media_files = Path(source_media_path).rglob(f'*.{media_file_extension}')
else:
    media_files = Path(source_media_path).glob(f'*.{media_file_extension}')
for media_file in media_files:
    if not media_file.is_file():
        logger.warning(f'{media_file} is not a file, skipping')
        continue
    if all([not media_file.suffix in video_file_suffixes, len(media_file.suffix) > 0]):
        try:
            exif = get_exif_of_image(media_file)
            if 'DateTimeOriginal' in exif:
                # strftime()Specify the format of the new name with
                media_create_date = exif['DateTimeOriginal']
                try:
                    media_timestamp = datetime.datetime.strptime(media_create_date, '%Y:%m:%d %H:%M:%S')
                except ValueError as e:
                    logger.warning(f'Failed to determine timestamp for {media_file} using exif data, resorting to fallback')
                    media_timestamp = datetime.datetime.fromtimestamp(media_file.lstat().st_mtime)
            else:
                logger.warning(f'No EXIF header for {media_file}')
                media_timestamp = datetime.datetime.fromtimestamp(media_file.lstat().st_mtime)
        except Exception as e:
            logger.warning(f'Failed to read exif data for {media_file}')
            media_timestamp = datetime.datetime.fromtimestamp(media_file.lstat().st_mtime)
    else:
        media_timestamp = datetime.datetime.fromtimestamp(media_file.lstat().st_mtime)
    media_year = media_timestamp.year
    media_month = media_timestamp.month
    media_destination_dir = get_destination_dir(media_year, media_month)
    if media_destination_dir:
        _media_destination_dir_obj = Path(media_destination_dir)
        media_destination_dir_obj = PurePath.joinpath(destination_media_path, _media_destination_dir_obj)
        media_file_dest = PurePath.joinpath(media_destination_dir_obj, media_file.name)
        if not media_destination_dir_obj.exists():
            media_destination_dir_obj.mkdir(parents=True)
        logger.info(f'Moving {media_file} to {media_file_dest.as_posix()}')
        media_file.rename(media_file_dest)
    else:
      logger.error('Could not determine destination for {media_file}')
"
  python -c "$process" $@
}
