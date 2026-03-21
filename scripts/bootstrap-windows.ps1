# =============================================================================
# AI Platform — Bootstrap for Windows (WSL2)
# Run from PowerShell (Administrator) on the Windows host.
#
# Parameters:
#   -WslRepoPath  Path inside WSL to the cloned repo (default: /home/<user>/ai-platform)
#
# Environment:
#   AI_PLATFORM_DEBUG=1  — passed to WSL bash for verbose bootstrap-linux logging
# =============================================================================

param(
    [string]$WslRepoPath = ""
)

$ErrorActionPreference = "Stop"

function Write-Ok   { param($msg) Write-Host "[OK]    $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "[WARN]  $msg" -ForegroundColor Yellow }
function Write-Fail { param($msg) Write-Host "[FAIL]  $msg" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "============================================="
Write-Host "  AI Platform — Bootstrap (Windows / WSL2)"
Write-Host "============================================="

# --- Step 1: Verify WSL2 ---
Write-Host ""
Write-Host "=== Step 1: Verify WSL2 ==="

$null = wsl --status 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Fail "WSL2 is not installed. Run: wsl --install"
}
Write-Ok "WSL2 is available"

$defaultDistro = (wsl -l -q 2>&1 | Select-Object -First 1).Trim()
if (-not $defaultDistro) {
    Write-Fail "No WSL2 distribution found. Run: wsl --install Ubuntu-24.04"
}
Write-Ok "Default distro: $defaultDistro"

# --- Step 2: Resolve repo path inside WSL ---
$wslUser = (wsl -- whoami).Trim()
if ([string]::IsNullOrWhiteSpace($WslRepoPath)) {
    $AI_PLATFORM_WSL_PATH = "/home/$wslUser/ai-platform"
} else {
    $AI_PLATFORM_WSL_PATH = $WslRepoPath.Trim()
}
Write-Host ""
Write-Host "Using WSL repo path: $AI_PLATFORM_WSL_PATH"
Write-Host "(Override with: -WslRepoPath '/home/you/path/to/ai-platform')"

# --- Step 3: Verify Docker inside WSL ---
Write-Host ""
Write-Host "=== Step 2: Verify Docker in WSL ==="

$dockerCheck = wsl -- bash -c "docker info > /dev/null 2>&1 && echo OK || echo FAIL"
if ($dockerCheck.Trim() -ne "OK") {
    Write-Fail "Docker is not running inside WSL. Start it: wsl -- sudo service docker start"
}
Write-Ok "Docker is running inside WSL"

# --- Step 4: Create data directories + render Prometheus file_sd ---
Write-Host ""
Write-Host "=== Step 3: Data dirs, permissions, Prometheus file_sd ==="

$debugExport = if ($env:AI_PLATFORM_DEBUG -eq "1") { "export AI_PLATFORM_DEBUG=1; " } else { "" }

wsl -- bash -c @"
set -e
$debugExport
cd '$AI_PLATFORM_WSL_PATH' || { echo 'Repo not found at $AI_PLATFORM_WSL_PATH'; exit 1; }
for d in postgres kafka redis prometheus grafana pgadmin redisinsight; do
  mkdir -p data/`$d
done
sudo chown -R 472:472 data/grafana || true
sudo chmod -R 777     data/prometheus || true
sudo chown -R 5050:5050 data/pgadmin || true
./scripts/render-prometheus-config.sh
echo 'Data directories and Prometheus file_sd ready'
"@

if ($LASTEXITCODE -ne 0) {
    Write-Fail "WSL setup failed — run in WSL: cd $AI_PLATFORM_WSL_PATH && ./scripts/bootstrap-linux.sh"
}
Write-Ok "WSL data dirs + render-prometheus-config.sh completed"

# --- Step 5: Environment file ---
Write-Host ""
Write-Host "=== Step 4: Environment File ==="

$envExists = wsl -- bash -c "test -f $AI_PLATFORM_WSL_PATH/.env && echo YES || echo NO"
if ($envExists.Trim() -eq "NO") {
    wsl -- bash -c "cp $AI_PLATFORM_WSL_PATH/.env.example $AI_PLATFORM_WSL_PATH/.env"
    Write-Warn ".env created from .env.example — edit passwords, KAFKA_ADVERTISED_EXTERNAL_HOST, DEV_MACHINE_IP"
} else {
    Write-Ok ".env already exists"
}

# --- Step 6: Port proxy rules for Tailscale access ---
Write-Host ""
Write-Host "=== Step 5: Configure Port Proxy (Tailscale / LAN) ==="
Write-Host "    Forwards Windows host ports to 127.0.0.1 (WSL publishes on host loopback)."
Write-Host "    Requires Administrator privileges."

$ports = @(
    @{ Name = "PostgreSQL";   Port = 5432 },
    @{ Name = "Kafka";        Port = 9094 },
    @{ Name = "Redis";        Port = 6379 },
    @{ Name = "Grafana";      Port = 3000 },
    @{ Name = "Prometheus";   Port = 9090 },
    @{ Name = "Kafka UI";     Port = 8080 },
    @{ Name = "pgAdmin4";     Port = 5050 },
    @{ Name = "RedisInsight"; Port = 5540 }
)

foreach ($p in $ports) {
    try {
        netsh interface portproxy add v4tov4 listenport=$($p.Port) listenaddress=0.0.0.0 connectport=$($p.Port) connectaddress=127.0.0.1 2>&1 | Out-Null
        Write-Ok "$($p.Name) :$($p.Port)"
    } catch {
        Write-Warn "Could not set port proxy for $($p.Name) :$($p.Port) — see docs/DEBUGGING.md"
    }
}

$allPorts = ($ports | ForEach-Object { $_.Port }) -join ","
try {
    netsh advfirewall firewall delete rule name="AI Platform" 2>&1 | Out-Null
    netsh advfirewall firewall add rule name="AI Platform" dir=in action=allow protocol=TCP localport=$allPorts 2>&1 | Out-Null
    Write-Ok "Firewall rule 'AI Platform' for ports: $allPorts"
} catch {
    Write-Warn "Could not create firewall rule — see docs/DEBUGGING.md (WSL2 / Tailscale)"
}

# --- Step 7: Start the stack ---
Write-Host ""
Write-Host "=== Step 6: Start Platform (docker compose up -d) ==="

wsl -- bash -c "cd $AI_PLATFORM_WSL_PATH && mkdir -p logs && docker compose up -d 2>&1 | tee -a logs/windows-bootstrap.log || { echo 'docker compose failed — see logs/windows-bootstrap.log'; exit 1; }"

if ($LASTEXITCODE -ne 0) {
    Write-Fail "docker compose up failed in WSL — see $AI_PLATFORM_WSL_PATH/logs/windows-bootstrap.log and docs/DEBUGGING.md"
}

Write-Host ""
Write-Host "============================================="
Write-Host "  AI Platform is starting!"
Write-Host "============================================="
Write-Host ""
Write-Host "  In WSL: cd $AI_PLATFORM_WSL_PATH && ./scripts/status.sh"
Write-Host "  Logs:   $AI_PLATFORM_WSL_PATH/logs/"
Write-Host "  Debug:  docs/DEBUGGING.md"
Write-Host ""
