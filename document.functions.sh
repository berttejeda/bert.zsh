# document

# bertdotcheater
alias cf="bert.cheater find"

# pdfgrep
pdf.search () { ls *.pdf | grep -i "${1}" | while read book;do echo $book;pdfgrep "$2" "${book}";done; }
pdf.grep(){ pdfgrep $1 $2 ; }
pdf.pillar_daily() { 
  pdfgrep 'E\.' $1 | head -6
  echo -e "Ok which errcode do you want to search for?"
  read search_term
  pdfgrep "${search_term}" $1 | awk '{print $1,$2,$(NF-1)}' | sort -k3 -n | grep -ve '^E\.'
}

excel.read () 
{ 
    usage="usage: ${FUNCNAME[0]} [-file:<excel_file>] [-sheets:'<sheet_name>;<sheet_name>'] [-columns:<colnum>,<colnum>,colnum,...] [-rcolumns:<colnum>-<colnum>]
[-filter:<filter1,filter2,...>] [-skip_rows:<num>] [-append:<column>,<string>] [-yaml] [--info]"
    if [[ $# -lt 1 ]];then echo $usage;return 0;fi
    if [[ "$*" =~ ".*--info.*" ]];then process="import xlrd;import sys;file = sys.stdin.read().split(':')[1].strip();xls=xlrd.open_workbook(file);print('Available Sheets:%s' % [(i, name) for i,name in enumerate(xls.sheet_names())])";echo $1 | python -c "$process";return 0;fi
    process="import re;import sys;import yaml;import json;import xlrd;import csv;import re;
def to_s(v):
  return [d.encode('utf-8') if not isinstance(d, (int, float, complex)) else str(int(d)) for d in v]
arguments = sys.stdin.read()
# arguments = '-file:/git/viper-config-cox/rdz/current/rdz_phxn.xlsx -sheets:RDZ Stream Information -filter:8871338682467360163 -dict:yes -skip_rows:2'
arguments = dict(item.strip().replace('-','',1).split(':',1) if re.search('^-',item) else item.strip().split(':',1) for item in re.split('\s-',arguments))
write_out = False
if arguments.get('wo'):
  csv_file = open('out.csv', 'wb')
  wr = csv.writer(csv_file, quoting=csv.QUOTE_ALL)
  write_out = True
excel_files=arguments['file'].split(';')
sheets=arguments['sheets'].split(';')
if sheets[0] == '*':
  for excel_file in excel_files:
    xls=xlrd.open_workbook(excel_file)
    sheets = ['%s' % s for s in xls.sheet_names()]
no_header = False if not arguments.get('no_header') else True
to_dict = False if not arguments.get('to_dict') else True
to_yaml = False if not arguments.get('to_yaml') else True
to_json = False if not arguments.get('to_json') else True
skip_rows = 0 if not arguments.get('skip_rows') else int(arguments['skip_rows'])
columns = None if not arguments.get('columns') else [int(c) for c in arguments['columns'].split(',')]
start, end  = (None,None) if arguments.get('columns') or not arguments.get('rcolumns') else [int(c) for c in arguments['rcolumns'].split('-')]
filters = None if not arguments.get('filter') else re.split(';|,| |\n',str(arguments['filter']))
append = '' if not arguments.get('append') else arguments.get('append').split(',')
data = []
for xlsheet in sheets:
  _sh = [xlrd.open_workbook(excel_file.strip()).sheet_by_name(xlsheet) for excel_file in excel_files]
  for sh in _sh:
    _sh_data = [sh.row_values(row)[start:end] for row in [range(sh.nrows)[skip_rows:]]]
quit()
c = 0

for l in data:
  if filters:
      if any([[d for d in l if re.search(''.join(f),d)] for f in filters]):
          if append:
              print(','.join(['{}{}'.format(d[1],append[1]) if d[0] == int(append[0]) else d[1] for d in enumerate(l)]))
              if write_out:
                wr.writerow(['{}{}'.format(d[1],append[1]) if d[0] == int(append[0]) else d[1] for d in enumerate(l)])
          else:
              if to_yaml:
                print(yaml.safe_dump(dict([(l[0],l[1:])]), default_flow_style=False))
              elif to_dict:
                print(dict([(l[0],l[1:])]))
              elif to_json:
                print(json.dumps(dict([(l[0],l[1:])])))
              else:
                print(','.join(l[:end]))
              if write_out:
                wr.writerow(l[:end])
  else:
      if append:
          print(','.join(['{}{}'.format(d[1],append[1]) if d[0] == int(append[0]) else d[1] for d in enumerate(l)]))
          if write_out:
            wr.writerow(['{}{}'.format(d[1],append[1]) if d[0] == int(append[0]) else d[1] for d in enumerate(l)])
      else:
        if to_dict:
          print(dict(l[0],l[1:]))
        elif to_json:
          print(json.dumps(dict(l[0],l[1:])))
        elif to_yaml:
          print('printing out yaml')
          print(yaml.dumps(dict(l[0],l[1:])))
        else:
          print(','.join(l[:end]))
        if write_out:
          wr.writerow(l[:end])

# data=dict(zip(header.split(','),rows.split(',')))
# print '\n'.join(['{}:{}'.format(d,v) for d,v in data.iteritems() if all([d,v])])
";
    echo $* | python -c "$process"
}

excel.search () {
    if [[ "$*" =~ ".*--help.*" ]] || [[ $# -lt 2 ]]; then
        echo -e "usage: ${FUNCNAME[0]} [path/to/file.xlsx] [search_term] [optional_column_name]"
        return 1
    fi

    local file_path="${1}"
    local term="${2}"
    local col="${3:-None}"

    local process="import pandas as pd; import os; import sys;
filepath = os.path.expanduser('${file_path}')
term = '${term}'
column = '${col}' if '${col}' != 'None' else None

try:
    df = pd.read_excel(filepath)
    if column:
        if column in df.columns:
            results = df[df[column].astype(str).str.contains(term, case=False, na=False, regex=True)]
        else:
            print(f'Error: Column \"{column}\" not found.'); sys.exit(1)
    else:
        results = df[df.apply(lambda row: row.astype(str).str.contains(term, case=False, na=False).any(), axis=1)]

    if not results.empty:
        print(results.to_markdown(index=False))
    else:
        print('No results found.')
except Exception as e:
    print(f'Error: {e}'); sys.exit(1)"

    python3 -c "${process}"
}

xmind.convert(){
  [ $# -lt 1 ] && echo "Usage: ${FUNCNAME[0]} [/path/to/xmind_document] >" >&2 && return 1
  ruby "${XMorgPath}" -t markdown -o "${1}.md" "${1}" --pandoc-options="--atx-headers"
}

image.to.markdown() {
  if [ $# -lt 1 ]; then echo "Usage: ${FUNCNAME[0]} <image_file> [width] [height]"; return 1; fi
  local width="${2:-50%}" height="${3:-50%}"
  process="import base64;import sys;file=sys.stdin.readlines()[0].replace('\n','');
image=open(file,'rb');image_read=image.read();image.close()
image_64=base64.encodebytes(image_read) if sys.version_info>=(3,9) else base64.encodestring(image_read)
image_string=image_64.decode('utf-8').replace('\n','')
w='${width}';h='${height}'
if w and h:
    print('<img src=\"data:image/png;base64,'+image_string+'\" width=\"'+w+'\" height=\"'+h+'\" />')
elif w:
    print('<img src=\"data:image/png;base64,'+image_string+'\" width=\"'+w+'\" />')
elif h:
    print('<img src=\"data:image/png;base64,'+image_string+'\" height=\"'+h+'\" />')
else:
    print('![image](data:image/png;base64,'+image_string+')')
"
  echo $1 | python -c "$process"
}

xml.to.json() {
  if [ $# -lt 1 ]; then echo "Usage: ${FUNCNAME[0]} <file>"; return 1; fi
  process="import json;import sys;import xmltodict;file=line=sys.stdin.readlines()[0].replace('\n','');
def convert(xml_file, xml_attribs=True):
    with open(xml_file, 'rb') as f:
        d = xmltodict.parse(f, xml_attribs=xml_attribs)
        print json.dumps(d, indent=4)
convert(file)
"
  echo $1 | python -c "$process"
}

document.spell-check() {
  if [ $# -lt 1 ]; then echo "Usage: ${FUNCNAME[0]} [file]"; return 1; fi
  aspell check "${1}" ${backup-'--dont-backup'}
}

document.words.unique() {

  local process
  process=$(cat << 'EOF'
import argparse
import glob
import os
import re
import shutil
import subprocess
import sys
from collections import Counter

parser = argparse.ArgumentParser(
    prog="document.words.unique",
    description="Create a list of unique words across one or more text or PDF files.\nPDFs are read with pypdf if installed, otherwise the pdftotext CLI.",
    epilog="""examples:
  document.words.unique notes.txt
  document.words.unique docs/*.md README.md
  document.words.unique 'docs/**/*.md'            # quoted: expanded recursively by python
  document.words.unique docs -r '\\.(md|txt)$'     # walk a directory, keep paths matching regex
  cat notes.txt | document.words.unique -""",
    formatter_class=argparse.RawDescriptionHelpFormatter
)
parser.add_argument("paths", nargs="+", help="Files, directories, or glob patterns to read ('-' for stdin). Quote a pattern to let python expand it ('**' recurses).")
parser.add_argument("--regex", "-r", help="Only read files whose path matches this regular expression.")
parser.add_argument("--output", "-o", help="Path to write the word list to (default: stdout).")
parser.add_argument("--case-sensitive", "-c", action="store_true", help="Treat words differing only in case as distinct.")
parser.add_argument("--count", "-n", action="store_true", help="Prefix each word with its number of occurrences.")
parser.add_argument("--by-frequency", "-f", action="store_true", help="Sort by occurrence count (descending) instead of alphabetically.")

args = parser.parse_args()

try:
    path_filter = re.compile(args.regex) if args.regex else None
except re.error as e:
    print(f"Error: invalid regex: {e}", file=sys.stderr)
    sys.exit(1)

def expand(path):
    if path == "-":
        return [path]
    path = os.path.expanduser(path)
    if os.path.isdir(path):
        return sorted(os.path.join(root, name) for root, _, names in os.walk(path) for name in names)
    if glob.has_magic(path):
        return sorted(p for p in glob.glob(path, recursive=True) if os.path.isfile(p))
    return [path]

files = []
for path in args.paths:
    matches = expand(path)
    if not matches:
        print(f"Warning: no files match {path}", file=sys.stderr)
    for f in matches:
        if path_filter and f != "-" and not path_filter.search(f):
            continue
        if f not in files:
            files.append(f)

if not files:
    print("Error: no files to process", file=sys.stderr)
    sys.exit(1)

def read_pdf(path):
    try:
        from pypdf import PdfReader
        return "\n".join(page.extract_text() or "" for page in PdfReader(path).pages)
    except ImportError:
        pass
    pdftotext = shutil.which("pdftotext")
    if pdftotext:
        result = subprocess.run([pdftotext, "-q", path, "-"], capture_output=True, text=True)
        if result.returncode != 0:
            raise OSError(f"pdftotext failed on {path}")
        return result.stdout
    raise OSError(f"cannot read {path}: install pypdf (pip install pypdf) or pdftotext (brew install poppler)")

texts = []
for f in files:
    try:
        if f == "-":
            texts.append(sys.stdin.read())
        elif f.lower().endswith(".pdf"):
            texts.append(read_pdf(f))
        else:
            with open(f, encoding="utf-8", errors="replace") as fh:
                texts.append(fh.read())
    except Exception as e:
        print(f"Warning: {e}", file=sys.stderr)
text = "\n".join(texts)

words = re.findall(r"[^\W\d_]+(?:['-][^\W\d_]+)*", text)
if not args.case_sensitive:
    words = [w.lower() for w in words]

counts = Counter(words)
if args.by_frequency:
    ordered = sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))
else:
    ordered = sorted(counts.items())

lines = [f"{n}\t{w}" if args.count else w for w, n in ordered]

if args.output:
    with open(args.output, "w", encoding="utf-8") as out:
        out.write("\n".join(lines) + ("\n" if lines else ""))
else:
    print("\n".join(lines))
EOF
)

  python3 -c "$process" "$@"
}

document.markdown2html(){

  # Display help if insufficient args
  if [[ $# -lt 1 ]];then 
    help ${FUNCNAME[0]} "pandoc [some/path/somefile] [options]";
    return 1
  fi

  if ! [[ ($(type /usr/{,local/}{,s}bin/livereload 2> /dev/null)) || ($(which livereload)) ]];then
    echo This function requires livereload
    echo Make sure you are using python 3.6+
    return 1
  else
    while true;
      do ${@}
      sleep 10; 
    done &
    livereload . -p 9000
  fi

}