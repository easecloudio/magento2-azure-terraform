#!/bin/bash
set -euo pipefail

NODE_INDEX="${node_index}"
BRAND="${brand}"
PROJECT="${project}"
VERSION="${opensearch_version}"

hostnamectl set-hostname "opensearch-$${NODE_INDEX}"
echo "127.0.0.1 opensearch-$${NODE_INDEX} opensearch-$${NODE_INDEX}.$${BRAND}.internal" >> /etc/hosts

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq openjdk-17-jre-headless curl

curl -fsSL "https://artifacts.opensearch.org/releases/bundle/opensearch/2.x/opensearch-$${VERSION}-linux-arm64.tar.gz" \
  -o /tmp/opensearch.tar.gz
mkdir -p /opt/opensearch
tar -xzf /tmp/opensearch.tar.gz -C /opt/opensearch --strip-components=1
/opt/opensearch/opensearch-tar-install.sh

cat > /opt/opensearch/config/opensearch.yml <<EOF
cluster.name: ${project}-cluster
node.name: opensearch-$${NODE_INDEX}
network.host: 0.0.0.0
http.port: 9200
transport.port: 9300

discovery.seed_hosts:
  - opensearch-0.${brand}.internal:9300
  - opensearch-1.${brand}.internal:9300
  - opensearch-2.${brand}.internal:9300

cluster.initial_cluster_manager_nodes:
  - opensearch-0
  - opensearch-1
  - opensearch-2

plugins.security.disabled: true
EOF

echo "OpenSearch node $${NODE_INDEX} initialized: ${project}" >> /var/log/cloud-init-custom.log
