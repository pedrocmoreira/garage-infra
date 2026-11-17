#!/usr/bin/env bash
# Sobe todo o ambiente em um cluster Kubernetes local (kind).
# Pré-requisitos: docker, kind, kubectl. Repositórios dos serviços como pastas irmãs.
# Uso: ./scripts/deploy-kind.sh            (cria cluster, builda imagens e aplica tudo)
#      SKIP_BUILD=1 ./scripts/deploy-kind.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE="$(cd "$ROOT/.." && pwd)"
SERVICES=(payment-mock-service os-service billing-service execution-service)

if ! kind get clusters | grep -qx garage; then
  kind create cluster --config "$ROOT/scripts/kind-config.yaml"
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.3/deploy/static/provider/kind/deploy.yaml
  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.7.2/components.yaml
  kubectl -n kube-system patch deployment metrics-server --type=json \
    -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
  kubectl wait --namespace ingress-nginx --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller --timeout=240s
fi
kubectl config use-context kind-garage

kubectl apply -f "$ROOT/k8s/infra/00-namespace.yaml"
"$ROOT/scripts/create-secrets.sh" "$ROOT/.env"
kubectl apply -f "$ROOT/k8s/infra"
kubectl -n garage create configmap grafana-dashboards \
  --from-file="$ROOT/observability/grafana/dashboards" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "$ROOT/k8s/observability"

for svc in "${SERVICES[@]}"; do
  if [ -z "${SKIP_BUILD:-}" ]; then
    docker build -t "garage/$svc:local" "$WORKSPACE/$svc"
  fi
  kind load docker-image "garage/$svc:local" --name garage
  kubectl apply -f "$WORKSPACE/$svc/k8s"
  kubectl -n garage set image "deployment/$svc" "$svc=garage/$svc:local"
done

kubectl -n garage rollout status statefulset/os-db --timeout=180s
kubectl -n garage rollout status statefulset/billing-db --timeout=180s
kubectl -n garage rollout status statefulset/execution-db --timeout=180s
kubectl -n garage rollout status statefulset/rabbitmq --timeout=240s
for svc in "${SERVICES[@]}"; do
  kubectl -n garage rollout status "deployment/$svc" --timeout=300s
done

cat <<MSG

Ambiente no ar (Ingress em http://garage.localhost):
  OS Service        http://garage.localhost/os/swagger-ui.html
  Billing Service   http://garage.localhost/billing/swagger-ui.html
  Execution Service http://garage.localhost/execution/swagger-ui.html
  Mercado Pago (simulador) http://garage.localhost/mercadopago/swagger-ui.html
Observabilidade (port-forward):
  kubectl -n garage port-forward svc/grafana 3000:3000
  kubectl -n garage port-forward svc/jaeger 16686:16686
  kubectl -n garage port-forward svc/rabbitmq 15672:15672
MSG
