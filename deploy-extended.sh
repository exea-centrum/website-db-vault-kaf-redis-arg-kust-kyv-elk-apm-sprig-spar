#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="davtroelkpyjs"

echo "🚀 Deploying Extended Stack: Spring Boot + Spark + MongoDB + ELK"

# 1. Deploy new databases
echo "📦 Deploying MongoDB..."
kubectl apply -f "${PROJECT_DIR}/manifests/base/mongodb.yaml" -n "${NAMESPACE}"

echo "📦 Deploying ELK Stack..."
kubectl apply -f "${PROJECT_DIR}/manifests/base/elasticsearch.yaml" -n "${NAMESPACE}"
kubectl apply -f "${PROJECT_DIR}/manifests/base/logstash.yaml" -n "${NAMESPACE}"
kubectl apply -f "${PROJECT_DIR}/manifests/base/kibana.yaml" -n "${NAMESPACE}"

# 2. Wait for databases
echo "⏳ Waiting for MongoDB..."
kubectl wait --for=condition=ready pod -l app=website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar,component=mongodb -n "${NAMESPACE}" --timeout=300s

echo "⏳ Waiting for Elasticsearch..."
kubectl wait --for=condition=ready pod -l app=website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar,component=elasticsearch -n "${NAMESPACE}" --timeout=300s

# 3. Initialize MongoDB
echo "🔧 Initializing MongoDB..."
kubectl wait --for=condition=complete job/mongodb-init -n "${NAMESPACE}" --timeout=300s

# 4. Deploy Spark
echo "⚡ Deploying Apache Spark..."
kubectl apply -f "${PROJECT_DIR}/manifests/base/spark-master.yaml" -n "${NAMESPACE}"
kubectl apply -f "${PROJECT_DIR}/manifests/base/spark-worker.yaml" -n "${NAMESPACE}"

# 5. Deploy Spring Boot
echo "🌱 Deploying Spring Boot..."
kubectl apply -f "${PROJECT_DIR}/manifests/base/spring-app-deployment.yaml" -n "${NAMESPACE}"

# 6. Wait for services
echo "⏳ Waiting for Spark Master..."
kubectl wait --for=condition=ready pod -l app=website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar,component=spark-master -n "${NAMESPACE}" --timeout=300s

echo "⏳ Waiting for Spring Boot..."
kubectl wait --for=condition=ready pod -l app=website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar,component=spring-app -n "${NAMESPACE}" --timeout=300s

# 7. Update FastAPI with new routes
echo "🔄 Updating FastAPI deployment..."
kubectl rollout restart deployment/fastapi-web-app -n "${NAMESPACE}"
kubectl wait --for=condition=ready pod -l app=website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar,component=fastapi -n "${NAMESPACE}" --timeout=300s

# 8. Update Ingress
echo "🌐 Updating Ingress..."
kubectl apply -f "${PROJECT_DIR}/manifests/base/ingress-extended.yaml" -n "${NAMESPACE}"

# 9. Update monitoring
echo "📊 Updating monitoring..."
kubectl apply -f "${PROJECT_DIR}/manifests/base/monitoring-extended.yaml" -n "${NAMESPACE}"

echo ""
echo "✅ Extended stack deployment complete!"
echo ""
echo "🌐 Access points:"
echo "   Main App:        http://app.website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar.local"
echo "   New Survey:      http://app.website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar.local/new-survey"
echo "   Spring Boot API: http://spring.website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar.local"
echo "   Spark UI:        http://spark.website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar.local"
echo "   Kibana:          http://kibana.website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar.local"
echo "   Grafana:         http://grafana.website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar.local"
echo "   PgAdmin:         http://pgadmin.website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar.local"
echo "   Kafka UI:        http://kafka-ui.website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar.local"
echo ""
echo "🔍 Check pods:"
echo "   kubectl get pods -n ${NAMESPACE}"
echo ""
echo "📈 Check services:"
echo "   kubectl get svc -n ${NAMESPACE}"
