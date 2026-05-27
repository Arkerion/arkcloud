#!/usr/bin/env bash
# Execute SUR le NAS (necessite sudo). Configure les ACL et lance docker compose.
set -euo pipefail

STACK_DIR="/volume1/docker/nextcloud-stack"

echo "==> Detection des outils de permission disponibles"
SYNOACL=""
for p in /usr/syno/bin/synoacltool /usr/syno/sbin/synoacltool /usr/local/bin/synoacltool; do
    if [ -x "$p" ]; then SYNOACL="$p"; break; fi
done

SETFACL=""
for p in /usr/bin/setfacl /bin/setfacl /opt/bin/setfacl; do
    if [ -x "$p" ]; then SETFACL="$p"; break; fi
done

echo "  synoacltool : ${SYNOACL:-NON TROUVE}"
echo "  setfacl     : ${SETFACL:-NON TROUVE}"

echo ""
echo "==> Application des permissions sur /volume1/ADMINISTRATION et /volume1/HUB"
for D in /volume1/ADMINISTRATION /volume1/HUB; do
    if [ ! -d "$D" ]; then
        echo "[!] $D n'existe pas, skip"
        continue
    fi
    echo "  [+] Traitement de $D"
    if [ -n "$SYNOACL" ]; then
        # On accorde l'acces au groupe 'users' (GID 100) qui contient tous les comptes humains du NAS.
        # Le container Nextcloud sera lance avec ce GID via 'group_add' dans le compose.
        $SYNOACL -add "$D" "group:users:allow:rwxpdDaARWcCo:fd--" || \
            echo "    [!] synoacltool a echoue, fallback chmod"
    elif [ -n "$SETFACL" ]; then
        $SETFACL -R -m u:33:rwX "$D"
        $SETFACL -R -d -m u:33:rwX "$D"
    else
        echo "    [!] Aucun outil ACL trouve, fallback chmod o+rwX (moins propre)"
        chmod -R o+rwX "$D"
    fi
done

echo ""
echo "==> Diagnostic permissions actuelles"
ls -la /volume1/ | grep -E 'ADMINISTRATION|HUB' || true

echo ""
echo "==> Detection du binaire docker"
DOCKER=""
for p in /usr/local/bin/docker /usr/bin/docker /volume1/@appstore/ContainerManager/usr/bin/docker /volume1/@appstore/Docker/usr/bin/docker; do
    if [ -x "$p" ]; then DOCKER="$p"; break; fi
done
if [ -z "$DOCKER" ]; then
    echo "[!] docker introuvable. Cherche manuellement :"
    find / -name docker -type f -executable 2>/dev/null | head -5
    exit 1
fi
echo "  docker : $DOCKER"

# Test plugin compose v2 vs binaire docker-compose v1
if $DOCKER compose version >/dev/null 2>&1; then
    COMPOSE="$DOCKER compose"
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE="docker-compose"
else
    echo "[!] Ni 'docker compose' ni 'docker-compose' disponibles"
    exit 1
fi
echo "  compose : $COMPOSE"

echo ""
echo "==> docker compose pull"
cd "$STACK_DIR"
$COMPOSE pull

echo ""
echo "==> docker compose up -d"
$COMPOSE up -d

echo ""
echo "==> Statut des containers (attendre ~10s la stabilisation) :"
sleep 10
$COMPOSE ps
