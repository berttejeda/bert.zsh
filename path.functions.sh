# PATH

# GOROOT is the location where the Go package is installed on your system
# GOPATH is the location of your work directory. 
# e.g. ~/HOME/go/projects

export GOPATH="${HOME}/go"

py_BINARY=python3
if ! [[ ($(type /usr/{,local/}{,s}bin/${py_BINARY} 2> /dev/null)) || ($(which $py_BINARY)) ]];then
	py_BINARY=python
fi

if [[ -n $os_is_windows ]];then
	py_user_site=$(${py_BINARY} -m site --user-base)
	py_user_site_posix=$(cygpath -u "${py_user_site}" | tr -d '\r')
	py_BINPATH=$(echo -n "${py_user_site_posix}/bin")
	py_ScriptsPath="${py_user_site_posix}/Scripts"
	py_AppDataPaths=$(ls ${APPDATA}/python | while read p;do cygpath -u "${APPDATA}/python/${p}/bin" | tr -d '\r';cygpath -u "${APPDATA}/python/${p}/Scripts" | tr -d '\r';done | tr '\n' ':')
else
	py_BINPATH="$(${py_BINARY} -m site --user-base)/bin"
	py_ScriptsPath="$(${py_BINARY} -m site --user-base)/Scripts"
fi

PATHS="""
/go/bin
$GOPATH/bin
/usr/local/go/bin
$HOME/.goenv/shims
$HOME/.goenv/bin
${py_BINPATH}
${py_ScriptsPath}
${py_AppDataPaths}
${LOCALAPPDATA}/Programs/Git/mingw64/bin
${GOPATH}
/c/Program Files/Go/bin
/c/git-sdk-64
/c/Progra~1/OpenSSL/bin
/c/oracle/instantclient_12_2
/c/ProgramData/Bind9/bin
/c/Users/$USER/Appdata/Local/Programs/nvm
$HOME/AppData/Local/Programs/nvm
$HOME/AppData/Local/Programs/nvm/v16.5.0
/c/tools/ruby24/bin
${HOME}/.conda/envs/py3
${HOME}/.conda/envs/py3/Scripts
${HOME}/Miniconda3/Scripts
/c/ProgramData/Miniconda3
/c/ProgramData/Miniconda3/Scripts
/c/tools/miniconda3/Scripts
/c/Progra~1/SUBLIM~1
$HOME/google-cloud-sdk/bin
/c/Programdata/chocolatey/bin
/usr/local/sbin
/usr/local/opt/sqlite/bin
/c/ProgramData/Anaconda3/envs/py3
/c/ProgramData/Anaconda3/Scripts
${PATH}
/c/Progra~1/nodejs
/c/Progra~1/Oracle/VirtualBox
/c/aspell/bin
/c/Progra~2/Aspell/bin
/mingw64/bin/gcc
/c/HashiCorp/Vagrant/embedded/mingw64/bin
/c/HashiCorp/Vagrant/embedded/usr/bin
/c/HashiCorp/Vagrant/bin
${HOME}/AppData/Roaming/npm
/c/Progra~2/MIB055~1/2017/BuildTools/MSBuild/15.0/Bin
/c/Progra~2/MIB055~1/2017/BuildTools/MSBuild/15.0/Bin/Roslyn
${HOME}/.cargo/bin
${HOME}/ProgramData/nvm
${HOME}/.local/bin
${HOME}/.githooks
/c/Progra~1/Amazon/AWSCLIV2
/c/Progra~1/Amazon/AWSCLI
/c/Progra~1/Amazon/AWSSAMCLI/bin
/c/Progra~1/Amazon/SessionManagerPlugin/bin
${HOME}/bin
$HOME/.jenv/bin
/c/Program Files/Graphviz/bin
"""
exclusions="/c/Program Files/Git/bin/git"
NEW_PATH=$(echo "${PATHS}" | tr ':' '\n' | egrep --text -v "${exclusions}" | sort -u | egrep --text '^/' | tr '\n' ':')
export PATH=/usr/local/bin:${NEW_PATH}