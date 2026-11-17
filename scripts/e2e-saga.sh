#!/usr/bin/env bash
# Teste ponta a ponta da Saga contra o ambiente em execução (docker compose ou port-forward).
# Executa 4 cenários: caminho feliz, orçamento recusado, pagamento recusado e falta de peças (estorno).
# Uso: ./scripts/e2e-saga.sh   (lê ADMIN_USERNAME/ADMIN_PASSWORD do .env)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
set -a; source "$ROOT/.env"; set +a
OS=${OS_URL:-http://localhost:8081}
BILLING=${BILLING_URL:-http://localhost:8082}
EXEC=${EXECUTION_URL:-http://localhost:8083}
MOCK=${PAYMENT_MOCK_URL:-http://localhost:8084}

json() { python3 -c "import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1], {}, {'d': d}))" "$1"; }
step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
wait_status() { # osId expected
  for _ in $(seq 1 30); do
    s=$(curl -fsS -H "$AUTH" "$OS/api/service-orders/$1" | json 'd["status"]')
    [ "$s" = "$2" ] && { echo "   OS $1 => $s"; return 0; }
    sleep 1
  done
  echo "   ERRO: OS $1 está $s (esperado $2)"; exit 1
}
saga() { curl -fsS -H "$AUTH" "$OS/api/service-orders/$1/saga" | json 'd["status"] + " / " + d["currentStep"] + " / " + str(d["failureReason"])'; }

step "Login"
TOKEN=$(curl -fsS -X POST "$OS/api/auth/login" -H 'Content-Type: application/json' \
  -d "{\"username\":\"$ADMIN_USERNAME\",\"password\":\"$ADMIN_PASSWORD\"}" | json 'd["token"]')
AUTH="Authorization: Bearer $TOKEN"

step "Cliente e veículo"
CPF=$(python3 -c "
import random
n=[random.randint(0,9) for _ in range(9)]
for _ in range(2):
    s=sum(v*w for v,w in zip(n, range(len(n)+1,1,-1))); d=(s*10)%11; n.append(0 if d==10 else d)
print(''.join(map(str,n)))")
PLATE="T$(python3 -c "import random,string; print(''.join(random.choices(string.ascii_uppercase,k=2))+str(random.randint(0,9))+random.choice(string.ascii_uppercase)+str(random.randint(10,99)))")"
CUSTOMER=$(curl -fsS -X POST "$OS/api/customers" -H "$AUTH" -H 'Content-Type: application/json' \
  -d "{\"document\":\"$CPF\",\"name\":\"Cliente E2E\",\"email\":\"cliente.e2e@example.com\"}" | json 'd["id"]')
VEHICLE=$(curl -fsS -X POST "$OS/api/vehicles" -H "$AUTH" -H 'Content-Type: application/json' \
  -d "{\"plate\":\"$PLATE\",\"make\":\"Fiat\",\"model\":\"Argo\",\"year\":2022,\"customerId\":$CUSTOMER}" | json 'd["id"]')
echo "   cliente=$CUSTOMER veiculo=$VEHICLE ($PLATE)"

open_os() { # parts json
  curl -fsS -X POST "$OS/api/service-orders" -H "$AUTH" -H 'Content-Type: application/json' \
    -d "{\"customerId\":$CUSTOMER,\"vehicleId\":$VEHICLE,\"serviceIds\":[$1],\"parts\":$2,\"observations\":\"E2E\"}" | json 'd["id"]'
}
until_budget() { # osId -> waits AGUARDANDO_APROVACAO and prints token
  sleep 2
  curl -fsS -X POST -H "$AUTH" "$EXEC/api/executions/$1/diagnosis/start" >/dev/null
  curl -fsS -X POST -H "$AUTH" -H 'Content-Type: application/json' "$EXEC/api/executions/$1/diagnosis/complete" -d '{"notes":"Diagnóstico E2E"}' >/dev/null
  wait_status "$1" AGUARDANDO_APROVACAO >&2
}
budget() { curl -fsS -H "$AUTH" "$BILLING/api/budgets/service-order/$1"; }
pay() { # osId outcome(APRO|FUND) -> cliente paga no checkout do simulador do Mercado Pago (webhook -> billing)
  PREF=$(curl -fsS -H "$AUTH" "$BILLING/api/payments/service-order/$1" | json 'd["preferenceId"]')
  curl -fsS -X POST "$MOCK/api/mock/checkout/$PREF/pay" -H 'Content-Type: application/json' -d "{\"outcome\":\"$2\"}" >/dev/null
}

step "CENÁRIO 1 - Caminho feliz"
ID=$(open_os 1 '[{"partId":2,"quantity":4}]'); echo "   OS id=$ID"
wait_status "$ID" RECEBIDA
until_budget "$ID"
TOKEN_B=$(budget "$ID" | json 'd["publicToken"]')
curl -fsS "$BILLING/api/public/budgets/$TOKEN_B/approve" >/dev/null
wait_status "$ID" AGUARDANDO_PAGAMENTO
pay "$ID" APRO
wait_status "$ID" EM_EXECUCAO
curl -fsS -X POST -H "$AUTH" "$EXEC/api/executions/$ID/repair/start" >/dev/null
curl -fsS -X POST -H "$AUTH" "$EXEC/api/executions/$ID/repair/complete" >/dev/null
wait_status "$ID" FINALIZADA
curl -fsS -X PATCH -H "$AUTH" "$OS/api/service-orders/$ID/deliver" >/dev/null
wait_status "$ID" ENTREGUE
echo "   saga: $(saga "$ID")"

step "CENÁRIO 2 - Cliente recusa o orçamento (compensação)"
ID=$(open_os 2 '[]'); echo "   OS id=$ID"
until_budget "$ID"
TOKEN_B=$(budget "$ID" | json 'd["publicToken"]')
curl -fsS "$BILLING/api/public/budgets/$TOKEN_B/reject" >/dev/null
wait_status "$ID" CANCELADA
sleep 1; echo "   saga: $(saga "$ID")"
echo "   execução: $(curl -fsS -H "$AUTH" "$EXEC/api/executions/$ID" | json 'd["status"]')"
echo "   orçamento: $(budget "$ID" | json 'd["status"]')"

step "CENÁRIO 3 - Pagamento recusado no Mercado Pago (compensação)"
ID=$(open_os 1 '[{"partId":1,"quantity":1}]'); echo "   OS id=$ID"
until_budget "$ID"
TOKEN_B=$(budget "$ID" | json 'd["publicToken"]')
curl -fsS "$BILLING/api/public/budgets/$TOKEN_B/approve" >/dev/null
wait_status "$ID" AGUARDANDO_PAGAMENTO
pay "$ID" FUND
wait_status "$ID" CANCELADA
sleep 1; echo "   saga: $(saga "$ID")"

step "CENÁRIO 4 - Falta de peças após pagamento (estorno do pagamento)"
ID=$(open_os 3 '[{"partId":3,"quantity":2}]'); echo "   OS id=$ID"
until_budget "$ID"
TOKEN_B=$(budget "$ID" | json 'd["publicToken"]')
curl -fsS "$BILLING/api/public/budgets/$TOKEN_B/approve" >/dev/null
wait_status "$ID" AGUARDANDO_PAGAMENTO
pay "$ID" APRO
wait_status "$ID" CANCELADA
sleep 2; echo "   saga: $(saga "$ID")"
echo "   pagamento: $(curl -fsS -H "$AUTH" "$BILLING/api/payments/service-order/$ID" | json 'd["status"]')"

printf '\n\033[1;32mTodos os cenários da Saga passaram.\033[0m\n'
