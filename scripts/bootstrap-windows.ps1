# =============================================================================
# AI Platform — Bootstrap for Windows (WSL2)
# Run this from PowerShell (Admin) on the Windows host.
# It sets up WSL2, verifies Docker, creates data dirs inside WSL, configures
# netsh port proxy rules for Tailscale access, and starts the stack.
# =============================================================================

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

$wslStatus = wsl --status 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Fail "WSL2 is not installed. Run: wsl --install"
}
Write-Ok "WSL2 is available"

$defaultDistro = (wsl -l -q 2>&1 | Select-Object -First 1).Trim()
if (-not $defaultDistro) {
    Write-Fail "No WSL2 distribution found. Run: wsl --install Ubuntu-24.04"
}
Write-Ok "Default distro: $defaultDistro"

# --- Step 2: Verify Docker inside WSL ---
Write-Host ""
Write-Host "=== Step 2: Verify Docker in WSL ==="

$dockerCheck = wsl -- bash -c "docker info > /dev/null 2>&1 && echo OK || echo FAIL"
if ($dockerCheck.Trim() -ne "OK") {
    Write-Fail "Docker is not running inside WSL. Start it: wsl -- sudo service docker start"
}
Write-Ok "Docker is running inside WSL"

# --- Step 3: Create data directories inside WSL ---
Write-Host ""
Write-Host "=== Step 3: Create Data Directories (inside WSL) ==="

# Determine the repo path inside WSL. Assumes the repo is cloned under the
# WSL home directory (e.g., ~/ai-platform). Adjust AI_PLATFORM_WSL_PATH if
# the repo lives elsewhere.
$wslUser = (wsl -- whoami).Trim()
$AI_PLATFORM_WSL_PATH = "/home/$wslUser/ai-platform"

wsl -- bash -c @"
set -e
cd $AI_PLATFORM_WSL_PATH || { echo 'Repo not found at $AI_PLATFORM_WSL_PATH'; exit 1; }
for d in postgres kafka redis prometheus grafana pgadmin redisinsight; do
    mkdir -p data/`$d
done
sudo chown -R 472:472 data/grafana
sudo chmod -R 777     data/prometheus
sudo chown -R 5050:5050 data/pgadmin
echo 'Data directories created and permissions set'
"@
Write-Ok "Data directories ready"

# --- Step 4: Environment file ---
Write-Host ""
Write-Host "=== Step 4: Environment File ==="

$envExists = wsl -- bash -c "test -f $AI_PLATFORM_WSL_PATH/.env && echo YES || echo NO"
if ($envExists.Trim() -eq "NO") {
    wsl -- bash -c "cp $AI_PLATFORM_WSL_PATH/.env.example $AI_PLATFORM_WSL_PATH/.env"
    Write-Warn ".env created from .env.example — edit passwords before production use"
} else {
    Write-Ok ".env already exists"
}

# --- Step 5: Port proxy rules for Tailscale access ---
Write-Host ""
Write-Host "=== Step 5: Configure Port Proxy (for Tailscale remote access) ==="
Write-Host "    These rules forward traffic from the Windows host to WSL2 Docker."
Write-Host "    Requires Administrator privileges."

$ports = @(
    @{ Name = "PostgreSQL";   Port = 5432 },
    @{ Name = "Kafka";        Port = 9094 },
    @{ Name = "Redis";        Port = 6379 },
    @{ Name = "Grafana";      Port = 3000 },
    @{ Name = "Prometheus";   Port = 9090 },
    @{ Name = "Kafka UI";     Port = 8080 },
    @{ Name = "pgAdmin4";     Port = 5050 },
    @{ Name = "RedisInsight";  Port = 5540 }
)

foreach ($p in $ports) {
    try {
        netsh interface portproxy add v4tov4 listenport=$($p.Port) listenaddress=0.0.0.0 connectport=$($p.Port) connectaddress=127.0.0.1 2>&1 | Out-Null
        Write-Ok "$($p.Name) :$($p.Port)"
    } catch {
        Write-Warn "Could not set port proxy for $($p.Name) :$($p.Port)"
    }
}

# Firewall rule (single rule covering all ports)
$allPorts = ($ports | ForEach-Object { $_.Port }) -join ","
try {
    netsh advfirewall firewall delete rule name="AI Platform" 2>&1 | Out-Null
    netsh advfirewall firewall add rule name="AI Platform" dir=in action=allow protocol=TCP localport=$allPorts 2>&1 | Out-Null
    Write-Ok "Firewall rule 'AI Platform' created for ports: $allPorts"
} catch {
    Write-Warn "Could not create firewall rule — you may need to add it manually"
}

# --- Step 6: Start the stack ---
Write-Host ""
Write-Host "=== Step 6: Start Platform ==="

wsl -- bash -c "cd $AI_PLATFORM_WSL_PATH && docker compose up -d"

Write-Host ""
Write-Host "============================================="
Write-Host "  AI Platform is starting!"
Write-Host "============================================="
Write-Host ""
Write-Host "  From WSL, run: cd $AI_PLATFORM_WSL_PATH && ./scripts/status.sh"
Write-Host ""
