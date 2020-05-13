#!/bin/sh
set -x
set -e

env

yum update -y -q

echo "S3 Bucket Info"
aws s3 ls s3://$QS_BUCKET_NAME/
aws s3 ls s3://$QS_BUCKET_NAME/$QS_KEY_PREFIX
aws s3 ls s3://$P_INSTALL_BUCKET_NAME/
aws s3 ls s3://$P_INSTALL_BUCKET_NAME/$P_INSTALL_BUCKET_PREFIX/


yum install -y -q  unzip
yum install -y -q  amazon-linux-extras install docker
usermod -a -G docker ec2-user
systemctl enable docker
systemctl start docker
docker version


mkdir -p /project/browser/
mkdir -p /project/scripts/
chmod -R 755 /project/browser
aws s3 cp s3://$QS_BUCKET_NAME/${QS_KEY_PREFIX}infra/ /project/browser/ --recursive --quiet
aws s3 sync s3://$QS_BUCKET_NAME/${QS_KEY_PREFIX}scripts/ /project/scripts/ --exclude "*.*" --include "*.sh"

chmod +x /project/scripts/*.sh
chown -R ec2-user:ec2-user /project
ls -lsa  /project/browser/

mv /project/browser/infrastructor/templates/browser.service.tmpl /etc/systemd/system/browser.service
chmod 644 /etc/systemd/system/browser.service
chown root:root /etc/systemd/system/browser.service


#curl -fsSL https://goss.rocks/install | sh
#/usr/local/bin/goss -g  /project/browser/infrastructor/goss/goss-base.yaml validate --sleep 60s --retry-timeout 30s
#echo "GOSS validate Success"

curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
python get-pip.py
pip install -q https://s3.amazonaws.com/cloudformation-examples/aws-cfn-bootstrap-latest.tar.gz
/opt/aws/bin/cfn-init -v --stack $AWS_STACK_NAME --resource rAutoScalingConfigApp --configsets MountConfig --region $AWS_REGION
crontab /home/ec2-user/crontab



export TMP_CONFIG_DIR=/efs/config/tmp
export TMP_STATUS=$TMP_CONFIG_DIR/status

rm -rf $TMP_CONFIG_DIR


# Configs
export TMP_BROWSER_PROPERTIES=$TMP_CONFIG_DIR/browser.properties
export TMP_LICENSE=$TMP_CONFIG_DIR/dotmatics.license.txt
export TMP_BIOREGISTER_GROOVY=$TMP_CONFIG_DIR/bioregister.groovy
export EFS_BROWSER_DIR=/efs/data/browser/WEB-INF
export EFS_BROWSER_PROPERTIES=$EFS_BROWSER_DIR/browser.properties
export EFS_BROWSER_LICENSE=$EFS_BROWSER_DIR/dotmatics.license.txt
export EFS_BIOREGISTER_DIR=/efs/data/bioregister
export EFS_BIOREGISTER_GROOVY=/efs/data/bioregister.groovy
export EFS_CUSTOMED_BROWSER_DIR=$TMP_CONFIG_DIR/browser


# Persistent Files
export EFS_BROWSER_PDF_DIR=/efs/data/browser/pdf
export EFS_BROWSER_RAW_DIR="/efs/data/browser/raw data"
export EFS_BROWSER_TEMP_DIR=/efs/data/browser/tempfiles
export EFS_BROWSER_PROFILES_DIR=/efs/data/browser/profiles
export EFS_BIOREGISTER_C2C_DIR=/efs/data/bioregister/c2c_attachments



# Logs
export EFS_BROWSER_LOG_DIR=/efs/logs/browser/
export EFS_BIOREGISTER_LOG_DIR=/efs/logs/bioregister/
export EFS_BACKUP_DIR=/efs/backup/
export EFS_WARN_FILE=/efs/data/WARN.txt

mkdir -p $TMP_CONFIG_DIR
mkdir -p $EFS_BROWSER_DIR
mkdir -p $EFS_BROWSER_PDF_DIR
mkdir -p "$EFS_BROWSER_RAW_DIR"
mkdir -p $EFS_BROWSER_TEMP_DIR
mkdir -p $EFS_BROWSER_PROFILES_DIR
mkdir -p $EFS_BIOREGISTER_DIR
mkdir -p $EFS_BIOREGISTER_C2C_DIR
mkdir -p $EFS_BACKUP_DIR
mkdir -p $EFS_BROWSER_LOG_DIR
mkdir -p $EFS_BIOREGISTER_LOG_DIR
mkdir -p $EFS_CUSTOMED_BROWSER_DIR



echo "Downloading Installation files."
aws s3 cp s3://$P_INSTALL_BUCKET_NAME/$P_INSTALL_BUCKET_PREFIX/browser.properties  $TMP_BROWSER_PROPERTIES || true
aws s3 cp s3://$P_INSTALL_BUCKET_NAME/$P_INSTALL_BUCKET_PREFIX/dotmatics.license.txt  $TMP_LICENSE || true
aws s3 sync s3://$P_INSTALL_BUCKET_NAME/$P_INSTALL_BUCKET_PREFIX/   $TMP_CONFIG_DIR/ --exclude "*.*" --include "browser-install-*.zip" --quiet
aws s3 sync s3://$P_INSTALL_BUCKET_NAME/$P_INSTALL_BUCKET_PREFIX/   $TMP_CONFIG_DIR/  --exclude "*.*" --include "bioregister-*.war" --quiet
aws s3 sync s3://$P_INSTALL_BUCKET_NAME/$P_INSTALL_BUCKET_PREFIX/   $TMP_CONFIG_DIR/  --exclude "*.*" --include "bioregister.groovy" --quiet
aws s3 sync s3://$P_INSTALL_BUCKET_NAME/$P_INSTALL_BUCKET_PREFIX/browser/   $EFS_CUSTOMED_BROWSER_DIR/
aws s3 cp s3://$QS_BUCKET_NAME/${QS_KEY_PREFIX}infra/efs/data/WARN.txt $EFS_WARN_FILE  --quiet

ls -ls $TMP_CONFIG_DIR

export TMP_BROWSER_ZIP_FILE=$(ls $TMP_CONFIG_DIR/browser-*)
export TMP_BIOREGISTER_WAR_FILE=$(ls $TMP_CONFIG_DIR/bioregister-*)
export TMP_BROWSER_ZIP_COUNT=$(ls $TMP_CONFIG_DIR/browser-* | wc -l | xargs )
export TMP_BIOREGISTER_WAR_COUNT=$(ls $TMP_CONFIG_DIR/bioregister-* | wc -l | xargs )

echo "TMP_BROWSER_ZIP_FILE=$TMP_BROWSER_ZIP_FILE"
echo "TMP_BIOREGISTER_WAR_FILE=$TMP_BIOREGISTER_WAR_FILE"


if [ -z "$TMP_BROWSER_ZIP_FILE" ]
then
  echo "[ERROR] browser installation zip doesn't exist."
  exit 1

elif [ "$TMP_BROWSER_ZIP_COUNT" -gt 1 ]
then
  ls -ls $TMP_CONFIG_DIR
  echo "[ERROR] Too many browser installation zip files."
  exit 1

elif [ ! -f  "$TMP_LICENSE" ]; then
  echo '[ERROR] $TMP_LICENSE not found '
  exit 1
fi


if [ -z "$TMP_BIOREGISTER_WAR_FILE" ]; then
    echo "[WARN] There is no bioregister installation zip file."

elif [ "$TMP_BIOREGISTER_WAR_COUNT" -gt 1 ] ; then
    echo "[ERROR] Too many bioregister installation zip files."
    exit 1

else
  if [  -f "$TMP_BIOREGISTER_GROOVY" ]; then
      echo "$TMP_BIOREGISTER_WAR_FILE and $TMP_BIOREGISTER_GROOVY both exist. "
  else
      echo "[ERROR] Bioregister installation zip file exists, but $TMP_BIOREGISTER_GROOVY doesn't exist"
      exit 1
  fi
fi



if [  ! -f "$TMP_BROWSER_PROPERTIES" ]; then
    echo '[WARN] Not found $TMP_BROWSER_PROPERTIES. Please check whether you upload browser.properties to s3.'
    echo "Start using browser.properties file from installation zip file."
    unzip -p $TMP_BROWSER_ZIP_FILE WEB-INF/browser.properties > $TMP_BROWSER_PROPERTIES
    sed -i '/^db.dba.user/s/=.*$/='SYSTEM'/' $TMP_BROWSER_PROPERTIES
    ls -ls $TMP_CONFIG_DIR
    cat $TMP_BROWSER_PROPERTIES | grep user
fi


if [  -f "$TMP_BROWSER_PROPERTIES" ]; then
    if [  -f  "$EFS_BROWSER_PROPERTIES" ]; then
        echo "$EFS_BROWSER_PROPERTIES exists"
        echo "Merging new keys into current properties"

        docker run --rm -t -uroot \
          -v /project/browser/groovy/MergeProps.groovy:/tmp/MergeProps.groovy \
          -v $EFS_BROWSER_PROPERTIES:/tmp/efs/browser.properties:z \
          -v $TMP_BROWSER_PROPERTIES:/tmp/tmp/browser.properties:z   \
          groovy:jre8 groovy /tmp/MergeProps.groovy
    fi

    ### If db.dba.user is empty, then assign new user to it
    docker run --rm -t -uroot \
      -v /project/browser/groovy/CheckProps.groovy:/tmp/CheckProps.groovy \
      -v $TMP_BROWSER_PROPERTIES:/tmp/browser.properties:z   \
      groovy:jre8 groovy /tmp/CheckProps.groovy


    echo "Setup updates.setting=new in $TMP_BROWSER_PROPERTIES"
    sed -i '/^updates.setting/s/=.*$/=new/' $TMP_BROWSER_PROPERTIES

    sed -i '/^db.description/s/=.*$/=(DESCRIPTION\\=(ADDRESS\\=(PROTOCOL\\=TCP)(HOST\\='$PRIVATE_DNS_NAME')(PORT\\='$DATABASE_PORT'))(CONNECT_DATA\\=(SERVICE_NAME\\='$P_DATABASE_NAME')) )/' $TMP_BROWSER_PROPERTIES
    sed -i '/^db.server/s/=.*$/='$PRIVATE_DNS_NAME'/' $TMP_BROWSER_PROPERTIES
    sed -i '/^db.dba.password/s/=.*$/='$P_DATABASE_PASS'/' $TMP_BROWSER_PROPERTIES
    sed -i '/^db.sid/s/=.*$/='$P_DATABASE_NAME'/' $TMP_BROWSER_PROPERTIES

    if [ "$P_DNS_ZONE_ID" = '' ]; then
        echo "pDnsHostedZoneID is empty."
        sed -i '/^app.browserurl/s/=.*$/=http:\/\/'$ALB_DNS_NAME'/' $TMP_BROWSER_PROPERTIES

    elif [ "$P_DNS_ZONE_APEX_DOMAIN" = '' ]; then
        echo "pDnsZoneApexDomain is empty."
        sed -i '/^app.browserurl/s/=.*$/=http:\/\/'$ALB_DNS_NAME'/' $TMP_BROWSER_PROPERTIES

    else
        echo "pDnsHostedZoneID and pDnsZoneApexDomain are not empty."
        sed -i '/^app.browserurl/s/=.*$/=https:\/\/'$P_DNS_NAME'.'$P_DNS_ZONE_APEX_DOMAIN'/' $TMP_BROWSER_PROPERTIES
    fi
fi

echo "updated tmp browser.properties at $(date)"

#Backup webapps before installation/upgrade
export BACKUP_DATE=$(date +'%Y-%m%d-%Hh%M')
mkdir -p /efs/backup/$BACKUP_DATE/

if [  -f "$EFS_BROWSER_PROPERTIES" ]; then
    cp -r $EFS_BROWSER_PROPERTIES /efs/backup/$BACKUP_DATE/
    cp -r $EFS_BROWSER_LICENSE /efs/backup/$BACKUP_DATE/
    echo "backup browser.properties done at $(date)"
fi

/project/scripts/update-bioregister-groovy.sh  BACKUP_DATE=$BACKUP_DATE


echo "copy browser properties to efs"
yes | cp $TMP_BROWSER_PROPERTIES $EFS_BROWSER_PROPERTIES
yes | cp $TMP_LICENSE $EFS_BROWSER_LICENSE

rm -rf $TMP_BROWSER_PROPERTIES
rm -rf $TMP_LICENSE

ls -ls $TMP_CONFIG_DIR

chown -R ec2-user:ec2-user /efs/
chown -R ec2-user:ec2-user /project
echo "chown done at $(date)"

cat $EFS_BROWSER_PROPERTIES  | grep updates.setting >> $TMP_STATUS

docker swarm init
systemctl stop browser.service
systemctl start browser.service
sleep 5
systemctl status browser.service
docker version
docker service ls

echo "export EFS_BROWSER_PROPERTIES=$EFS_BROWSER_PROPERTIES" >> /etc/environment
source /etc/environment

echo "Installation finished"
echo "userdata done." >> $TMP_STATUS
/opt/aws/bin/cfn-signal -e $? --stack $AWS_STACK_NAME --resource rAutoScalingGroupApp --region $AWS_REGION