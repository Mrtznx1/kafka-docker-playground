#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

NGROK_AUTH_TOKEN=${NGROK_AUTH_TOKEN:-$1}

display_ngrok_warning

bootstrap_ccloud_environment



set +e
playground topic delete --topic MyKafkaTopicName
set -e

docker compose build
docker compose down -v --remove-orphans
docker compose up -d

sleep 5

log "Getting ngrok hostname and port"
NGROK_URL=$(curl --silent http://127.0.0.1:4040/api/tunnels | jq -r '.tunnels[0].public_url')
NGROK_HOSTNAME=$(echo $NGROK_URL | cut -d "/" -f3 | cut -d ":" -f 1)
NGROK_PORT=$(echo $NGROK_URL | cut -d "/" -f3 | cut -d ":" -f 2)

connector_name="IbmMQSource_$USER"
set +e
log "Deleting fully managed connector $connector_name, it might fail..."
playground connector delete --connector $connector_name
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
     "connector.class": "IbmMQSource",
     "name": "$connector_name",
     "kafka.auth.mode": "KAFKA_API_KEY",
     "kafka.api.key": "$CLOUD_KEY",
     "kafka.api.secret": "$CLOUD_SECRET",
     "output.data.format": "AVRO",
     "kafka.topic": "MyKafkaTopicName",
     "mq.hostname": "$NGROK_HOSTNAME",
     "mq.port": "$NGROK_PORT",
     "mq.transport.type": "client",
     "mq.queue.manager": "QM1",
     "mq.channel": "DEV.APP.SVRCONN",
     "mq.username": "app",
     "mq.password": "passw0rd",
     "jms.destination.name": "DEV.QUEUE.1",
     "jms.destination.type": "queue",
     "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 300

sleep 5

log "Sending messages to DEV.QUEUE.1 JMS queue:"
docker exec -i ibmmq /opt/mqm/samp/bin/amqsput DEV.QUEUE.1 << EOF
Message 1
Message 2

EOF

sleep 5

log "Verify we have received the data in MyKafkaTopicName topic"
playground topic consume --topic MyKafkaTopicName --min-expected-messages 2 --timeout 60

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name