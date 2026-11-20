# Checks the NetSuite laptop setup. No AI needed. Changes nothing in NetSuite:
# it only reads (one SuiteQL query per account, one SDF object list per account).
# Safe to run any time.

$SkillsDir = Join-Path $HOME '.copilot\skills'
$SecretDir = Join-Path $HOME '.netsuite-query'
$ExpectedSkills = @(
    'nsq', 'netsuite-data-solutioning', 'drawing-t-accounts',
    'netsuite-ai-connector-instructions', 'netsuite-finance-analyst', 'netsuite-owasp-secure-coding',
    'netsuite-sdf-project-documentation', 'netsuite-sdf-roles-and-permissions', 'netsuite-sdf-safe-guide',
    'netsuite-suitescript-learning', 'netsuite-suitescript-records-reference', 'netsuite-suitescript-upgrade',
    'netsuite-uif-spa-reference'
)

$ErrorActionPreference = 'Continue'
$script:pass = 0; $script:fail = 0; $script:warn = 0

function Pass($name, $detail) { $script:pass++; Write-Host ('  PASS  {0,-34} {1}' -f $name, $detail) -ForegroundColor Green }
function Bad($name, $detail)  { $script:fail++; Write-Host ('  FAIL  {0,-34} {1}' -f $name, $detail) -ForegroundColor Red }
function Note($name, $detail) { $script:warn++; Write-Host ('  WARN  {0,-34} {1}' -f $name, $detail) -ForegroundColor Yellow }
function Skip($name, $detail) { Write-Host ('  SKIP  {0,-34} {1}' -f $name, $detail) -ForegroundColor DarkGray }
function Has($cmd)            { [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }
function Section($text)       { Write-Host ''; Write-Host $text -ForegroundColor Cyan }

$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
            [Environment]::GetEnvironmentVariable('Path', 'User') + ';' + (Join-Path $env:APPDATA 'npm')

Write-Host 'NetSuite laptop check' -ForegroundColor Cyan

# ------------------------------------------------------------------ tools
Section 'Tools'

if (Has 'node') {
    $v = (node -v).TrimStart('v'); $major = [int]($v.Split('.')[0])
    if ($major -ge 18) { Pass 'Node.js' "v$v" } else { Bad 'Node.js' "v$v is too old, need 18 or newer" }
} else { Bad 'Node.js' 'not found' }

if (Has 'java') {
    $line = cmd /c "java -version 2>&1" | Select-Object -First 1
    $major = 0
    if ($line -match '"(\d+)(\.(\d+))?') { $major = [int]$Matches[1]; if ($major -eq 1 -and $Matches[3]) { $major = [int]$Matches[3] } }
    if ($major -eq 17 -or $major -eq 21) { Pass 'Java' "$major" } else { Bad 'Java' "$line (SuiteCloud needs 17 or 21)" }
} else { Bad 'Java' 'not found' }

if (Has 'git') { Pass 'Git' ((git --version) -replace 'git version ', '') } else { Bad 'Git' 'not found' }

$openssl = @((Join-Path $env:ProgramFiles 'Git\usr\bin\openssl.exe'),
             (Join-Path $env:LOCALAPPDATA 'Programs\Git\usr\bin\openssl.exe')) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $openssl -and (Has 'openssl')) { $openssl = (Get-Command openssl).Source }
if ($openssl) { Pass 'openssl' 'found' } else { Bad 'openssl' 'not found (comes with Git for Windows)' }

if (Has 'suitecloud') { Pass 'SuiteCloud CLI' 'installed' } else { Bad 'SuiteCloud CLI' 'not found' }

if (Has 'nsq') {
    $help = nsq.cmd --help 2>&1 | Out-String
    if ($help -match '--prod') { Pass 'nsq' 'installed (v0.3 or newer)' } else { Note 'nsq' 'installed but old: run the setup again' }
} else { Bad 'nsq' 'not found' }

# ------------------------------------------------------------------ skills
Section "Skills ($SkillsDir)"

$missing = $ExpectedSkills | Where-Object { -not (Test-Path (Join-Path $SkillsDir "$_\SKILL.md")) }
if (-not $missing) { Pass 'NetSuite skills' "$($ExpectedSkills.Count) of $($ExpectedSkills.Count) present" }
else { Bad 'NetSuite skills' ("missing: " + ($missing -join ', ')) }

# ------------------------------------------------------------------ key
Section "Key ($SecretDir)"

$publicPem  = Join-Path $SecretDir 'public.pem'
$privatePem = Join-Path $SecretDir 'private.pem'
if ((Test-Path $privatePem) -and (Test-Path $publicPem)) {
    Pass 'Key pair' 'present'
    if ($openssl) {
        $end = (& $openssl x509 -in $publicPem -noout -enddate 2>$null) -replace 'notAfter=', ''
        try {
            $endDate = [datetime]::ParseExact(($end -replace '\s+', ' ').Trim(), 'MMM d HH:mm:ss yyyy GMT', [Globalization.CultureInfo]::InvariantCulture)
            $days = [int]($endDate - (Get-Date)).TotalDays
            if ($days -gt 60) { Pass 'Certificate expiry' "$($endDate.ToString('yyyy-MM-dd')) ($days days left)" }
            elseif ($days -gt 0) { Note 'Certificate expiry' "$($endDate.ToString('yyyy-MM-dd')): only $days days left, make a new key soon" }
            else { Bad 'Certificate expiry' "expired $($endDate.ToString('yyyy-MM-dd'))" }
        } catch { Note 'Certificate expiry' "could not read date: $end" }
    }
    $acl = (icacls $SecretDir | Out-String)
    if ($acl -match 'Everyone|BUILTIN\\Users|Authenticated Users') { Bad 'Key folder access' 'other users can read it: run the setup again' }
    else { Pass 'Key folder access' "only $env:USERNAME" }
} else { Bad 'Key pair' 'missing: run the setup again' }

# ------------------------------------------------------------------ accounts
Section 'NetSuite accounts'

$accountsPath = Join-Path $SecretDir 'accounts.json'
$accounts = @()
if (Test-Path $accountsPath) { $accounts = (Get-Content $accountsPath -Raw | ConvertFrom-Json).PSObject.Properties }

if (-not $accounts) {
    Skip 'Connected accounts' 'none yet: run the setup again when you have NetSuite admin access'
} else {
    $passkey = [Environment]::GetEnvironmentVariable('SUITECLOUD_CI_PASSKEY', 'User')
    if ($passkey) { $env:SUITECLOUD_CI_PASSKEY = $passkey; Pass 'SDF key login enabled' 'SUITECLOUD_CI_PASSKEY is set' }
    else { Bad 'SDF key login enabled' 'SUITECLOUD_CI_PASSKEY is not set: run the setup again' }

    $sdfList = if (Has 'suitecloud') { suitecloud.cmd account:manageauth --list 2>&1 | Out-String } else { '' }

    foreach ($a in $accounts) {
        $alias = $a.Name; $acct = $a.Value.accountId
        $isProd = ($a.Value.env -eq 'production') -or ($a.Value.env -ne 'sandbox' -and $acct -notmatch '_(SB\d*|RP)$')
        Write-Host "  -- $alias ($acct)" -ForegroundColor Cyan

        # nsq: login, then a real read
        $out = nsq.cmd test --account $alias 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) { Pass 'nsq login' 'token issued, test query ran' }
        else { Bad 'nsq login' (($out.Trim() -split "`n")[-1]) }

        $tmp = Join-Path $env:TEMP "nsq-check-$alias.json"
        $args_ = @('run', 'SELECT id, name FROM subsidiary', '--account', $alias, '--format', 'json', '--out', $tmp)
        if ($isProd) { $args_ += '--prod' }
        $out = nsq.cmd @args_ 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0 -and (Test-Path $tmp)) {
            $rows = @(Get-Content $tmp -Raw | ConvertFrom-Json)
            if ($rows.Count -gt 0) { Pass 'nsq reads data' "$($rows.Count) subsidiaries visible" }
            else { Bad 'nsq reads data' '0 subsidiaries: the read-only role is missing View on Subsidiaries' }
        } else { Bad 'nsq reads data' (($out.Trim() -split "`n")[-1]) }
        Remove-Item $tmp -ErrorAction SilentlyContinue

        # SDF: saved login, then a real read from a throwaway project
        if ($sdfList -match [regex]::Escape($alias)) { Pass 'SDF login saved' "auth ID $alias" }
        else { Bad 'SDF login saved' "no SDF auth ID named ${alias}: run the setup again"; continue }

        $proj = Join-Path $env:TEMP "sdf-check-$alias"
        if (Test-Path $proj) { Remove-Item $proj -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $proj | Out-Null
        Push-Location $proj
        suitecloud.cmd project:create --type ACCOUNTCUSTOMIZATION --projectname check 2>&1 | Out-Null
        Push-Location (Join-Path $proj 'check')
        suitecloud.cmd account:setup:ci --select $alias 2>&1 | Out-Null
        $out = suitecloud.cmd object:list --type customrecordtype 2>&1 | Out-String
        $code = $LASTEXITCODE
        Pop-Location; Pop-Location
        Remove-Item $proj -Recurse -Force -ErrorAction SilentlyContinue
        if ($code -eq 0 -and $out -notmatch 'error|denied|invalid') { Pass 'SDF talks to NetSuite' 'listed custom record types' }
        else { Bad 'SDF talks to NetSuite' (($out.Trim() -split "`n")[-1]) }
    }
}

# ------------------------------------------------------------------ result
Write-Host ''
$summary = "$($script:pass) passed, $($script:fail) failed, $($script:warn) warnings"
if ($script:fail -eq 0) { Write-Host "ALL GOOD: $summary" -ForegroundColor Green }
else { Write-Host "NEEDS ATTENTION: $summary. Fix the FAIL lines, usually by running the setup again." -ForegroundColor Red }
