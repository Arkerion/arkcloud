# Nextcloud sur NAS Synology (remplacement Synology Drive)

Stack : Nextcloud + MariaDB + Redis + Collabora Online.
HTTPS termine par le **Reverse Proxy DSM** existant (celui qui sert deja arkpilot.arkerion.fr).

## Architecture

```
Internet
   |
   v  port 443 (deja NAT WAN 443 -> LAN 443 sur la box)
[Reverse Proxy DSM] --- cloud.arkerion.fr  --> 127.0.0.1:8080  (container Nextcloud)
                  --- office.arkerion.fr --> 127.0.0.1:9980  (container Collabora)
                  --- arkpilot.arkerion.fr -> 127.0.0.1:9009  (deja en place)
```

## Avant le premier deploiement

### 1. DNS Cloudflare (ou registrar)
Creer 2 enregistrements A (ou CNAME vers arkpilot.arkerion.fr) :
- `cloud.arkerion.fr`  -> meme IP publique que arkpilot
- `office.arkerion.fr` -> meme IP publique

### 2. Permissions sur les dossiers NAS (cle pour que Nextcloud puisse ecrire)
Le container tourne en UID 33 (www-data). Pour qu'il puisse lire/ecrire dans
`/volume1/ADMINISTRATION` et `/volume1/HUB` SANS casser l'acces SMB des users
Synology, on utilise des ACL POSIX :

```bash
ssh -p 51 rkchouk@192.168.1.71
sudo synoacltool -add /volume1/ADMINISTRATION "user:www-data:allow:rwxpdDaARWcCo:fd--"
sudo synoacltool -add /volume1/HUB "user:www-data:allow:rwxpdDaARWcCo:fd--"
```

Si `synoacltool` ne reconnait pas `www-data`, fallback setfacl :
```bash
sudo setfacl -R -m u:33:rwX /volume1/ADMINISTRATION
sudo setfacl -R -d -m u:33:rwX /volume1/ADMINISTRATION
sudo setfacl -R -m u:33:rwX /volume1/HUB
sudo setfacl -R -d -m u:33:rwX /volume1/HUB
```

## Deploiement

### 1. Copier les fichiers sur le NAS
```bash
scp -P 51 -r /home/parallels/Documents/nextcloud-stack rkchouk@192.168.1.71:/volume1/docker/
```

### 2. Creer le .env avec les vrais secrets
```bash
ssh -p 51 rkchouk@192.168.1.71
cd /volume1/docker/nextcloud-stack
cp .env.example .env
nano .env   # remplacer tous les CHANGEME_*
```

### 3. Premier demarrage
```bash
sudo docker compose up -d
sudo docker compose logs -f app
```
Attendre `apache2 -D FOREGROUND` (1-2 min).

Verifier que ca repond en local :
```bash
curl -I http://192.168.1.71:8080
# doit renvoyer 302 vers /login
```

## Configuration Reverse Proxy DSM

Panneau de configuration > Portail des applications > **Reverse Proxy** > Creer.

### Entree 1 : cloud.arkerion.fr
| Champ | Valeur |
|---|---|
| Source - Protocole | HTTPS |
| Source - Nom d'hote | cloud.arkerion.fr |
| Source - Port | 443 |
| Activer HSTS | OK |
| Destination - Protocole | HTTP |
| Destination - Nom d'hote | localhost |
| Destination - Port | 8080 |

Onglet **En-tetes personnalises** > "Creer" > "WebSocket" (preset).
Ajouter aussi 3 entetes manuelles (sinon Nextcloud genere des liens en http://) :
- `X-Forwarded-Proto` = `https`
- `X-Forwarded-Host` = `cloud.arkerion.fr`
- `X-Real-IP` = `$remote_addr`

Onglet **Avance** > "Custom headers" pour autoriser les gros uploads :
- `client_max_body_size` = `16G` (si l'option est exposee dans ta version de DSM)
Sinon, override via `/etc/nginx/sites-enabled/server.ReverseProxy.conf` apres le reload (Synology peut reset, prevoir un script post-config).

### Entree 2 : office.arkerion.fr
Idem mais Destination port = `9980`.
Onglet En-tetes : preset **WebSocket** obligatoire (Collabora utilise WS).

### Certificat Let's Encrypt
Panneau de configuration > Securite > Certificat.
- Editer le certificat *.arkerion.fr existant > "Ajouter d'autres noms d'hote (SAN)"
- Ajouter : `cloud.arkerion.fr`, `office.arkerion.fr`
- Re-emettre.
- Assigner ce certif aux 2 nouveaux services reverse proxy.

## Configuration post-installation Nextcloud

### A. External Storages (dossiers NAS)
1. Se connecter sur `https://cloud.arkerion.fr` avec le compte admin
2. App "External storage support" (deja installee par defaut, l'activer)
3. Parametres admin > External storage :
   - "ADMINISTRATION" -> type **Local** -> chemin `/external/ADMINISTRATION` -> disponible pour groupe "Administration"
   - "HUB" -> `/external/HUB` -> groupe "HUB"

### B. Groupes & users
Parametres > Utilisateurs > creer les groupes (Administration, HUB...) et les comptes.
Le partage par groupe se gere ensuite sur chaque External Storage (etape A).

### C. Collabora pour l'edition collaborative
1. Apps > Office & text > activer "Nextcloud Office"
2. Parametres admin > Nextcloud Office :
   - **"Use your own server"**
   - URL : `https://office.arkerion.fr`
3. Sauvegarder. Ouvrir un .docx -> doit s'ouvrir en mode collaboratif live.

### D. Reglages recommandes (corrige les warnings dans l'admin)
```bash
sudo docker compose exec --user www-data app php occ db:add-missing-indices
sudo docker compose exec --user www-data app php occ maintenance:repair --include-expensive
```

## Operations courantes

### Logs
```bash
sudo docker compose logs app --tail 50
sudo docker compose logs collabora --tail 50
```

### Mise a jour
```bash
cd /volume1/docker/nextcloud-stack
sudo docker compose pull
sudo docker compose up -d
```

### Sauvegarde
```bash
# DB
sudo docker compose exec db sh -c 'mariadb-dump -u root -p"$MYSQL_ROOT_PASSWORD" --single-transaction nextcloud' > backup-nc-$(date +%F).sql
# Config + apps (les data utilisateur sont sur /volume1, deja sauvegardees par Hyper Backup)
sudo docker run --rm -v nextcloud_nc_config:/c -v nextcloud_nc_apps:/a -v $(pwd):/backup alpine tar czf /backup/nc-config-$(date +%F).tar.gz -C / c a
```

### Mode maintenance
```bash
sudo docker compose exec --user www-data app php occ maintenance:mode --on
sudo docker compose exec --user www-data app php occ maintenance:mode --off
```

## Notes specifiques Synology

- Port SSH du NAS = 51 (deja documente en memoire ARKPILOT).
- Ne PAS utiliser le paquet Nextcloud du Centre de paquets en parallele -> conflit DB.
- Si tu veux exposer aussi `/volume1/homes`, ajouter un bind mount dans `docker-compose.yml` (service `app` ET `cron`) puis un External Storage dans l'UI.
- Les fichiers ajoutes via SMB (Synology Drive client classique) apparaitront dans Nextcloud apres un scan : `sudo docker compose exec --user www-data app php occ files:scan --all` (ou cron auto toutes les heures).
