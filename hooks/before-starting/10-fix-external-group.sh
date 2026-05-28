#!/bin/sh
# www-data doit etre membre du gid 100 (groupe 'users' Synology) pour acceder
# aux External Storage /external/* via l'ACL synology (group:users:allow:rwx).
#
# Pourquoi ce hook : group_add:["100"] dans le compose ajoute le gid au PID 1,
# mais Apache fait son propre initgroups() en lisant /etc/group DU CONTAINER au
# lancement de ses workers www-data -> il perd le gid 100 -> opendir Permission
# denied sur les dossiers montes. On ajoute donc www-data au groupe 100 DANS
# /etc/group du container, ce qu'Apache respectera. Idempotent, rejoue a chaque boot.
set -e
getent group 100 >/dev/null 2>&1 || groupadd -g 100 hostusers
usermod -aG 100 www-data
echo "[hook] www-data ajoute au gid 100 : $(id www-data)"
