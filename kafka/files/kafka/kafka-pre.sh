#!/bin/bash

set -eo pipefail

TAGS_FILE=/etc/systemd/system.conf.d/aws_environment.conf
TAG_PREFIX="AWS_TAG_KAFKA_"
KAFKA_HOME=/opt/kafka
KAFKA_CFG=${KAFKA_HOME}/config/server.properties

get_tag_value() {
  grep ${1} ${TAGS_FILE} | head -1 \
      | awk -F'=' '{print $NF}' \
      | sed 's/"$//'
}

# -----------------------------
# AWS CLI override for testing
# -----------------------------
AWS_CLI="aws"
if [ "$AWS_TAG_TESTING_NODE" != "" ]; then
  echo "Testing node, using custom aws cli command"
  AWS_CLI=/usr/local/sbin/aws-test-cli
fi

# -----------------------------
# NODE ID (KRaft replaces broker.id)
# -----------------------------
THIS_NODE=$(get_tag_value "TAG_NAME")
NODE_ID=$(echo "${THIS_NODE}" | awk -F'-' '{print $NF}')

sed -i "s/^node.id=.*$/node.id=${NODE_ID}/" ${KAFKA_CFG}

# -----------------------------
# CONTROLLER QUORUM CONFIG (CRITICAL KRaft change)
# -----------------------------
# Example: bootstrap controller nodes manually or via tags

CONTROLLER_NODES=$(get_tag_value "CONTROLLER_QUORUM")

sed -i "s|^controller.quorum.bootstrap.servers=.*$|controller.quorum.bootstrap.servers=${CONTROLLER_NODES}|" ${KAFKA_CFG}

# -----------------------------
# LISTENERSfor variable in $(env | grep "$TAG_PREFIX"); do
    NAME=$(echo $variable | cut -d'=' -f1)
    VALUE=$(echo $variable | cut -d'=' -f2-)

    KEY=$(echo $NAME | awk -F"$TAG_PREFIX" '{print $2}' \
        | tr '[:upper:]' '[:lower:]' \
        | tr '_' '.')

    echo "Setting $KEY=$VALUE"

    sed -i "/^$KEY=/d" $KAFKA_CFG
    echo "$KEY=$VALUE" >> $KAFKA_CFG
done
# -----------------------------
sed -i "s|^listeners=.*$|listeners=PLAINTEXT://${THIS_NODE}:9092,CONTROLLER://${THIS_NODE}:9093|" ${KAFKA_CFG}

sed -i "s|^advertised.listeners=.*$|advertised.listeners=PLAINTEXT://${THIS_NODE}:9092|" ${KAFKA_CFG}

# -----------------------------
# LOG DIRS (EBS support)
# -----------------------------
ENVIRONMENT_FILE="/etc/environment"
EXPECTED_EBS_VOLUME_COUNT=$(cat $ENVIRONMENT_FILE | awk '$0 ~ /ebs_count/ {print}' | awk -F'=' '{print $2}')

if [ "$AWS_TAG_TESTING_NODE" != "" ]; then
  EXPECTED_EBS_VOLUME_COUNT=1
fi

DISK_LIST=$(for i in $(seq 1 ${EXPECTED_EBS_VOLUME_COUNT}); do echo -n "/opt/kafka-logs/$i,"; done | sed 's/.$//')

sed -i "s|^log.dirs=.*$|log.dirs=${DISK_LIST}|" ${KAFKA_CFG}

# -----------------------------
# RACK AWARENESS
# -----------------------------
RACK_ID=$(get_tag_value "AVAILABILITY_ZONE")

sed -i "s/^broker.rack=.*$/broker.rack=${RACK_ID}/" ${KAFKA_CFG}

# -----------------------------
# DYNAMIC TAG-BASED CONFIG
# -----------------------------
echo "Checking Kafka tag-based configs"

for variable in $(env | grep "$TAG_PREFIX"); do
    NAME=$(echo $variable | cut -d'=' -f1)
    VALUE=$(echo $variable | cut -d'=' -f2-)

    KEY=$(echo $NAME | awk -F"$TAG_PREFIX" '{print $2}' \
        | tr '[:upper:]' '[:lower:]' \
        | tr '_' '.')

    echo "Setting $KEY=$VALUE"

    sed -i "/^$KEY=/d" $KAFKA_CFG
    echo "$KEY=$VALUE" >> $KAFKA_CFG
done

# -----------------------------
# LOG DIRECTORY PERMISSIONS
# -----------------------------
mkdir -p /var/log/kafka
chown kafka:kafka /var/log/kafka
chmod 755 /var/log/kafka

echo "Ensuring Kafka log volume ownership"
chown -R kafka:kafka /opt/kafka-logs