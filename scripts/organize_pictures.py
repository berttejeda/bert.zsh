#!/usr/bin/env python3
"""Organize photos and videos into four-month folders by creation date.

    <destination>/2026_January-April/
    <destination>/2026_May-August/
    <destination>/2026_September-December/

The creation date is taken from the first source that has one:

  1. Embedded metadata. With exiftool installed (recommended; brew install
     exiftool) this covers photos and videos: EXIF DateTimeOriginal, QuickTime
     CreationDate (the recording time, kept even when a video is re-exported),
     then EXIF/QuickTime CreateDate. Without exiftool, Pillow reads EXIF
     DateTimeOriginal/DateTimeDigitized from images only.
  2. A date in the filename, e.g. IMG_20260214_103000.jpg, PXL_20260214_...,
     IMG-20260214-WA0001.jpg, Screenshot 2026-02-14 at 10.30.00.png
  3. The file system: birth (creation) time, or the modification time if that
     is earlier (copying a file resets its birth time but keeps its mtime)

Existing files are never overwritten: an identical file at the destination is
skipped, and a different file with the same name gets a numeric suffix.
"""

import argparse
import datetime
import filecmp
import logging
import os
import re
import json
import shutil
import subprocess
import sys
from pathlib import Path

DEFAULT_EXTENSIONS = 'jpg,jpeg,png,heic,heif,gif,tif,tiff,dng,cr2,nef,arw,mp4,mov,m4v,avi'

PERIODS = (
    ('January-April', range(1, 5)),
    ('May-August', range(5, 9)),
    ('September-December', range(9, 13)),
)

# EXIF creation tags in the Exif sub-IFD, most to least preferred: DateTimeOriginal, DateTimeDigitized.
# (IFD0 DateTime is when the file was last edited, so it's deliberately not used.)
EXIF_IFD = 0x8769
EXIF_DATE_TAGS = (0x9003, 0x9004)
EXIF_DATE_FORMAT = '%Y:%m:%d %H:%M:%S'

# exiftool tags, most to least preferred. CreationDate is QuickTime's capture time; CreateDate is
# EXIF DateTimeDigitized for images and the (possibly re-encoded) movie header time for videos.
EXIFTOOL_DATE_TAGS = ('DateTimeOriginal', 'CreationDate', 'CreateDate', 'MediaCreateDate')
EXIFTOOL_BATCH = 500

# YYYY[sep]MM[sep]DD, optionally followed by HH[sep]MM[sep]SS, not embedded in a longer run of digits
FILENAME_DATE = re.compile(
    r'(?<!\d)((?:19|20)\d{2})[-_.]?(0[1-9]|1[0-2])[-_.]?(0[1-9]|[12]\d|3[01])'
    r'(?:[-_. T]?(?:at[ _])?([01]\d|2[0-3])[-_.:h]?([0-5]\d)[-_.:m]?([0-5]\d)\d{0,3})?(?!\d)')

log = logging.getLogger('organize_pictures')


def load_pillow():
    """Return PIL.Image, or None if Pillow is missing. Registers HEIC support when available."""
    try:
        from PIL import Image
    except ImportError:
        log.warning('Pillow not installed (pip install Pillow); using file timestamps only')
        return None
    try:
        from pillow_heif import register_heif_opener
        register_heif_opener()
    except ImportError:
        pass
    return Image


def parse_metadata_date(value):
    """Parse an EXIF/QuickTime style date ('2026:08:08 18:31:13-04:00'), or None for blank/zero dates."""
    try:
        ts = datetime.datetime.strptime(str(value).strip('\x00 ')[:19], EXIF_DATE_FORMAT)
    except ValueError:
        return None
    return ts if ts.year >= 1900 else None


def exiftool_dates(paths):
    """Return {path: (timestamp, tag)} for every path with a usable metadata date, via batched exiftool calls."""
    dates = {}
    # QuickTimeUTC: QuickTime CreateDate is stored in UTC; convert it to local time like the other tags
    cmd = ['exiftool', '-json', '-q', '-q', '-api', 'QuickTimeUTC=1', '-charset', 'filename=utf8',
           *[f'-{t}' for t in EXIFTOOL_DATE_TAGS], '-@', '-']
    for i in range(0, len(paths), EXIFTOOL_BATCH):
        batch = paths[i:i + EXIFTOOL_BATCH]
        proc = subprocess.run(cmd, input='\n'.join(map(str, batch)), capture_output=True, text=True)
        try:
            records = json.loads(proc.stdout or '[]')
        except json.JSONDecodeError:
            log.warning(f'Could not parse exiftool output: {proc.stderr.strip()}')
            continue
        for rec in records:
            for tag in EXIFTOOL_DATE_TAGS:
                ts = parse_metadata_date(rec.get(tag, ''))
                if ts:
                    dates[Path(rec['SourceFile'])] = (ts, tag)
                    break
    return dates


def exif_timestamp(image_module, path):
    """Creation time from EXIF via Pillow, or None."""
    if image_module is None:
        return None
    try:
        with image_module.open(path) as im:
            exif = im.getexif().get_ifd(EXIF_IFD)
            for tag in EXIF_DATE_TAGS:
                value = exif.get(tag)
                if not value:
                    continue
                ts = parse_metadata_date(value)
                if ts:
                    return ts
                log.debug(f'Unparseable EXIF date {value!r} in {path}')
    except Exception as e:  # not an image Pillow can read, corrupt file, etc.
        log.debug(f'No EXIF for {path}: {e}')
    return None


def filename_timestamp(path, now):
    """Creation time from a date embedded in the filename, or None. Impossible and future dates are ignored."""
    for m in FILENAME_DATE.finditer(path.stem):
        parts = [int(g) for g in m.groups() if g is not None]
        try:
            ts = datetime.datetime(*parts)
        except ValueError:  # e.g. 2026-02-30
            continue
        if ts <= now:
            return ts
    return None


def filesystem_timestamp(path):
    """Birth time, or the modification time if earlier (copies get a new birth time but keep their mtime).

    Network shares (NFS/SMB) often report a birth time of 0, i.e. 1970-01-01; such values are ignored.
    """
    st = path.stat()
    stamps = [t for t in (st.st_mtime, getattr(st, 'st_birthtime', 0)) if t > 0]
    return datetime.datetime.fromtimestamp(min(stamps) if stamps else st.st_mtime)


def creation_timestamp(path, metadata, image_module, now):
    """Return (timestamp, source) using embedded metadata, then the filename, then the file system.

    metadata is the exiftool result for all files, or None to read EXIF with Pillow instead.
    """
    if metadata is not None:
        if path in metadata:
            ts, tag = metadata[path]
            return ts, f'metadata {tag}'
    else:
        ts = exif_timestamp(image_module, path)
        if ts:
            return ts, 'exif'
    ts = filename_timestamp(path, now)
    if ts:
        return ts, 'filename'
    return filesystem_timestamp(path), 'filesystem'


def period_dir(ts):
    for name, months in PERIODS:
        if ts.month in months:
            return f'{ts.year}_{name}'


def unique_destination(src, dest, planned):
    """Return a free path for src at dest, or None if an identical file is already there.

    planned holds targets claimed earlier in this run, so dry runs report the same names a real run would use.
    """
    candidate, n = dest, 1
    while candidate.exists() or candidate in planned:
        if candidate.exists() and filecmp.cmp(src, candidate, shallow=False):
            return None
        candidate = dest.with_name(f'{dest.stem}_{n}{dest.suffix}')
        n += 1
    return candidate


def find_media(source, extensions, recursive, skip_under):
    pattern = '**/*' if recursive else '*'
    for path in sorted(source.glob(pattern)):
        if not path.is_file() or path.name.startswith('.'):
            continue
        if path.suffix.lower().lstrip('.') not in extensions:
            continue
        # Don't reprocess files already sorted into a period folder of the destination
        if any(parent in skip_under for parent in path.parents):
            continue
        yield path


def build_parser(prog):
    p = argparse.ArgumentParser(
        prog=prog,
        description='Organize photos & videos into YEAR_January-April / YEAR_May-August / '
                    'YEAR_September-December folders by creation date '
                    '(from EXIF, else a date in the filename, else the file system).',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=f'''Examples:
  {prog} -s ~/Downloads/phone -d ~/Pictures --dry-run
  {prog} -s ~/Downloads/phone -d ~/Pictures -r
  {prog} -s . -x jpg,heic --copy''')
    p.add_argument('-s', '--source-media-path', type=Path, default=Path('.'),
                   help='folder containing the media files (default: current directory)')
    p.add_argument('-d', '--destination-media-path', type=Path,
                   help='folder under which period folders are created (default: the source folder)')
    p.add_argument('-x', '--media-file-extension', default=DEFAULT_EXTENSIONS,
                   help='comma-separated extensions, case-insensitive (default: %(default)s)')
    p.add_argument('-r', '--recursive', action='store_true', help='search the source folder recursively')
    p.add_argument('-n', '--dry-run', action='store_true', help='show what would happen without changing anything')
    p.add_argument('-c', '--copy', action='store_true', help='copy files instead of moving them')
    p.add_argument('--debug', action='store_true', help='verbose logging')
    return p


def main(argv=None):
    prog = os.environ.get('ORGANIZE_PICTURES_PROG') or Path(sys.argv[0]).name
    args = build_parser(prog).parse_args(argv)
    logging.basicConfig(level=logging.DEBUG if args.debug else logging.INFO,
                        format='%(levelname)s: %(message)s', stream=sys.stdout)

    source = args.source_media_path.expanduser().resolve()
    destination = (args.destination_media_path or args.source_media_path).expanduser().resolve()
    if not source.is_dir():
        log.error(f'Source folder not found: {source}')
        return 2
    extensions = {e.strip().lower().lstrip('.') for e in args.media_file_extension.split(',') if e.strip()}
    skip_under = {d for d in destination.glob('*_*') if d.is_dir() and d.name.split('_', 1)[1] in dict(PERIODS)}

    files = list(find_media(source, extensions, args.recursive, skip_under))
    if shutil.which('exiftool'):
        log.info(f'Reading metadata from {len(files)} files with exiftool ...')
        metadata, image_module = exiftool_dates(files), None
    else:
        log.warning('exiftool not found (brew install exiftool); video metadata dates will not be read')
        metadata, image_module = None, load_pillow()
    verb = 'copy' if args.copy else 'move'
    tag = '[dry-run] ' if args.dry_run else ''
    counts = {'done': 0, 'skipped': 0, 'failed': 0}
    created, planned = set(), set()
    now = datetime.datetime.now()

    for path in files:
        ts, ts_source = creation_timestamp(path, metadata, image_module, now)
        target_dir = destination / period_dir(ts)
        target = unique_destination(path, target_dir / path.name, planned)
        if target is None:
            log.info(f'{tag}Skip {path} (identical file already in {target_dir.name})')
            counts['skipped'] += 1
            continue
        planned.add(target)

        if not target_dir.exists() and target_dir not in created:
            log.info(f'{tag}Create {target_dir}')
            created.add(target_dir)
        log.info(f'{tag}{verb.capitalize()} {path} -> {target} (created {ts:%Y-%m-%d}, from {ts_source})')
        if args.dry_run:
            counts['done'] += 1
            continue
        try:
            target_dir.mkdir(parents=True, exist_ok=True)
            (shutil.copy2 if args.copy else shutil.move)(path, target)
            counts['done'] += 1
        except OSError as e:
            log.error(f'Failed to {verb} {path}: {e}')
            counts['failed'] += 1

    past = 'copied' if args.copy else 'moved'
    log.info(f"{tag}{counts['done']} {'would be ' + past if args.dry_run else past}, "
             f"{counts['skipped']} skipped, {counts['failed']} failed")
    return 1 if counts['failed'] else 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
