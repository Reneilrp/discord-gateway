# ==============================================================================
# windows-portproxy-setup.ps1
# ------------------------------------------------------------------------------
# Run as Administrator in PowerShell on Windows 11.
# Only needed if you are NOT using networkingMode=mirrored in .wslconfig.
# Forwards ports 443 and 8000 from Windows WireGuard (10.0.0.2) to WSL localhost.
# ==============================================================================

Write-Host "Configuring Windows 11 Port Proxy for WSL 2 Marzban..." -ForegroundColor Cyan

# 1. Forward Port 443 (VLESS Proxy)
netsh interface portproxy delete v4tov4 listenport=443 listenaddress=10.0.0.2 2>$null
netsh interface portproxy add v4tov4 listenport=443 listenaddress=10.0.0.2 connectport=443 connectaddress=127.0.0.1
Write-Host "[OK] Port 443 forwarded: 10.0.0.2:443 -> 127.0.0.1:443" -ForegroundColor Green

# 2. Forward Port 8000 (Marzban Web Dashboard)
netsh interface portproxy delete v4tov4 listenport=8000 listenaddress=10.0.0.2 2>$null
netsh interface portproxy add v4tov4 listenport=8000 listenaddress=10.0.0.2 connectport=8000 connectaddress=127.0.0.1
Write-Host "[OK] Port 8000 forwarded: 10.0.0.2:8000 -> 127.0.0.1:8000" -ForegroundColor Green

# 3. Allow through Windows Defender Firewall
netsh advfirewall firewall delete rule name="Marzban-VLESS-443" 2>$null
netsh advfirewall firewall add rule name="Marzban-VLESS-443" dir=in action=allow protocol=TCP localport=443
netsh advfirewall firewall delete rule name="Marzban-Web-8000" 2>$null
netsh advfirewall firewall add rule name="Marzban-Web-8000" dir=in action=allow protocol=TCP localport=8000
Write-Host "[OK] Windows Firewall rules created for ports 443 and 8000" -ForegroundColor Green

Write-Host "`nCurrent Active Port Proxies:" -ForegroundColor Yellow
netsh interface portproxy show all
