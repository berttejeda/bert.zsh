# Overview

This repo contains various zsh source files that contain

functions I have created or knabbed from the internets.

The file name indicates the context of usage, 

e.g. file.functions.sh contains zsh functions specific to file system operations. 

For your convenience, I have included an installation script that takes care of sourcing all library files in this repository.

You can invoke the installation script via curl as follows:

`source <(curl -Lks https://raw.githubusercontent.com/berttejeda/bert.zsh/master/.installer.sh)`

# Installing ZSH

## On Windows

1. Launch a Powershell terminal
1. Install [Chocolatey](https://chocolatey.org/) to your local user profile:<br />
`
Set-Variable -Name "ChocolateyInstallPath" -Value "$(Join-Path -Path $Env:LocalAppData -ChildPath chocolatey)";
New-Item $ChocolateyInstallPath -Type Directory -Force;
[Environment]::SetEnvironmentVariable("ChocolateyInstall", $ChocolateyInstallPath);
Set-ExecutionPolicy Bypass -Scope Process;
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
`
1. Install miniconda3: `choco install -y miniconda3`
1. Install gcc (via mingw): `choco install -y mingw`
1. Install msys2: `choco install -y msys2`
1. Install make:  `choco install -y make`
1. Install docker and docker-compose:<br />
  `choco install -y docker docker-compose`
1. Download the zsh package (v5.9.2):<br />
  `curl -ksO https://repo.msys2.org/msys/x86_64/zsh-5.9-2-x86_64.pkg.tar.zst`
1. Untar + decompress the zsh package:<br /> 
  `mkdir zsh && tar --use-compress-program=zstd -xvf zsh-5.9-2-x86_64.pkg.tar.zst -C zsh`<br />
  Note: The above command assumes the `zstd.exe` binary is available via your PATH<br />
  If you encounter an error similar to `tar.h: Cannotopen: No such file or directory`,<br />
  you may have to adjust your PATH variable to include the location of the `ztsd.exe` binary,<br />
  e.g. `export PATH="$PATH:/c/msys64/usr/bin"` if running from git-bash/msys or<br />
  `$env:PATH="$($env:PATH);C:\msys64\usr\bin"` if running from Powershell<br />
  (adjust the above to the location of the `ztsd.exe` binary on your machine)
1. Merge the zsh content to Git BASH directory:<br />
  `cp -R zsh/etc /;
  cp -R zsh/usr /`
1. Initialize the zsh init file:<br />
  `touch ~/.zshrc`
1. Clean up and test zsh
  `rm -rf zsh zsh.tar.zst zstd;
  zsh --version`
1. Install [Oh My Zsh](https://ohmyz.sh/)<br />
  `sh -c "$(curl -fsSL https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"`
  1. Install the zsh honukai theme<br />
  `
  curl -fsSL https://raw.githubusercontent.com/oskarkrawczyk/honukai-iterm/master/honukai.zsh-theme -o ~/.oh-my-zsh/custom/themes/honukai.zsh-theme;
  sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="honukai"/g' ~/.zshrc
  `
1. Install bert.zsh<br />
  `source <(curl -Lks https://raw.githubusercontent.com/berttejeda/bert.zsh/master/.installer.sh)`
1. Make zsh launch at bash startup
   `echo 'test -t && exec zsh >> ~/.bashrc`
1. Restart your terminal
1. Prep miniconda3:<br />
  `
  conda init zsh;
  conda.exe 'shell.zsh' 'hook';
  `

## On other platforms

see: [Installing ZSH · ohmyzsh/ohmyzsh Wiki](https://github.com/ohmyzsh/ohmyzsh/wiki/Installing-ZSH)