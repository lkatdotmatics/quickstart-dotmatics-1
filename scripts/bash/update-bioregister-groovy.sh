#!/bin/sh
set -x


export TMP_BIOREGISTER_WAR_FILE=$(ls $TMP_CONFIG_DIR/bioregister-*)
export TMP_BIOREGISTER_WAR_COUNT=$(ls $TMP_CONFIG_DIR/bioregister-* | wc -l | xargs )
echo "TMP_BIOREGISTER_WAR_FILE=$TMP_BIOREGISTER_WAR_FILE"


aws s3 cp s3://$P_INSTALL_BUCKET_NAME/$P_INSTALL_BUCKET_PREFIX/bioregister.groovy   $TMP_CONFIG_DIR/  || true

if [ -z "$TMP_BIOREGISTER_WAR_FILE" ]; then
    echo "[WARN] There is no bioregister installation zip file."

elif [ "$TMP_BIOREGISTER_WAR_COUNT" -gt 1 ] ; then
    echo "[ERROR] Too many bioregister installation zip files."
    exit 1

else
  if [  -f "$TMP_BIOREGISTER_GROOVY" ]; then
        echo "$TMP_BIOREGISTER_WAR_FILE and $TMP_BIOREGISTER_GROOVY both exist. "

        echo "bioregister.groovy exists,then update ServerURL and oracle host."

        if [   -f  "$EFS_BIOREGISTER_GROOVY" ]; then
            export BIOREGISTER_PASSWORD=$(cat $EFS_BIOREGISTER_GROOVY | grep password= |  cut -d"'" -f2 | xargs)
            sed -i 's/password=\x27.*\x27/password=\x27'$BIOREGISTER_PASSWORD'\x27\n\tpasswordEncryptionCodec=BrowserEncryptionCodec/g' $TMP_BIOREGISTER_GROOVY
            cat $TMP_BIOREGISTER_GROOVY | grep password=
        fi

        sed -i 's/http:\/\/localhost:8080/'$APP_SERVER_URL'/g'  $TMP_BIOREGISTER_GROOVY
        sed -i 's/localhost/'$PRIVATE_DNS_NAME'/g'  $TMP_BIOREGISTER_GROOVY
        sed -i 's/c:\\\\c2c_attachments/\/c2c_attachments/g' $TMP_BIOREGISTER_GROOVY
        sed -i 's/XE/'$P_DATABASE_NAME'/g' $TMP_BIOREGISTER_GROOVY
        echo "updating browser.properties done at $(date)"


        if [ -z "$BACKUP_DATE" ]; then
            echo "BACKUP_DATE env is a empty string"
            export BACKUP_DATE=$(date +'%Y-%m%d-%Hh%M')
        else
            echo "BACKUP_DATE has the value: $BACKUP_DATE"
        fi

        if [  -f "$EFS_BIOREGISTER_GROOVY" ]; then
            mkdir -p /efs/backup/$BACKUP_DATE/
            ls -ls  $EFS_BIOREGISTER_GROOVY || true
            cp -r $EFS_BIOREGISTER_GROOVY /efs/backup/$BACKUP_DATE/
        fi

       echo "Moving bioregister.groovy from tmp to EFS ... "
       yes | mv $TMP_BIOREGISTER_GROOVY $EFS_BIOREGISTER_GROOVY


       export BIOREGISTER_CONTAINER_ID=$( docker ps --filter label=app.name=bioregister --format {{.ID}} )

       if [ ! -z "$BIOREGISTER_CONTAINER_ID" ]; then
            docker ps
            echo "Restarting bioregister container ..."
            docker stop $BIOREGISTER_CONTAINER_ID
       fi


  else
      echo "[ERROR] Bioregister installation zip file exists, but $TMP_BIOREGISTER_GROOVY doesn't exist"
      exit 1
  fi
fi



