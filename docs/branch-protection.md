# Proteção da branch `main` (obrigatório na Fase 4)

Aplique em **cada um dos 5 repositórios** (`os-service`, `billing-service`, `execution-service`, `payment-mock-service`, `garage-infra`).

## Pelo GitHub (Settings → Rules → Rulesets → New branch ruleset)
- Target: `main` (Default branch)
- ✅ Restrict deletions · ✅ Block force pushes
- ✅ **Require a pull request before merging** (1 aprovação, descartar aprovações em novos commits)
- ✅ **Require status checks to pass**, com os checks:
  - `Build e testes (cobertura mínima 80%)`
  - `Qualidade (SonarCloud)`

## Pelo terminal (GitHub CLI)
```bash
OWNER=pedrocmoreira
for REPO in os-service billing-service execution-service payment-mock-service; do
gh api -X PUT "repos/$OWNER/$REPO/branches/main/protection" \
  -H "Accept: application/vnd.github+json" \
  -F "required_status_checks[strict]=true" \
  -F "required_status_checks[contexts][]=Build e testes (cobertura mínima 80%)" \
  -F "required_status_checks[contexts][]=Qualidade (SonarCloud)" \
  -F "enforce_admins=true" \
  -F "required_pull_request_reviews[required_approving_review_count]=1" \
  -F "required_pull_request_reviews[dismiss_stale_reviews]=true" \
  -F "restrictions=" \
  -F "allow_force_pushes=false" -F "allow_deletions=false"
done
```

## Secrets e variables de cada repositório de serviço
| Nome | Tipo | Uso |
|---|---|---|
| `SONAR_TOKEN` | Secret | Token do SonarCloud (My Account → Security). Organização (`pedrocmoreira`) e chave do projeto (`pedrocmoreira_<serviço>`) já estão no `pom.xml` |
| `KUBE_CONFIG` | Secret (opcional) | kubeconfig **em base64** de um cluster real. Sem ele, o deploy roda em um cluster *kind* efêmero no runner |

O job de deploy usa o *environment* `production`. Crie-o em Settings → Environments; se quiser, adicione aprovação manual.
O repositório `garage-infra` precisa estar no mesmo owner (o deploy faz checkout dele para aplicar a infraestrutura).
