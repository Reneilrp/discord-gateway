#!/usr/bin/env bash
# ==============================================================================
# Helper to create/reset Marzban admin user in WSL
# ==============================================================================
docker exec -it marzban marzban cli admin create --sudo
