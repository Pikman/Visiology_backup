#! /bin/bash
set -euxo pipefail
date

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

# backup

#the block responsible for the monogodb backup
ID=$(docker ps | grep visiology.admin | awk '{print $1}')
user=""
password=""
if [ ! -z $(docker exec -i $ID sh -c "cat secrets/MONGO_AUTH_USER") ];
then
        #echo "Файл существует";
        user="$(echo `docker exec -i $ID sh -c "cat secrets/MONGO_AUTH_USER"`)";
        password="$(echo `docker exec -i $ID sh -c "cat secrets/MONGO_AUTH_PASSWORD"`)";
fi
sudo docker exec -i $(docker ps --format "{{.Names}}" --filter name=mongo) mongodump --username="$user" --password="$password" -d VisiologyVA -h 127.0.0.1:27017 --out /data/db/dump/

#data-collection check and backup
DC_cont_name=$(docker ps --format "{{.Names}}" --filter name=data-c)
if docker ps | grep data-collection-db
  then DC_cont_name=$(docker ps --format "{{.Names}}" --filter name=data-collection-db)
fi
sudo docker exec -i $DC_cont_name  bash -c "PGPASSWORD="Postgres9" pg_dump -h 127.0.0.1 -U postgres --format custom --blobs \
-d $(grep DataBase /docker-volume/data-collection/config.json  | cut -d\" -f4) \
> /mnt/volume/DB.backup" && \

pushd /docker-volume 
sudo tar \
--exclude='./data-collection/postgresql' \
--exclude='./ssbi/postgresql' \
--exclude='./ssbi/logs' \
--exclude='./viqube/log' \
--exclude='./viqube/apiLog' \
--exclude='./viqube/crashdumps' \
--exclude='./viqube-admin/logs' \
-czf visiology-$(hostname)-before-restore.tar.gz  ./admin/  ./dashboard-service/ ./dashboard-viewer/ \
./data-collection/DB.backup ./identity-server/ ./mongodb/dump/ ./proxy/ ./ssbi/ ./viqube/  ./viqube-admin/ 

popd
echo "Unpacking $1..."
tar -xf $1 --one-top-level
cd $(basename $1 .tar.gz)
pwd

# mongo
rm \
    mongodb/dump/VisiologyVA/GeneralSettings.* \
    mongodb/dump/VisiologyVA/LdapSettings.* \
    mongodb/dump/VisiologyVA/WebappEmailSettings.*  \
    mongodb/dump/VisiologyVA/Users.* \
    mongodb/dump/VisiologyVA/UserRoles.* \
    mongodb/dump/VisiologyVA/HomeDashboard.*
mkdir -p /docker-volume/mongodb/dump/VisiologyVA/
cp -r mongodb/dump/VisiologyVA/* /docker-volume/mongodb/dump/VisiologyVA/ 
docker exec -i $(docker ps --format "{{.Names}}" --filter name=mongo) mongorestore --username="$user" --password="$password" -d VisiologyVA -h 127.0.0.1:27017 --drop /data/db/dump/VisiologyVA

# dc
CONFDB=/docker-volume/data-collection/config.json

if [ -f $CONFDB ]; then
    DC_DB="$(grep DataBase /docker-volume/data-collection/config.json  | cut -d\" -f4)"
    echo  "SELECT pg_terminate_backend(pg_stat_activity.pid)
    FROM pg_stat_activity
    WHERE pg_stat_activity.datname = '$DC_DB'
    AND pid <> pg_backend_pid();
    DROP DATABASE \"$DC_DB\";
    create database \"$DC_DB\";" > db_del.sql
    echo "файл db_del.sql создан"
else
   echo "Файл '$CONFDB' не найден."
#   exit 1
fi

docker cp db_del.sql  $DC_cont_name:/application/db_del.sql 
rm db_del.sql 
docker exec $DC_cont_name bash -c "PGPASSWORD='Postgres9' psql -h 127.0.0.1 -U postgres -a -f db_del.sql" 
cp data-collection/DB.backup /docker-volume/data-collection/ 
docker exec $DC_cont_name bash -c "PGPASSWORD='Postgres9' pg_restore -h 127.0.0.1 -U postgres -d $DC_DB \
 /mnt/volume/DB.backup"

# vq
cp -r viqube/snapshots/auto.snapshot /docker-volume/viqube/snapshots/ 
#docker restart viqube || \
#(docker service scale visiology_viqube-master=0 && docker service scale visiology_viqube-master=1)

# rest of things
cp -rv admin/* /docker-volume/admin/ 
cp -rv dashboard-service/* /docker-volume/dashboard-service/ 
cp -rv dashboard-viewer/* /docker-volume/dashboard-viewer/ 
cp -rv ssbi/* /docker-volume/ssbi/ 
cp -rv viqube-admin /docker-volume/ 
cp -rv identity-server /docker-volume/ 
chown $USER:$USER -R /docker-volume/ssbi /docker-volume/viqube /docker-volume/viqube-admin

cd .. && rm -rf $(basename $1 .tar.gz)
pwd
echo "Restore finished"
date
echo "History of run.sh:"
cat /home/$USER/.bash_history | grep run.sh | tail -10
