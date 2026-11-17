# Roteiro do vídeo (até 15 minutos)

Preparação: `docker compose up -d --build` já executado, abas abertas (Swagger/Postman, RabbitMQ, MailHog, Jaeger, Grafana, GitHub Actions).

| Tempo | Bloco | O que mostrar |
|---|---|---|
| 0:00–1:30 | Arquitetura | Diagrama do README: 3 serviços, bancos próprios (2× PostgreSQL + MongoDB), RabbitMQ, Mercado Pago, observabilidade. Por que orquestração. |
| 1:30–6:00 | **Fluxo completo de uma OS** | Postman pasta “2. Fluxo feliz”: login → abrir OS → fila do Execution → diagnóstico → orçamento no Billing → **e-mail no MailHog** → aprovar pelo link → página com “Pagar com Mercado Pago” → checkout do **simulador** (`payment-mock-service`), escolhendo APRO → webhook assinado chega ao Billing (`/api/mock/payments` mostra a entrega) → reparo → FINALIZADA → entrega. Mostrar `GET /history` e `GET /saga` (COMPLETED). |
| 6:00–9:30 | **Saga e tratamento de falhas** | Pasta “3. Falta de peças”: pagamento aprovado mas pastilha sem estoque → OS CANCELADA, saga COMPENSATING → COMPENSATED, pagamento REFUNDED. Pasta “4. Orçamento recusado” (execução CANCELLED). No RabbitMQ: exchange `garage.saga`, filas e DLQs. Opcional: `./scripts/e2e-saga.sh` rodando os 4 cenários. |
| 9:30–12:30 | **Deploy automatizado com testes** | Abrir um PR pequeno no `execution-service` → checks “Build e testes” e “SonarCloud” obrigatórios → merge → Actions: imagem no GHCR → deploy Kubernetes → `rollout status` + smoke test verde. Mostrar artefato `jacoco-report` e o Quality Gate. |
| 12:30–14:30 | **Monitoramento e rastreamento** | Jaeger: um trace atravessando os serviços (inclusive o simulador de pagamento) (HTTP → RabbitMQ). Logs JSON com o mesmo `traceId`. Grafana: sagas iniciadas/concluídas/compensadas, pagamentos, reserva de peças, latência p95. |
| 14:30–15:00 | Encerramento | Recapitular requisitos atendidos. |

Dica: o simulador segue o contrato do Mercado Pago. Para mostrar o provedor real, configure `MP_API_BASE_URL=https://api.mercadopago.com`,
o Access Token de teste e `MP_NOTIFICATION_URL` com uma URL pública (ngrok).
