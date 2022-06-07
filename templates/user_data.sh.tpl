#!/bin/bash -xe

#!/bin/bash -xe
sleep 30
export PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/opt/aws/bin:/root/bin
dnf upgrade --assumeyes
#dnf install python3.9 --assumeyes
dnf install python3-pip --assumeyes
pip3.6 install -U pip
# upgrade awscli to latest stable
# upgrading pip from 9.0.3 to 10.0.1 changes the path from /usr/bin/pip to
# /usr/local/bin/pip and the line below throws this error
#     /var/lib/cloud/instance/scripts/part-001: line 10: /usr/bin/pip: No such file or directory
# So, I export the PATH in the beggining correctly but still tries to from the old location
# I couldn't see why in the outputs I'm going to hardcode it for now (01:10am)
pip3.6 install -U awscli

echo "* hard nofile 64000" >> /etc/security/limits.conf
echo "* soft nofile 64000" >> /etc/security/limits.conf
echo "root hard nofile 64000" >> /etc/security/limits.conf
echo "root soft nofile 64000" >> /etc/security/limits.conf

sudo tee /etc/yum.repos.d/mongodb-org-5.0.repo << EOF
[mongodb-org-5.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/8/mongodb-org/5.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-5.0.asc
EOF

sudo tee /etc/yum.repos.d/pritunl.repo << EOF
[pritunl]
name=Pritunl Repository
baseurl=https://repo.pritunl.com/stable/yum/oraclelinux/8/
gpgcheck=1
enabled=1
EOF

sudo yum -y install oracle-epel-release-el8
sudo yum-config-manager --enable ol8_developer_EPEL
sudo yum -y update
sudo yum -y install at tar cronie
systemctl enable --now crond.service atd
# WireGuard server support
sudo yum -y install wireguard-tools

sudo yum -y remove iptables-services
sudo systemctl stop firewalld.service
sudo systemctl disable firewalld.service

# Import signing key from keyserver
gpg --keyserver hkp://keyserver.ubuntu.com --recv-keys 7568D9BB55FF9E5287D586017AE645C0CF8E292A
gpg --armor --export 7568D9BB55FF9E5287D586017AE645C0CF8E292A > key.tmp; sudo rpm --import key.tmp; rm -f key.tmp
# Alternative import from download if keyserver offline
sudo rpm --import https://raw.githubusercontent.com/pritunl/pgp/master/pritunl_repo_pub.asc

sudo yum -y install pritunl mongodb-org
sudo systemctl enable mongod pritunl
sudo systemctl start mongod pritunl


cd /tmp
curl https://amazon-ssm-eu-west-1.s3.amazonaws.com/latest/linux_amd64/amazon-ssm-agent.rpm -o amazon-ssm-agent.rpm
yum install -y amazon-ssm-agent.rpm
status amazon-ssm-agent || start amazon-ssm-agent
sleep 10
pritunl setup-key > setup-key.txt

sleep 30
aws s3 cp setup-key.txt s3://${s3_backup_bucket}
#aws s3 cp /var/lib/pritunl/pritunl.uuid s3://${s3_backup_bucket}
echo "Envoi des fichier setup fait"
rm setup-key.txt

#if this is a rebuild then the backup directory exist inside the S3 bucket
DoesMostRecentExists=$(aws s3 ls s3://${s3_backup_bucket}/most-recent/ --recursive --summarize | grep "Total Objects: " | sed 's/[^0-9]*//g')
if [ "$DoesMostRecentExists" -eq "0" ]; then
  echo "File not found, generating default password"
  echo "pritunl default-password > /tmp/default-password.txt" | at now + 10 minutes
  echo "aws s3 cp /tmp/default-password.txt s3://${s3_backup_bucket}" | at now + 11 minutes
  echo "rm /tmp/default-password.txt" | at now + 12 minutes
else
  sudo systemctl stop pritunl
  aws s3 cp s3://${s3_backup_bucket}/most-recent/most-recent.tar.gz /pritunl/dump/
  #aws s3 cp s3://${s3_backup_bucket}/pritunl.uuid /var/lib/pritunl/pritunl.uuid
  cd /pritunl/dump/ && tar xvf most-recent.tar.gz
  mongorestore -d pritunl --nsInclude '*' /pritunl/dump/dump/pritunl/
  sudo systemctl start pritunl
fi

cat <<"EOF" > /usr/sbin/mongobackup.sh
#!/bin/bash -e

set -o errexit  # exit on cmd failure
set -o nounset  # fail on use of unset vars
set -o pipefail # throw latest exit failure code in pipes
set -o xtrace   # print command traces before executing command.

export PATH="/usr/local/bin:$PATH"
export BACKUP_TIME=$(date +'%Y-%m-%d-%H-%M-%S')
export BACKUP_FILENAME="$BACKUP_TIME-pritunl-db-backup.tar.gz"
export BACKUP_DEST="/tmp/$BACKUP_TIME"
mkdir "$BACKUP_DEST" && cd "$BACKUP_DEST"
mongodump -d pritunl
tar zcf "$BACKUP_FILENAME" dump
rm -rf dump
md5sum "$BACKUP_FILENAME" > "$BACKUP_FILENAME.md5"
aws s3 cp "$BACKUP_FILENAME" s3://${s3_backup_bucket}/backups/
aws s3 cp "$BACKUP_FILENAME.md5" s3://${s3_backup_bucket}/backups/
cp "$BACKUP_FILENAME" most-recent.tar.gz
cp "$BACKUP_FILENAME.md5" most-recent.md5
aws s3 cp most-recent.tar.gz s3://${s3_backup_bucket}/most-recent/
aws s3 cp most-recent.md5 s3://${s3_backup_bucket}/most-recent/
cd && rm -rf "$BACKUP_DEST"
EOF
chmod 700 /usr/sbin/mongobackup.sh

cat <<"EOF" > /etc/cron.daily/pritunl-backup
#!/bin/bash -e
export PATH="/usr/local/sbin:/usr/local/bin:$PATH"
mongobackup.sh # && \
   curl -fsS --retry 3 \
   "https://hchk.io/\$( aws --region=${aws_region} --output=text \
                        ssm get-parameters \
                        --names ${healthchecks_io_key} \
                        --with-decryption \
                        --query 'Parameters[*].Value')"
EOF
chmod 755 /etc/cron.daily/pritunl-backup

cat <<"EOF" > /etc/logrotate.d/pritunl
/var/log/mongodb/*.log {
  daily
  missingok
  rotate 60
  compress
  delaycompress
  copytruncate
  notifempty
}
EOF

cat <<"EOF" > /home/ec2-user/.bashrc
# https://twitter.com/leventyalcin/status/852139188317278209
if [ -f /etc/bashrc ]; then
  . /etc/bashrc
fi
EOF

aws s3 cp /var/log/cloud-init-output.log s3://${s3_backup_bucket}/setup_logs/

