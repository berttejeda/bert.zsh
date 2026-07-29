# web
web.listen(){ 
  usage="""Usage: 
  ${FUNCNAME[0]} <PORTNUMBER>"""
  if [[ ($# -lt 1) || ("$*" =~ "-h|--help") ]];then echo -e "${usage}";return 0;fi 
  if ! python -m SimpleHTTPServer ${1} 2>/dev/null;then 
    python -m http.server ${1}
  fi
}

web.listen.upload(){ 
  usage="""Usage: 
  ${FUNCNAME[0]} [PORT] [UPLOAD-DIRECTORY]"""
  if [[ ($# -lt 1) || ("$*" =~ "-h|--help") ]];then echo -e "${usage}";return 0;fi 
  PORT="${1:-8000}"
  UPLOAD_DIR="${2:-$(pwd)}"
  process="import os, sys, cgi, http.server, socketserver

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
UPLOAD_DIR = sys.argv[2] if len(sys.argv) > 2 else os.getcwd()

class UploadHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'text/html')
        self.end_headers()
        self.wfile.write(b'''<!DOCTYPE html>
<html><body>
<h2>Upload File</h2>
<form method='POST' enctype='multipart/form-data'>
<input type='file' name='file' required>
<input type='submit' value='Upload'>
</form>
</body></html>''')

    def do_POST(self):
        content_type = self.headers.get('Content-Type')
        if content_type and content_type.startswith('multipart/form-data'):
            form = cgi.FieldStorage(
                fp=self.rfile,
                headers=self.headers,
                environ={'REQUEST_METHOD': 'POST', 'CONTENT_TYPE': content_type}
            )
            if 'file' in form and form['file'].filename:
                filename = os.path.basename(form['file'].filename)
                filepath = os.path.join(UPLOAD_DIR, filename)
                with open(filepath, 'wb') as out:
                    out.write(form['file'].file.read())
                self.send_response(200)
                self.end_headers()
                self.wfile.write(('Uploaded: %s\n' % filename).encode())
                return
        else:
            length = int(self.headers.get('Content-Length', 0))
            filename = os.path.basename(self.path) or 'uploaded'
            filepath = os.path.join(UPLOAD_DIR, filename)
            with open(filepath, 'wb') as out:
                out.write(self.rfile.read(length))
            self.send_response(200)
            self.end_headers()
            self.wfile.write(('Uploaded: %s\n' % filename).encode())
            return

        self.send_response(400)
        self.end_headers()
        self.wfile.write(b'No file uploaded\n')

with socketserver.TCPServer(('', PORT), UploadHandler) as httpd:
    print('Serving upload server on port %s (dir: %s)' % (PORT, UPLOAD_DIR))
    httpd.serve_forever()
"
  python -c "${process}" "${PORT}" "${UPLOAD_DIR}"
}

alias jcurl='curl -s -f -i -L -o "/dev/stderr" -w "$(date -u +"%F %T,%3NZ") - GET \"%{url_effective}\" %{http_code} %{size_download} %{time_total}\n"'

web.stat.endpoint(){
  if wget -q -nv --spider "${1}"; then 
    echo "SUCCESS: Remote resource exists!"
  else
    echo "ERROR: Remote resource does not exist!"
  fi
}

web.open-url() {
  if [ $os_is_windows ];then
    '/c/Program Files (x86)/Google/Chrome/Application/chrome' "${*}"
  elif [ $os_is_osx ];then 
    /usr/bin/open -a "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" "${*}"
  fi  
}

domain.get-commonname() {
  usage="""Usage: 
  ${FUNCNAME[0]} --url [URL] --port [PORTNUMBER]"""  
  if [[ ($# -lt 1) || ("$*" =~ ".*--help.*") ]];then echo -e "${usage}";return 0;fi 
  PREFIX=""
  PORT="443"
  while (( $# )); do
      if [[ "$1" =~ ".*--url.*" ]]; then URL=$2;fi    
      if [[ "$1" =~ ".*--port.*" ]]; then PORT=$2;fi    
      if [[ "$1" =~ ".*--dry.*" ]]; then PREFIX="echo";fi
      shift
  done
  if [[ "${PORT}" == "443" ]];then 
    echo "No port specified, using default: 443"
  fi
	echo | openssl s_client -servername ${URL} -connect $URL:$PORT 2>/dev/null | openssl x509 -noout -subject
}

domain.get-cert() {
  usage="""Usage: 
  ${FUNCNAME[0]} --url [URL] --port [PORTNUMBER]"""  
  if [[ ($# -lt 1) || ("$*" =~ ".*--help.*") ]];then echo -e "${usage}";return 0;fi 
  PREFIX=""
  PORT="443"
  while (( $# )); do
      if [[ "$1" =~ ".*--url.*" ]]; then URL=$2;fi    
      if [[ "$1" =~ ".*--port.*" ]]; then PORT=$2;fi    
      if [[ "$1" =~ ".*--dry.*" ]]; then PREFIX="echo";fi
      shift
  done
  if [[ "${PORT}" == "443" ]];then 
    echo "No port specified, using default: 443"
  fi
  # echo -n | openssl s_client -connect $ip:$port | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' 2>/dev/null
  openssl s_client -showcerts -connect $URL:$PORT </dev/null 2>/dev/null|openssl x509 -outform PEM
}