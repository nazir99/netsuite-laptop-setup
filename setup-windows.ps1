# NetSuite dev setup for a Windows laptop.
# Installs: Node, Java 17, Git, SuiteCloud CLI, nsq, NetSuite skills for Copilot,
# one key for this laptop, and connects nsq + SDF to the client account with it.
# Safe to re-run: finished steps are skipped, skills are updated.

$YourName  = 'Gabriel Rollano'
$SkillsDir = Join-Path $HOME '.copilot\skills'
$SecretDir = Join-Path $HOME '.netsuite-query'

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Step($n, $text) { Write-Host ''; Write-Host "[$n/6] $text" -ForegroundColor Cyan }
function Ok($text)       { Write-Host "    OK  $text" -ForegroundColor Green }
function Info($text)     { Write-Host "    $text" }
function Warn($text)     { Write-Host "    !!  $text" -ForegroundColor Yellow }
function Fail($text)     { throw "STOPPED: $text  Fix that, then run the setup again. Finished steps are skipped." }
function Has($cmd)       { [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }

function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
    $npmGlobal = Join-Path $env:APPDATA 'npm'
    if ($env:Path -notlike "*$npmGlobal*") { $env:Path += ";$npmGlobal" }
}

function Winget-Install($id, $label) {
    if (-not (Has 'winget')) { Fail "winget is missing, so $label cannot be installed. Ask IT to install $label." }
    Info "Installing $label (Windows may ask for permission)..."
    winget install --id $id -e --silent --accept-source-agreements --accept-package-agreements | Out-Host
    Refresh-Path
}

function Get-JavaMajor {
    if (-not (Has 'java')) { return 0 }
    $line = cmd /c "java -version 2>&1" | Select-Object -First 1
    if ($line -match '"(\d+)(\.(\d+))?') {
        $major = [int]$Matches[1]
        if ($major -eq 1 -and $Matches[3]) { $major = [int]$Matches[3] }
        return $major
    }
    return 0
}

function Find-OpenSsl {
    foreach ($c in @((Join-Path $env:ProgramFiles 'Git\usr\bin\openssl.exe'),
                     (Join-Path $env:LOCALAPPDATA 'Programs\Git\usr\bin\openssl.exe'))) {
        if (Test-Path $c) { return $c }
    }
    $cmd = Get-Command openssl -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

# Clone a public repo, or update it if it is already there.
function Sync-Repo($url, $dir) {
    if (Test-Path (Join-Path $dir '.git')) {
        git -C $dir pull -q --ff-only
    } else {
        if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
        git clone -q --depth 1 $url $dir
    }
    if ($LASTEXITCODE -ne 0) { Fail "could not download $url (a company proxy or firewall is the usual cause)." }
}

Write-Host 'NetSuite dev setup' -ForegroundColor Cyan
Refresh-Path

# ------------------------------------------------------------------ 1
Step 1 'Node.js, Java 17 and Git'

if (-not (Has 'node')) {
    Winget-Install 'OpenJS.NodeJS.LTS' 'Node.js LTS'
    if (-not (Has 'node')) { Fail 'Node.js did not install. Open a new PowerShell window and run the setup again.' }
}
Ok "Node $(node -v)"

$javaMajor = Get-JavaMajor
if ($javaMajor -ne 17 -and $javaMajor -ne 21) {
    if ($javaMajor -gt 0) { Warn "Java $javaMajor found, but SuiteCloud needs 17 or 21. Installing 17." }
    Winget-Install 'Microsoft.OpenJDK.17' 'Java 17'
    $jdk = Get-ChildItem (Join-Path $env:ProgramFiles 'Microsoft') -Directory -Filter 'jdk-17*' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($jdk) { $env:JAVA_HOME = $jdk.FullName; $env:Path = "$($jdk.FullName)\bin;$env:Path" }
    $javaMajor = Get-JavaMajor
    if ($javaMajor -ne 17 -and $javaMajor -ne 21) { Fail 'Java 17 is not on the PATH yet. Open a new PowerShell window and run the setup again.' }
}
Ok "Java $javaMajor"

if (-not (Has 'git') -or -not (Find-OpenSsl)) {
    Winget-Install 'Git.Git' 'Git for Windows'
    if (-not (Has 'git') -or -not (Find-OpenSsl)) { Fail 'Git did not install. Open a new PowerShell window and run the setup again.' }
}
Ok 'Git'

# ------------------------------------------------------------------ 2
Step 2 'SuiteCloud CLI'

if (-not (Has 'suitecloud')) {
    $env:SUITECLOUD_CLI_ACCEPT_LICENSE = 'true'
    Info 'Installing (accepts the Oracle Free Use license)...'
    npm.cmd install -g @oracle/suitecloud-cli | Out-Host
    if ($LASTEXITCODE -ne 0) { Fail 'npm could not install the SuiteCloud CLI. A company proxy is the usual cause: ask IT.' }
    Refresh-Path
    if (-not (Has 'suitecloud')) { Fail 'suitecloud is not on the PATH yet. Open a new PowerShell window and run the setup again.' }
}
Ok 'suitecloud'

# ------------------------------------------------------------------ 3
Step 3 'nsq and the NetSuite skills (for Copilot)'

New-Item -ItemType Directory -Force -Path $SkillsDir | Out-Null

Sync-Repo 'https://github.com/nazir99/nsq.git'                       (Join-Path $SkillsDir 'nsq')
Sync-Repo 'https://github.com/nazir99/netsuite-data-solutioning.git' (Join-Path $SkillsDir 'netsuite-data-solutioning')
Sync-Repo 'https://github.com/nazir99/drawing-t-accounts.git'        (Join-Path $SkillsDir 'drawing-t-accounts')
Ok 'nsq, netsuite-data-solutioning, drawing-t-accounts'

# Oracle's SuiteCloud skills live in one folder of a large repo: fetch only that folder.
$oracle = Join-Path $env:TEMP 'suitecloud-sdk-skills'
if (Test-Path $oracle) { Remove-Item $oracle -Recurse -Force }
git clone -q --depth 1 --filter=blob:none --sparse https://github.com/oracle/netsuite-suitecloud-sdk.git $oracle
if ($LASTEXITCODE -ne 0) { Fail 'could not download the Oracle SuiteCloud skills.' }
git -C $oracle sparse-checkout set packages/agent-skills
$oracleSkills = Get-ChildItem (Join-Path $oracle 'packages\agent-skills') -Directory -Filter 'netsuite-*'
foreach ($s in $oracleSkills) {
    $dest = Join-Path $SkillsDir $s.Name
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    Copy-Item $s.FullName $dest -Recurse
}
Remove-Item $oracle -Recurse -Force -ErrorAction SilentlyContinue
Ok "$($oracleSkills.Count) Oracle SuiteCloud skills"

npm.cmd install -g (Join-Path $SkillsDir 'nsq') | Out-Null
if ($LASTEXITCODE -ne 0) { Fail 'npm could not install the nsq command.' }
Refresh-Path
if (-not (Has 'nsq')) { Fail 'nsq is not on the PATH yet. Open a new PowerShell window and run the setup again.' }
Ok "nsq command (skills are in $SkillsDir)"

# ------------------------------------------------------------------ 4
Step 4 'Key for this laptop (one key for nsq and SDF)'

New-Item -ItemType Directory -Force -Path $SecretDir | Out-Null
$privatePem = Join-Path $SecretDir 'private.pem'
$publicPem  = Join-Path $SecretDir 'public.pem'

if (-not ((Test-Path $privatePem) -and (Test-Path $publicPem))) {
    $openssl = Find-OpenSsl
    $cn = 'nsq-' + ($YourName.ToLower() -replace '[^a-z0-9]', '-')
    & $openssl req -x509 -newkey rsa:4096 -sha256 -nodes -days 730 -keyout $privatePem -out $publicPem -subj "/CN=$cn" 2>&1 | Out-Null
    if (-not (Test-Path $publicPem)) { Fail 'openssl did not create the key.' }
    Ok 'new key and certificate created (valid 2 years)'
} else {
    Ok 'key already exists, keeping it'
}
icacls $SecretDir /inheritance:r /grant:r "$($env:USERNAME):(OI)(CI)F" | Out-Null
Ok "key folder locked to $env:USERNAME"

# ------------------------------------------------------------------ 5
Step 5 'Connect to the client NetSuite account'

$answer = Read-Host '    Connect a NetSuite account now? You need NetSuite admin access. (Y/n)'
if ($answer -match '^[nN]') {
    Info 'Skipped. Run the setup again when you have admin access.'
    Write-Host ''; Write-Host 'Done (account not connected yet). Running the checks...' -ForegroundColor Green
    try { & ([scriptblock]::Create((Invoke-RestMethod 'https://raw.githubusercontent.com/nazir99/netsuite-laptop-setup/main/check-windows.ps1'))) } catch { }
    return
}

do {
    $alias = (Read-Host '    Short name for this account (letters, numbers, dashes), e.g. acme-sb').Trim()
} until ($alias -match '^[A-Za-z0-9_-]+$')
$accountId = (Read-Host '    NetSuite Account ID (Setup > Company > Company Information), e.g. 1234567_SB1').Trim()
$env_ = if ($accountId -match '_SB\d*$') { 'sandbox' } else { 'production' }
Info "This is a $env_ account."

$roleName = "Read-only queries ($YourName)"
$appName  = "$YourName read-only queries"
$nsUrl    = 'https://' + ($accountId.ToLower() -replace '_', '-') + '.app.netsuite.com'

Write-Host ''
Write-Host "    In NetSuite ($nsUrl), as an Administrator:" -ForegroundColor Yellow
Write-Host ''
Write-Host '    A. Setup > Company > Enable Features > SuiteCloud'
Write-Host '       Check: REST Web Services, OAuth 2.0, SuiteCloud Development Framework. Save.'
Write-Host ''
Write-Host "    B. Setup > Users/Roles > Manage Roles > New. Name: $roleName"
Write-Host '       Setup tab: REST Web Services (Full), Log in using OAuth 2.0 Access Tokens (Full)'
Write-Host '       Lists, Transactions, Reports: View only. All subsidiaries. Nothing above View.'
Write-Host '       Save, then add this role to your employee record.'
Write-Host ''
Write-Host "    C. Setup > Integration > Manage Integrations > New. Name: $appName"
Write-Host '       Uncheck Token-Based Authentication. Check Client Credentials (Machine to Machine).'
Write-Host '       Scope: REST Web Services only. Save and copy the CLIENT ID.'
Write-Host ''
Write-Host '    D. Setup > Integration > OAuth 2.0 Client Credentials (M2M) Setup > Create New, twice,'
Write-Host '       both times you as Entity and the same certificate file (Explorer is opening on it):'
Write-Host "         1) Role: $roleName      Application: $appName"
Write-Host '            -> copy its CERTIFICATE ID (for queries)'
Write-Host '         2) Role: Administrator (or your developer role)   Application: SuiteCloud Development Integration'
Write-Host '            -> copy its CERTIFICATE ID (for deploying)'
Write-Host ''
Write-Host '    If IT asks: one certificate from this laptop, two permission levels. One can deploy'
Write-Host '    scripts I build, the other can only read data, so reporting can never change anything.'
Write-Host ''
Start-Process explorer.exe "/select,`"$publicPem`""

$clientId  = (Read-Host '    C. CLIENT ID').Trim()
$queryCert = (Read-Host '    D1. CERTIFICATE ID for queries').Trim()
$sdfCert   = (Read-Host '    D2. CERTIFICATE ID for deploying').Trim()

nsq.cmd accounts add --account $alias --accountId $accountId --clientId $clientId --certId $queryCert --env $env_ | Out-Host
if ($LASTEXITCODE -ne 0) { Fail 'nsq could not save the account.' }
nsq.cmd test --account $alias | Out-Host
if ($LASTEXITCODE -eq 0) { Ok "nsq connected to $accountId as '$alias'" }
else { Warn "nsq test failed. Check the client ID, the D1 certificate ID and the role, then run: nsq test --account $alias" }

# ------------------------------------------------------------------ 6
Step 6 'Connect SuiteCloud (SDF) with the same key: no more browser logins'

# SuiteCloud only allows key login when this variable is set. It encrypts the saved login.
$passkey = [Environment]::GetEnvironmentVariable('SUITECLOUD_CI_PASSKEY', 'User')
if (-not $passkey) {
    $passkey = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 40 | ForEach-Object { [char]$_ })
    [Environment]::SetEnvironmentVariable('SUITECLOUD_CI_PASSKEY', $passkey, 'User')
}
$env:SUITECLOUD_CI_PASSKEY = $passkey

suitecloud.cmd account:setup:ci --account $accountId --authid $alias --certificateid $sdfCert --privatekeypath $privatePem | Out-Host
if ($LASTEXITCODE -eq 0) { Ok "SDF connected to $accountId as '$alias'" }
else { Warn 'SDF key login failed. Check the D2 certificate ID (SuiteCloud Development Integration row), then run the setup again.' }

Write-Host ''
Write-Host 'Done. Running the checks...' -ForegroundColor Green
try { & ([scriptblock]::Create((Invoke-RestMethod 'https://raw.githubusercontent.com/nazir99/netsuite-laptop-setup/main/check-windows.ps1'))) }
catch { Warn 'Could not download the check script. Run it later (see below).' }
Write-Host ''
Write-Host '  Open a NEW PowerShell window, then:'
Write-Host "    nsq run `"SELECT id, name FROM subsidiary`" --account $alias --format md"
Write-Host "    In an SDF project folder, once:  suitecloud account:setup:ci --select $alias"
Write-Host '  Update skills and nsq later: run this setup again.'
Write-Host '  Check everything any time:  irm https://raw.githubusercontent.com/nazir99/netsuite-laptop-setup/main/check-windows.ps1 | iex'
Write-Host "  Never copy or share $SecretDir"
