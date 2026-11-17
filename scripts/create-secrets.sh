#!/usr/bin/env bash
# Cria/atualiza o Secret "garage-secrets" no namespace garage a partir do arquivo .env
# Uso: ./scripts/create-secrets.sh [caminho/.env]
set -euo pipefail
ENV_FILE="${1:-$(dirname "$0")/../.env}"
[ -f "$ENV_FILE" ] || { echo "Arquivo $ENV_FILE não encontrado (copie .env.example para .env)"; exit 1; }
set -a; source "$ENV_FILE"; set +a

MONGO_URI="mongodb://${MONGO_ROOT_USER}:${MONGO_ROOT_PASSWORD}@execution-db:27017/${MONGO_DB_NAME}?authSource=admin"

kubectl get namespace garage >/dev/null 2>&1 || kubectl create namespace garage
kubectl -n garage create secret generic garage-secrets \
  --from-env-file="$ENV_FILE" \
  --from-literal=EXECUTION_MONGO_URI="$MONGO_URI" \
  --dry-run=client -o yaml | kubectl apply -f -
echo "Secret garage-secrets aplicado."
