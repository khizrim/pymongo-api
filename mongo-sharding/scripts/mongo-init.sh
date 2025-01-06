#!/bin/bash

# Constants
LOGFILE="db-setup.log"

# Start logging
echo "Script started at $(date)" > "$LOGFILE"

# Logging function
log() {
  local message="$1"
  echo "$(date): $message" | tee -a "$LOGFILE"
}

# Initialize the database setup
log "Initializing the database setup"

# Setup configuration server
log "Setting up the configuration server"
docker compose exec -T config_srv mongosh --port 27017 --quiet <<EOF
rs.initiate({
  _id: 'config_server',
  configsvr: true,
  members: [{ _id: 0, host: 'config_srv:27017' }]
});
EOF
sleep 3

# Setup shard_1
log "Setting up shard_1"
docker compose exec -T shard_1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: 'shard_1',
  members: [{ _id: 0, host: 'shard_1:27018' }]
});
EOF
sleep 3

# Setup shard_2
log "Setting up shard_2"
docker compose exec -T shard_2 mongosh --port 27019 --quiet <<EOF
rs.initiate({
  _id: 'shard_2',
  members: [{ _id: 0, host: 'shard_2:27019' }]
});
EOF
sleep 3

# Configure shards in the router
log "Configuring shards in the router"
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
sh.addShard("shard_1/shard_1:27018");
sh.addShard("shard_2/shard_2:27019");
EOF
sleep 3

# Setup database and sharding
log "Setting up the database and sharding"
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
use somedb;

sh.enableSharding("somedb");
db.createCollection("helloDoc");
db.helloDoc.createIndex({ "name": "hashed" });
sh.shardCollection("somedb.helloDoc", { "name": "hashed" });

for (let i = 0; i < 1000; i++) {
  db.helloDoc.insertOne({ age: i, name: "ly" + i });
}

db.helloDoc.countDocuments();
EOF
sleep 5

# Count documents in shard_1
log "Counting documents in shard_1"
docker compose exec -T shard_1 mongosh --port 27018 --quiet <<EOF
use somedb;
db.helloDoc.countDocuments();
EOF

# Count documents in shard_2
log "Counting documents in shard_2"
docker compose exec -T shard_2 mongosh --port 27019 --quiet <<EOF
use somedb;
db.helloDoc.countDocuments();
EOF

# Completion log
log "Script completed successfully"
