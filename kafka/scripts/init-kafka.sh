#!/bin/bash

set -ueo pipefail
umask 0022

FILES=/tmp/files

#############################
# 1. KAFKA VERSION
#############################

KAFKA_VERSION=4.3.0

KAFKA_MIRROR=https://archive.apache.org/dist/kafka

# Kafka install paths
KAFKA_HOME=/opt/kafka
KAFKA_LOG_DIR=/var/log/kafka

KAFKA_USER=kafka
KAFKA_GROUP=kafka

#############################
# 2. INSTALL JAVA (AMAZON LINUX)
#############################

if command -v dnf >/dev/null 2>&1; then
    dnf update -y
    dnf install -y java-17-amazon-corretto
else
    yum update -y
    yum install -y java-17-amazon-corretto
fi

alternatives --set java /usr/lib/jvm/java-17-amazon-corretto/bin/java || true

#############################
# 3. CREATE KAFKA USER
#############################

groupadd -r ${KAFKA_GROUP} || true

id -u ${KAFKA_USER} >/dev/null 2>&1 || \
useradd -r -m -g ${KAFKA_GROUP} ${KAFKA_USER}

#############################
# 4. DOWNLOAD KAFKA
#############################


KAFKA_TAR="kafka_2.13-${KAFKA_VERSION}.tgz"

curl --fail -L -o /tmp/${KAFKA_TAR} \
${KAFKA_MIRROR}/${KAFKA_VERSION}/${KAFKA_TAR}

#############################
# 5. INSTALL KAFKA
#############################

tar xvf /tmp/${KAFKA_TAR} -C /tmp

mkdir -p ${KAFKA_HOME}

mv /tmp/kafka_2.13-${KAFKA_VERSION}/* ${KAFKA_HOME}/

chown -R ${KAFKA_USER}:${KAFKA_GROUP} ${KAFKA_HOME}

#############################
# 6. LOG DIRECTORY
#############################

mkdir -p ${KAFKA_LOG_DIR}
chown -R ${KAFKA_USER}:${KAFKA_GROUP} ${KAFKA_LOG_DIR}

#############################
# 7. CONFIG FILES (STATIC)
#############################

install --owner ${KAFKA_USER} --group ${KAFKA_GROUP} --mode 0644 \
${FILES}/kafka/server.properties \
${KAFKA_HOME}/config/server.properties

install --owner ${KAFKA_USER} --group ${KAFKA_GROUP} --mode 0644 \
${FILES}/kafka/log4j2.yaml \
${KAFKA_HOME}/config/log4j2.yaml

#############################
# 8. SYSTEMD SERVICES
#############################

install --owner root --group root --mode 0444 \
${FILES}/kafka/kafka.service \
/etc/systemd/system/kafka.service

install --owner root --group root --mode 0444 \
${FILES}/kafka/kafka-pre.service \
/etc/systemd/system/kafka-pre.service

install --owner root --group root --mode 0755 \
${FILES}/kafka/kafka-pre.sh \
/usr/local/bin/kafka-pre.sh


#############################
# 9. EBS + STORAGE
#############################

install --owner root --group root --mode 0755 \
/tmp/files/attach-ebs.sh /usr/local/bin

install --owner root --group root --mode 0755 \
/tmp/files/settle-ebs.sh /usr/local/bin

install --owner root --group root --mode 0755 \
/tmp/files/mount-volumes.sh /usr/local/bin

install --owner root --group root --mode 0644 \
/tmp/files/attach-ebs.service /etc/systemd/system

install --owner root --group root --mode 0644 \
/tmp/files/settle-ebs.service /etc/systemd/system

install --owner root --group root --mode 0644 \
/tmp/files/mount-volumes.service /etc/systemd/system

#############################
# 13. CLEANUP
#############################

rm -rf /tmp/files
rm -rf /tmp/kafka_*.tgz
rm -rf /tmp/kafka_*

yum clean all || true
dnf clean all || true

find /var/log -type f -delete

#############################
# 14. ENABLE SERVICES
#############################

systemctl daemon-reload

systemctl enable attach-ebs
systemctl enable settle-ebs
systemctl enable mount-volumes

systemctl enable kafka-pre
systemctl enable kafka

#############################
# 15. FINAL HARDENING
#############################

umask 0077