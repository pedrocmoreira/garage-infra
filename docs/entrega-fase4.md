# Tech Challenge — Fase 4 · Garage System em Microsserviços

> Conteúdo do PDF de entrega no portal. Substitua os campos `<<...>>` e exporte para PDF.

## 1. Participantes
| Nome | RM | Discord/Contato |
|---|---|---|
| <<Nome completo>> | <<RM>> | <<contato>> |

## 2. Repositórios
| Repositório | Link |
|---|---|
| OS Service (orquestrador) | https://github.com/pedrocmoreira/os-service |
| Billing Service | https://github.com/pedrocmoreira/billing-service |
| Execution Service | https://github.com/pedrocmoreira/execution-service |
| Simulador do Mercado Pago | https://github.com/pedrocmoreira/payment-mock-service |
| Infraestrutura / docs / Postman | https://github.com/pedrocmoreira/garage-infra |

## 3. Vídeo de demonstração
<<link do YouTube/Vimeo (não listado), até 15 min>>

## 4. Diagrama geral da arquitetura
(Exporte o diagrama Mermaid da seção “Arquitetura” do `garage-infra/README.md`, por exemplo em <https://mermaid.live>, e cole aqui.)

- 3 microsserviços independentes, cada um com repositório, pipeline, Dockerfile, manifestos Kubernetes e banco próprios.
- **OS Service** → PostgreSQL · **Billing Service** → PostgreSQL · **Execution Service** → MongoDB.
- Comunicação assíncrona via **RabbitMQ** (exchange topic `garage.saga`, comandos `command.*`, eventos `event.*`, DLQ).
- REST síncrono para usuários, provedor de pagamento e webhook. Nenhum serviço acessa o banco de outro.
- Pagamentos: **`payment-mock-service`**, um repositório separado que imita a API do Mercado Pago (preferências, consulta,
  estorno e webhook assinado com `x-signature`). O Billing usa a mesma integração HTTP do provedor real.
- Observabilidade: OpenTelemetry → Jaeger (traces distribuídos), Prometheus → Grafana (métricas), logs JSON com traceId.

## 5. Estratégia do Saga Pattern: **Orquestrada**
O **OS Service** é o orquestrador. Ele persiste o estado da saga (`saga_instances`), envia comandos aos participantes e reage
aos eventos de resposta:

`Abrir OS → diagnóstico (Execution) → orçamento + e-mail (Billing) → aprovação do cliente → pagamento Mercado Pago → reserva de peças → execução → finalizada`

**Compensações:** orçamento recusado ou pagamento recusado → cancela a execução e o orçamento. Falta de peças após o pagamento
→ cancela a execução e **estorna o pagamento** no Mercado Pago. A OS vai para `CANCELADA` e a saga para `COMPENSATED`.

**Justificativa:** o ciclo de vida da OS já pertencia ao OS Service. As compensações dependem do histórico da saga (estornar ou
só cancelar), que fica centralizado e consultável em `GET /service-orders/{id}/saga`. Os participantes continuam desacoplados:
só executam comandos e publicam fatos. Mitigações do ponto central: estado persistido, idempotência, publicação pós-commit, retry e DLQ.

## 6. Justificativa da divisão dos microsserviços
| Serviço | Contexto delimitado | Motivo da separação |
|---|---|---|
| OS Service | Atendimento: OS, clientes, veículos, catálogo | Dono do ciclo de vida e do histórico da OS; ponto de entrada do atendimento |
| Billing Service | Cobrança: orçamentos e pagamentos | Regras financeiras e integração externa (Mercado Pago) isoladas; escala e falha independentes |
| Execution Service | Produção: fila, diagnóstico, reparo, estoque | Operação da oficina com ritmo próprio; o estoque é consumido na execução |
| Payment Mock Service | Provedor externo simulado | Representa o Mercado Pago fora do domínio da oficina; permite testar aprovação, recusa e estorno sem credenciais reais |

## 7. Tecnologias
Java 21 · Spring Boot 4 (Web MVC, Data JPA, Data MongoDB, AMQP, Security, Actuator) · PostgreSQL 16 · MongoDB 7 · RabbitMQ 3.13 ·
Mercado Pago Checkout Pro (simulado pelo payment-mock-service) · JWT · Flyway · OpenTelemetry · Jaeger · Prometheus · Grafana · Docker · Kubernetes (kind / qualquer
cluster) · GitHub Actions · GHCR · JaCoCo (gate 80%) · SonarCloud · JUnit 5 · Mockito · Cucumber (BDD) · Postman/Newman.

## 8. Evidências de qualidade
| Serviço | Testes | Cobertura de linhas | Branches |
|---|---|---|---|
| os-service (inclui 5 cenários BDD) | 88 | 99,4% | 89,4% |
| billing-service | 32 | 98,3% | 83,1% |
| execution-service | 21 | 97,2% | 87,1% |
| payment-mock-service | 13 | 98,1% | 89,2% |

SonarCloud (Quality Gate e cobertura por serviço): <https://sonarcloud.io/organizations/pedrocmoreira/projects>

<<Insira prints do JaCoCo, do SonarCloud (Quality Gate) e dos pipelines verdes.>>
