#!/bin/bash

set -euxo pipefail

BACKUPNAME="${1:-$(hostname)-visiology-$(date +%d'.'%m'.'%Y)}"
BACKUPNAME=$BACKUPNAME'.tar.gz'

#next 3 line to backup version 2.21+
ID=$(docker ps | grep visiology.admin | awk '{print $1}')
user="$(echo `docker exec -it $ID sh -c "cat secrets/MONGO_AUTH_USER"`)"
password="$(echo `docker exec -it $ID sh -c "cat secrets/MONGO_AUTH_PASSWORD"`)"
sudo docker exec -i $(docker ps --format "{{.Names}}" --filter name=mongo)  mongodump -u $user -p $password -d VisiologyVA -h 127.0.0.1:27017 --out /data/db/dump/ && \
sudo docker exec -i $(docker ps --format "{{.Names}}" --filter name=data-collection-db)  bash -c "PGPASSWORD="Postgres9" pg_dump -h 127.0.0.1 -U postgres --format custom --blobs \
-d $(grep DataBase /docker-volume/data-collection/config.json  | cut -d\" -f4) \
> /mnt/volume/DB.backup" && \
cd /docker-volume && \
sudo tar \
--exclude='./data-collection/postgresql' \
--exclude='./ssbi/postgresql' \
--exclude='./ssbi/logs' \
--exclude='./viqube/log' \
--exclude='./viqube/apiLog' \
--exclude='./viqube/crashdumps' \
--exclude='./viqube-admin/logs' \
-czf $BACKUPNAME ./admin/  ./dashboard-service/ ./dashboard-viewer/ \
./data-collection/DB.backup ./identity-server/ ./mongodb/dump/ ./proxy/ ./ssbi/ ./viqube/  ./viqube-admin/ 
ls -lh /docker-volume/*.tar.gz

exit 0
