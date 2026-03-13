FROM mcr.microsoft.com/dotnet/framework/runtime:4.8-windowsservercore-ltsc2019

SHELL ["powershell", "-Command"]

# Installer act-cli manuellement
RUN Invoke-WebRequest -Uri 'https://github.com/nektos/act/releases/latest/download/act_Windows_x86_64.zip' \
    -OutFile 'act.zip'; \
    Expand-Archive 'act.zip' -DestinationPath 'C:\act'; \
    Remove-Item 'act.zip'; \
    $path = [Environment]::GetEnvironmentVariable('PATH', 'Machine'); \
    [Environment]::SetEnvironmentVariable('PATH', $path + ';C:\act', 'Machine')

# Installer Git manuellement
RUN Invoke-WebRequest -Uri 'https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.1/MinGit-2.47.1-64-bit.zip' \
    -OutFile 'git.zip'; \
    Expand-Archive 'git.zip' -DestinationPath 'C:\git'; \
    Remove-Item 'git.zip'; \
    $path = [Environment]::GetEnvironmentVariable('PATH', 'Machine'); \
    [Environment]::SetEnvironmentVariable('PATH', $path + ';C:\git\cmd', 'Machine')

# Installer GitHub CLI
RUN Invoke-WebRequest -Uri 'https://github.com/cli/cli/releases/download/v2.63.2/gh_2.63.2_windows_amd64.zip' \
    -OutFile 'gh.zip'; \
    Expand-Archive 'gh.zip' -DestinationPath 'C:/gh'; \
    Remove-Item 'gh.zip'; \
    $path = [Environment]::GetEnvironmentVariable('PATH', 'Machine'); \
    [Environment]::SetEnvironmentVariable('PATH', $path + ';C:\gh\gh_2.63.2_windows_amd64\bin', 'Machine')

# Installer Node.js v20.20.0 (LTS)
RUN Invoke-WebRequest -Uri 'https://nodejs.org/dist/v20.20.0/node-v20.20.0-win-x64.zip' \
    -OutFile 'node.zip'; \
    Expand-Archive 'node.zip' -DestinationPath 'C:/'; \
    Rename-Item 'C:/node-v20.20.0-win-x64' 'C:/nodejs'; \
    Remove-Item 'node.zip'; \
    $path = [Environment]::GetEnvironmentVariable('PATH', 'Machine'); \
    [Environment]::SetEnvironmentVariable('PATH', $path + ';C:/nodejs', 'Machine')

# Installer PowerShell Core (pwsh)
RUN Invoke-WebRequest -Uri 'https://github.com/PowerShell/PowerShell/releases/download/v7.4.1/PowerShell-7.4.1-win-x64.zip' \
    -OutFile 'pwsh.zip'; \
    Expand-Archive 'pwsh.zip' -DestinationPath 'C:/pwsh'; \
    Remove-Item 'pwsh.zip'; \
    $path = [Environment]::GetEnvironmentVariable('PATH', 'Machine'); \
    [Environment]::SetEnvironmentVariable('PATH', $path + ';C:/pwsh', 'Machine')

CMD ["powershell"]