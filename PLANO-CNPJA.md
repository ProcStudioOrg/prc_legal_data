# Plano — Enriquecimento via CNPJA

Status: **plano** (nada implementado, nada gravado no banco).
Base: dry run executado em 2026-07-26 contra o banco local (espelho do remoto, 166.261 societies).
Token: `CNPJA` no `.env`. Header: `Authorization: <token>` (cru, sem `Bearer`).

---

## 1. Objetivo — duas frentes

### Frente A — Onboarding / conferência de clientes
Ao cadastrar (ou revisar) um cliente ProcStudio, puxar dados ricos do CNPJ: endereço
estruturado, CEP, telefone, e-mail, capital social, natureza jurídica, situação cadastral
e o quadro de sócios com papel e data de entrada. Serve para pré-preencher cadastro,
validar que a sociedade está **Ativa** e detectar divergência entre o que o cliente
declara e o que consta na Receita.

### Frente B — Enriquecimento para marketing
Enriquecer a base de advogados/sociedades com contato (e-mail + telefone) e dados
firmográficos, e **descobrir sociedades novas** que ainda não existem na nossa base.
O scrape da OAB é de 2025-07-11 — tudo que nasceu depois é invisível hoje.

> **Pendência declarada:** como tratar sociedade nova cujo(s) advogado(s) não existe(m)
> na nossa base. Ver §7 — há um bloqueio estrutural de schema que precisa ser decidido
> antes de qualquer ingestão.

---

## 2. O que já está validado (evidência do dry run)

Amostra de 17 societies (aleatórias + PELLIZZETTI E WALBER).

- **13/17 casaram** por busca de nome + verificação por nome de sócio.
- Exemplo âncora: `PELLIZZETTI E WALBER ADVOGADOS ASSOCIADOS` → `49780032000146`,
  2/2 sócios conferidos, CEP 85810010, Cascavel, tel 4530355898, `adv5898s@gmail.com`.
- Nosso banco tem `zip_code`, `city` e `phone` **nil** em toda a base. O CNPJA preenche.
- Nas 668 sociedades novas coletadas: **100% com e-mail e telefone**.

### Regras de match aprendidas (não negociar, cada uma custou um caso real)

| Regra | Caso que a originou |
|---|---|
| `count == 1` **não** basta | `LEON ADVOGADOS ASSOCIADOS` (PR) retornou 1 resultado, nome quase igual, **sócios totalmente diferentes** (Esdras/Isabela vs Ovidio/Jaqueline). Firma diferente. Falso positivo puro. |
| Nome exato **não** é obrigatório | `EVANES CESAR FIGUEIREDO` está na Receita como `FIGUEIRE**RO**` — erro de digitação no registro federal. O nome do sócio bateu 100%. |
| **Autoridade = sobreposição de nome de sócio (≥1)**; nome só como pista de busca | consequência das duas linhas acima |
| Contagem de sócios **não** é critério | `OLIVIERI, CARVALHO E LIEVORI` bateu 4/7 — *associados* não entram no QSA porque não têm capital. Diferença **estrutural e permanente**, nunca vai fechar. Não tratar como drift. |
| Filtrar `head`/`status` | `DANIELA HUDSON` retornou matriz `...000129` (Ativa, RJ) e filial `...000200` (**Baixada**, Niterói) |
| **Descartar fallback por tokens** | Quando o nome cheio não acha, a busca degradada por tokens devolveu 6.762 / 1.179 / 168 registros de lixo (`LUIZA BARCELOS CALCADOS S/A`, `SAINT ANNA ADMINISTRADORA DE CONDOMINIOS`) e **zero** acertos em 4 tentativas. Só gera risco de falso positivo. Melhor deixar sem match. |

Os 4 que não casaram têm padrão: sobrenomes genéricos (`BARCELOS & BARCELOS`,
`OLIVEIRA & COSTA`) e variação de pontuação (`SANT'ANNA`). Com a base baixada
localmente (§4) dá pra atacar isso offline sem gastar request.

---

## 3. Referência da API (testado, não documentação de fé)

### Endpoints
- `GET /office/{cnpj}` — ficha completa de um estabelecimento
- `GET /office?<filtros>` — busca/listagem em massa (aceita `limit=1000`)
- `GET /person/{uuid}` — **grafo de participações** de uma pessoa (todas as empresas em que é sócia)

### Filtros que funcionam
| Filtro | Resultado medido |
|---|---|
| `mainActivity.id.in=6911701` | **259.789** sociedades de advocacia no Brasil |
| `head.eq=true` | 251.767 (só matriz) |
| `status.id.in=2` | 200.022 (só Ativa) |
| `founded.gte=YYYY-MM-DD` | fundadas a partir de |
| `statusDate.gte=YYYY-MM-DD` | 4.476 mudaram de situação desde 2026-07-01 |
| `address.state.in=PR` | filtro por UF |
| `names.in=<texto>` | busca por nome, token-AND |
| `limit=1000` | aceito; cada registro vem com **QSA completo** |

### Filtros que NÃO existem (400)
`updated.gte`, `updated.after`, `sort`, `order`, filtro por cidade,
`mainActivity.in`, `company.name.contains`, `name`, `search`, `q`.

> Consequência: **não dá para filtrar por "registro alterado na Receita"**.
> Mudança de quadro societário só se detecta com varredura + diff local (§5).

### Parâmetros extras em `/office/{cnpj}`
- `simples=true` → `simples`/`simei` (optante + desde)
- `geocoding=true` → `latitude`/`longitude`
- `registrations=UF` → inscrições estaduais (vazio para advocacia: ISS, não ICMS)
- `links=RFB_CERTIFICATE` → URL assinada do Cartão CNPJ oficial (expira ~90 dias)

### Campos do payload
`taxId`, `updated` (frescor do dado na Receita), `company.{id,name,equity,nature,size}`,
`members[].{since, role{id,text}, person{id,name,type,taxId,age,country}}`,
`alias`, `founded`, `head`, `status`+`statusDate`, `address` (estruturado + IBGE
`municipality`), `phones[]`, `emails[]` (com `ownership: PERSONAL|CORPORATE`),
`mainActivity`/`sideActivities` (CNAE).

### Duas limitações a saber de antemão
1. **Não existe % de cada sócio.** Só `company.equity` (capital social total) e o `role`
   (`Sócio-Administrador` vs `Sócio com Capital`). A Receita não publica distribuição de
   quotas — isso está no Contrato Social na Junta Comercial. Não é obtível por esta API,
   em nenhum plano.
2. **CPF vem mascarado**: `***802539**` (dígitos 4–9 de 11). Não dá para *adquirir* CPF.
   Dá para **validar** um CPF que já temos (conferir os 6 dígitos do meio).
   Em compensação, `person.id` é UUID estável derivado do CPF → serve como **chave de
   pessoa** para montar o grafo societário **sem guardar dado pessoal**. Preferir sempre
   `person.id` a CPF (LGPD, e a base é de ~166k terceiros).

---

## 4. Estratégia: varredura em massa, não busca por nome

Foi o achado que virou o jogo.

| Abordagem | Requests | Tempo @ 1/min |
|---|---|---|
| Busca por nome, 1 por society | ~166.000 | ~4,5 meses |
| **Varredura CNAE `limit=1000`** | **260** | **~4,4 horas** |

Como cada página do bulk já traz o QSA completo, dá pra **baixar a base inteira e casar
offline**. Isso resolve throughput e qualidade de match ao mesmo tempo: sem rate limit no
matching, dá pra usar fuzzy, normalização de apóstrofo, comparação por sócio, e reprocessar
à vontade — sem gastar um request por tentativa.

### Rate limit (medido)
Token bucket: **~16 de burst, refil ~1/min ≈ 1.440 requests/dia**.
Medição: 2 sucessos em 8 tentativas a cada 15s, os dois separados por 62s. Depois de 60 min
ocioso, 15 requests seguidos passaram sem nenhum 429.

### ⚠️ Risco aberto — custo
**Não sei se `limit=1000` custa 1 crédito ou 1.000.** Todos os endpoints de conta
(`/authentication`, `/me`, `/account`, `/subscription`, `/usage`, `/credits`) dão 404.
O rate limit é claramente por request, mas a cobrança pode ser por registro.

**Conferir no painel do CNPJA antes de rodar a varredura completa.**
Se for por registro, 260 requests = 260k registros, e o caminho sensato passa a ser só o
incremental (`founded.gte` = 668 registros; `statusDate.gte` = 4.476).

---

## 5. Jobs propostos

1. **`Cnpja::SweepNewFirmsJob`** (diário) — `mainActivity.id.in=6911701&founded.gte=<ontem>`.
   ~67 sociedades novas/dia no Brasil → **1 request/dia**. Alimenta a Frente B.
2. **`Cnpja::SweepStatusChangesJob`** (semanal) — `statusDate.gte=<semana passada>`.
   Pega baixa/suspensão de sociedade. Relevante para as duas frentes (cliente com
   sociedade baixada = risco).
3. **`Cnpja::FullSweepJob`** (mensal, gated pelo §4) — varre os 260 pages, grava snapshot,
   faz diff local contra o snapshot anterior → **mudança de quadro societário**.
   É o único jeito, já que `updated.gte` não existe.
4. **`Cnpja::EnrichSocietyJob`** (sob demanda, Frente A) — `/office/{cnpj}` com
   `simples=true&geocoding=true&links=RFB_CERTIFICATE` para um cliente específico no onboarding.

Todos com backoff em 429 (30/60/90/120/150s) — já validado no dry run.

---

## 6. Migração proposta

```ruby
# societies
add_column :societies, :cnpj, :string                    # + index unique
add_column :societies, :cnpja_data, :jsonb, default: {}  # payload cru
add_column :societies, :cnpja_updated_at, :datetime      # campo `updated` da Receita
add_column :societies, :cnpja_synced_at,  :datetime      # quando NÓS buscamos
add_column :societies, :cnpja_match_confidence, :string  # verified | ambiguous | unmatched

# lawyers
add_column :lawyers, :cnpja_person_id, :string           # UUID estável, chave do grafo
```

Regra: só grava `cnpj` com `cnpja_match_confidence = verified` (≥1 sócio conferido).
`ambiguous` fica em quarentena para revisão manual — **nunca** promover automaticamente.

Lembrar do `config/changelog.yml` se algum campo novo vazar para a API pública (regra do CLAUDE.md).

---

## 7. ⚠️ Bloqueio estrutural da Frente B (decidir antes de ingerir)

Sociedade nova vinda do CNPJA **não cabe na tabela `societies` hoje**:

- `Society` valida `inscricao` com `presence: true` **e** `uniqueness` — é o número OAB.
  Firma descoberta via CNAE **não tem** inscrição OAB (só CNPJ).
- Valida também `state` e `number_of_partners > 0`.
- `LawyerSociety` valida capacidade contra `number_of_partners` e, pior,
  `destroy_orphan_society` **apaga a society automaticamente** quando o último vínculo
  some — uma society sem advogado na nossa base seria destruída sozinha.

Ou seja: a base atual pressupõe "society sempre tem advogado OAB nosso". Prospect não tem.

**Opções (escolher depois):**
- **(a) Tabela separada `prospect_societies`** — não contamina o modelo OAB, sem risco de
  quebrar as validações e o auto-destroy. É a mais segura e a minha recomendação.
- **(b) `inscricao` nullable + flag `source: oab|cnpja`** — reaproveita o modelo, mas mexe
  em validação usada pela API pública e pelo fluxo DJEN. Risco maior.
- **(c) Só CSV/export para marketing**, sem persistir no banco. Mais barato, não acumula.

---

## 8. Roadmap sugerido

- **Fase 0** — conferir cobrança no painel CNPJA (§4). Destrava ou reduz todo o resto.
- **Fase 1 (Frente A)** — migração §6 + `EnrichSocietyJob` sob demanda. Baixo risco,
  valor imediato no onboarding, volume pequeno de request.
- **Fase 2** — `SweepNewFirmsJob` + `SweepStatusChangesJob` (1 request/dia + 1/semana).
  Barato mesmo se a cobrança for por registro.
- **Fase 3** — decidir §7, então ingerir prospects para marketing.
- **Fase 4** — `FullSweepJob` + diff de quadro societário (só depois da Fase 0).

---

## 9. Artefatos do dry run

Ficaram no scratchpad da sessão (temporário — copiar se quiser guardar):
`/private/tmp/claude-501/-Users-brpl-code-ProcStudio-prc-legal-data/9e887b6e-80b6-45b1-be78-aac322de20bb/scratchpad/`

- `novas_sociedades.json` / `.csv` — 668 sociedades fundadas de 2026-07-16 a 26,
  com sócios, papel, `desde`, CPF mascarado e `person_id`. 100% com e-mail e telefone.
  Top UFs: SP 197, MG 90, PR 71, RJ 54, RS 50, BA 47, SC 30, GO 25.
- `dry_run_report.json` / `retry_report.json` — evidência bruta dos 17 casos de match.
- `cnpja_dry_run.rb` / `cnpja_retry.rb` — scripts do teste (read-only).
