#!/usr/bin/env bash
# Deploie la stack Nextcloud sur le NAS Synology 192.168.1.71
# Usage : ./deploy.sh
# Necessite que le .env soit deja genere (voir README).

set -euo pipefail

NAS_HOST="rkchouk@192.168.1.71"
NAS_PORT=51
NAS_DIR="/volume1/docker/nextcloud-stack"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"

cyan()  { printf "\033[1;36m%s\033[0m\n" "$*"; }
green() { printf "\033[1;32m%s\033[0m\n" "$*"; }
red()   { printf "\033[1;31m%s\033[0m\n" "$*"; }

if [ ! -f "$SRC_DIR/.env" ]; then
    red "ERREUR : $SRC_DIR/.env manquant. Genere-le d'abord (voir README)."
    exit 1
fi

cyan "==> [1/3] Copie de la stack vers $NAS_HOST:$NAS_DIR"
scp -P $NAS_PORT -O -r "$SRC_DIR" "$NAS_HOST:/volume1/docker/"

cyan "==> [2/3] Setup NAS (ACL + docker compose up) via sudo a distance"
# -tt force allocation d'un TTY pour que sudo puisse demander son mdp interactivement.
chmod +x "$SRC_DIR/nas-setup.sh" 2>/dev/null || true
ssh -tt -p $NAS_PORT "$NAS_HOST" "sudo bash $NAS_DIR/nas-setup.sh"

cyan "==> [3/3] Verification : curl http://192.168.1.71:8080"
sleep 8
if curl -fsS -I http://192.168.1.71:8080 -o /dev/null --max-time 10; then
    green "OK Nextcloud repond sur :8080"
else
    red "Nextcloud ne repond pas encore (peut prendre 30-60s au premier boot). Logs :"
    red "  ssh -p 51 rkchouk@192.168.1.71 'cd $NAS_DIR && sudo docker compose logs app --tail 50'"
fi

green ""
green "==> Termine. Etapes suivantes :"
echo "  1. Reverse Proxy DSM : ajouter cloud.arkerion.fr -> localhost:8080 et office.arkerion.fr -> localhost:9980"
echo "  2. DNS : creer A records cloud.arkerion.fr + office.arkerion.fr -> meme IP que arkpilot.arkerion.fr"
echo "  3. Cert Let's Encrypt SAN : ajouter cloud + office au certif existant"
echo "  4. Connexion sur https://cloud.arkerion.fr (admin: rudy / cf .env) et configurer External Storages + Collabora"
