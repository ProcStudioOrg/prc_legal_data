# Receita Federal (OpenCNPJ) — enriquecimento societário e prospecção

Data: 2026-10-06
Status: spec aprovada em conversa, aguardando revisão do documento
Repos afetados: `prc_legal_data` (fonte), `ProcStudio-Docker` (onboarding), `fullFuckerDashboard/ai-dashboard` (prospecção)
Substitui: `PLANO-CNPJA.md` (API paga, 1 request/min). Este desenho usa o dump público do OpenCNPJ, offline e gratuito. As regras de match do plano antigo continuam valendo e estão repetidas aqui.

## 1. Objetivo

1. **Onboarding do ProcStudio** pré-preenchido: no signup e na criação de novos escritórios, o escritório nasce com CNPJ, endereço, contato, data de fundação, natureza jurídica e o quadro de sócios da Receita.
2. **CNPJ no legal_data**: preencher `societies.cnpj` para as sociedades OAB (hoje 3 de 169.503 têm CNPJ).
3. **Prospecção no FFD**: tabela de sociedades de advocacia ativas que não existem na base OAB (fundadas depois do corte do scrape, 11/07/2025, ou nunca raspadas), com e-mail e telefone, ligadas ao CRM de advogados quando um sócio é advogado conhecido.

## 2. Decisões tomadas

| Decisão | Escolha | Motivo |
|---|---|---|
| Escopo de ingestão | Só CNAE 6911701 (advocacia), 261.347 estabelecimentos | Cobre os três objetivos. CNPJ arbitrário vai na API pública ao vivo, com cache. |
| Onde a base vive | Postgres do legal_data no H1 | H1 tem 274 GB livres e já é a fonte de verdade de advogados. ProcStudio e FFD só consultam o legal_data; nenhum deles toca o dump nem a API pública (regra: nenhuma API externa a partir do frontend). |
| Onboarding | Signup e criação de escritório pré-preenchidos, mais botão "Buscar dados do CNPJ" no formulário | Pedido explícito do Bruno. |
| FFD | Tabela própria `legal_crm_firms` chaveada por CNPJ | Firma sem advogado na base não cabe no CRM de advogados (chave OAB). |
| Sociedade sem advogado OAB | Nunca entra em `societies` | `LawyerSociety#destroy_orphan_society` apaga sociedade sem vínculo. Prospects vivem só em `receita_companies` (§7 do plano antigo, opção a). |

## 3. Evidência (spike offline de 2026-10-06, descartável)

Casamento das 169.503 sociedades OAB (espelho local de 02/08/2026) contra as 261.347 firmas do dump 2026-08, em 54 s de Python:

| Resultado | Qtd |
|---|---|
| verified | 148.140 (87%) — 144.212 por nome exato + sócio, 3.928 só por 2+ sócios |
| ambiguous | 1.952 |
| unmatched | 19.411 |

Prospects (firmas ativas, matriz, raiz de CNPJ não casada com sociedade OAB): **67.047**, dos quais 59.016 com sócio cujo nome é de advogado conhecido, 33.194 fundadas após 11/07/2025, 3.513 nos últimos 60 dias, 53.613 unipessoais, 63.061 com e-mail.

Perfil do recorte: 202.493 ativas, 253.276 com QSA, 226.199 com e-mail, 248.301 com telefone. CPF do sócio vem mascarado (`***146406**`, dígitos 4 a 9). Não existe percentual de quota. Naturezas: 169.532 Unipessoal, 70.721 Simples Pura, 11.967 Simples Ltda, 2.841 cartórios, ~1.600 órgãos públicos.

## 4. Fluxo de dados

```
OpenCNPJ data.zip (mensal, 13,5 GB)
   └─ receita:refresh (H1) ─ extrai CNAE 6911701 em streaming ─▶ storage/receita/<release>/advocacia.ndjson
         └─ receita:import ─▶ receita_companies + receita_partners
               └─ receita:match_societies ─▶ societies.cnpj, receita_companies.society_id, receita_partners.lawyer_id
                     ├─ GET /api/v1/lawyer/:oab  (societies[].cnpj, receita, partners) ─▶ ProcStudio signup / lookup
                     ├─ GET /api/v1/cnpj/:cnpj   (local ou api.opencnpj.org + cache)   ─▶ ProcStudio botão + planilha
                     └─ GET /api/v1/receita/companies (filtros + cursor)               ─▶ FFD legal_crm_firms
```

## 5. legal_data

### 5.1 Tabelas

**`receita_companies`** (chave natural `cnpj`, string 14, unique)

| Coluna | Tipo | Origem |
|---|---|---|
| cnpj | string, PK lógica, índice unique | `cnpj` |
| cnpj_root | string 8, índice | `cnpj[0,8]` (agrupa matriz e filiais) |
| razao_social, nome_fantasia | string | idem |
| name_normalized | string, índice (uf, name_normalized) | normalização §5.3 |
| situacao_cadastral, data_situacao_cadastral, motivo_situacao | string, date, string | idem |
| matriz | boolean | `matriz_filial == 'Matriz'` |
| data_inicio_atividade | date, índice | idem |
| cnae_principal | string | idem |
| natureza_juridica | string, índice | idem |
| tipo_logradouro, logradouro, numero, complemento, bairro, cep, uf, municipio, codigo_municipio | string | idem |
| email | string | lowercase |
| telefones | jsonb `[{ddd, numero, is_fax}]` | idem |
| capital_social | decimal(15,2) | `"4800,00"` → 4800.00 |
| porte_empresa, opcao_simples, data_opcao_simples, opcao_mei | string/date | idem |
| raw | jsonb | linha inteira do dump, para não reimportar quando um campo novo for preciso |
| source | string | `dump` ou `opencnpj_api` |
| release | string | `2026-08` (dump) ou nulo (api) |
| fetched_at | datetime | quando a linha foi gravada (expira cache da api em 30 dias) |
| society_id | bigint FK nullable, índice | preenchido pelo matcher |
| match_confidence | string | `verified`, `ambiguous`, `unmatched` |
| matched_at | datetime | |

**`receita_partners`**

| Coluna | Tipo |
|---|---|
| receita_company_id | FK, índice |
| nome_socio | string |
| name_normalized | string, índice |
| cpf_mascarado | string 11 (`***146406**`) |
| identificador | string (`Pessoa Física`, `Pessoa Jurídica`, `Estrangeiro`) |
| qualificacao | string (`Sócio-Administrador`, `Sócio com Capital`...) |
| data_entrada_sociedade | date |
| faixa_etaria | string |
| lawyer_id | FK nullable, índice |
| first_seen_release, last_seen_release | string |

Índice unique em (receita_company_id, name_normalized, cpf_mascarado). Sócio que some do QSA numa release nova mantém a linha com `last_seen_release` antigo. Isso é o diff de quadro societário sem tabela de eventos.

`societies` não ganha coluna nova. `cnpj`, `cnpja_match_confidence` e `cnpja_synced_at` passam a ser escritos pelo matcher da Receita. `cnpja_data` fica como está (vazio).

### 5.2 Importador — `rake receita:import FILE= RELEASE= [DRY_RUN=true]`

- Lê NDJSON com `File.foreach(file).each_slice(2000)`, uma transação por fatia, `upsert_all` em `receita_companies` por `cnpj`. Linha malformada conta em `stats[:malformed_line]` e não derruba o lote (padrão de `lib/tasks/import_mg.rake`).
- Sócios: por empresa, `upsert_all` por (empresa, nome normalizado, cpf mascarado), atualizando `last_seen_release`; `first_seen_release` só no insert.
- Só `identificador_socio == 'Pessoa Física'` recebe `name_normalized` para match; PJ e estrangeiro ficam na tabela sem vínculo.
- Idempotente: rodar duas vezes a mesma release não muda nada.
- Resumo no fim: lidas, inseridas, atualizadas, sócios, malformadas.

### 5.3 Normalização de nome (única, compartilhada)

`ActiveSupport::Inflector.transliterate(name).gsub(/[^A-Za-z ]+/, ' ').strip.upcase.squeeze(' ')`, idêntica à de `Cnpja::SocietyMatcher#normalize` e `import_mg.rake`. Fica em `Receita::NameNormalizer.call` e as duas cópias antigas passam a chamá-la.

### 5.4 Matcher — `rake receita:match_societies [STATE=] [DRY_RUN=true]`

Serviço `Receita::SocietyMatcher`, sem HTTP, 100% SQL e Ruby:

1. Para cada `Society` com advogados: candidatos = empresas da mesma UF com `name_normalized` igual ao nome da sociedade **ou** com algum sócio cujo `name_normalized` é igual ao de um advogado da sociedade.
2. Confirmados = candidatos com `≥ 1` sócio batendo com advogado da sociedade.
3. Fortes = confirmados com nome exato **ou** `≥ 2` sócios batendo. Nome parecido sem sócio batendo não conta (caso LEON). Nome diferente com sócio batendo conta (caso FIGUEIRERO).
4. Agrupa fortes por `cnpj_root`. Uma raiz: `verified`, escolhe matriz ativa, senão matriz, senão a primeira. Mais de uma raiz: `ambiguous`. Nenhum forte: `unmatched`.
5. `verified` grava `societies.cnpj`, `cnpja_match_confidence = 'verified'`, `cnpja_synced_at`, `receita_companies.society_id` e `match_confidence`. Liga `receita_partners.lawyer_id` ao advogado da sociedade cujo nome bateu.
6. `ambiguous` grava só `match_confidence` nas empresas e `cnpja_match_confidence = 'ambiguous'` na sociedade. **Nunca promove automaticamente.**
7. Sociedade já `verified` com o mesmo CNPJ em release nova: só atualiza `cnpja_synced_at`. Se o CNPJ sumiu do dump (baixa definitiva), mantém o CNPJ e deixa a situação visível pela empresa.

Vínculo sócio → advogado **fora** de sociedade casada (para prospects): `rake receita:link_partners` liga `receita_partners.lawyer_id` quando o `name_normalized` corresponde a exatamente um advogado principal na mesma UF. Homônimo na UF: sem vínculo (25.074 nomes existem em mais de uma UF; dentro da UF o número é menor, mas a regra é a mesma).

### 5.5 Refresh — `rake receita:refresh RELEASE=2026-09`

Roda no H1 via SSH (fora do Puma; `ProtectSystem=strict` só vale para o serviço). Passos:

1. Baixa `https://file.opencnpj.org/releases/receita/data.zip` para `storage/receita/<release>/data.zip` com `curl -C -` (retomável). Confere o MD5 contra `info.json` (`zip_md5checksum`). Falha de MD5 aborta.
2. Extrai em streaming: `unzip -Z1 | while read member; unzip -p data.zip "$member" | grep '"cnae_principal":"6911701"'` para `advocacia.ndjson` (o script `extract_advocacia.sh` que já existe no dump do Mac, levou ~20 min para 987 shards).
3. `receita:import`, `receita:match_societies`, `receita:link_partners`.
4. Apaga o zip; mantém o NDJSON da release (500 MB) e apaga releases com mais de 3 meses.
5. Resumo via `UsageReportJob`-like POST ao webhook do FFD (`usage` source, tipo `receita_refresh`), para aparecer em Alertas.

Primeira carga em produção: `scp` do `advocacia_6911701.ndjson` já extraído no Mac (502 MB) para `storage/receita/2026-08/` e rodar os passos 3 e 5. Agendamento mensal fica manual nesta rodada; cron entra quando dois refreshes tiverem passado sem incidente.

### 5.6 API pública (changelog versão 1.6)

**Payload do advogado** (`GET /api/v1/lawyer/:oab`, `LawyerSerializer#society_attributes`): cada sociedade ganha

```json
"cnpj": "49780032000146",
"receita": {
  "situacao_cadastral": "Ativa", "data_inicio_atividade": "2019-03-04",
  "natureza_juridica": "Sociedade Simples Pura", "capital_social": "10000.00",
  "porte_empresa": "Micro Empresa (ME)", "opcao_simples": "S",
  "email": "adv5898s@gmail.com", "telefones": [{"ddd":"45","numero":"30355898","is_fax":false}],
  "endereco": {"tipo_logradouro":"RUA","logradouro":"PARANA","numero":"3056","complemento":"SALA 2","bairro":"CENTRO","cep":"85810010","municipio":"CASCAVEL","uf":"PR"}
},
"partners": [
  {"nome":"BRUNO PELLIZZETTI","qualificacao":"Sócio-Administrador","data_entrada":"2019-03-04","faixa_etaria":"31 a 40 anos","oab_id":"PR_54159"},
  {"nome":"FULANO WALBER","qualificacao":"Sócio com Capital","data_entrada":"2019-03-04","faixa_etaria":"31 a 40 anos","oab_id":null}
]
```

Só quando `cnpja_match_confidence == 'verified'`. Caso contrário `cnpj: null`, `receita: null`, `partners: []`. Sócios com `last_seen_release` menor que a release atual não entram em `partners`. Eager load: `societies: :receita_company → :receita_partners`.

**`GET /api/v1/cnpj/:cnpj`** (chave `read`): normaliza para 14 dígitos (aceita o CNPJ alfanumérico de 2026, já aceito pelo `CnpjValidatable` do ProcStudio), valida dígito verificador. Busca em `receita_companies`; se ausente ou `source = 'opencnpj_api'` com `fetched_at` > 30 dias, chama `https://api.opencnpj.org/{cnpj}` (timeout 5 s, 1 tentativa), grava com `source: 'opencnpj_api'` e devolve. 404 da API vira 404 nosso, gravado como cache negativo por 7 dias (`raw: {}`, `situacao_cadastral: nil`). Resposta no mesmo formato do bloco `receita` acima, mais `cnpj`, `razao_social`, `nome_fantasia`, `matriz`, `cnae_principal` e `partners` (sem `oab_id` a menos que a empresa seja do recorte casado). Rate limit continua no nginx (10 r/s).

**`GET /api/v1/receita/companies`** (chave `read`), para o FFD:

| Parâmetro | Comportamento |
|---|---|
| `uf` | obrigatório |
| `situacao` | default `Ativa` |
| `matriz` | default `true` |
| `founded_since` | `data_inicio_atividade >= date` |
| `natureza` | lista separada por vírgula; default exclui cartório e órgão público |
| `unmatched` | `true` = `society_id IS NULL` e nenhuma empresa da mesma raiz casada |
| `known_lawyer` | `true` = ao menos um sócio com `lawyer_id` |
| `updated_since` | `updated_at >= datetime`, para sync incremental |
| `from_cnpj`, `limit` (≤ 500) | cursor por CNPJ crescente; `meta.next_from_cnpj` |

Cada item: campos cadastrais, contato, `society_id`, `match_confidence`, `partners[]` com `oab_id` e `lawyer_id`, `release`.

Todas as três mudanças registram `UsageEvent` como as rotas atuais e entram em `config/changelog.yml` como versão 1.6.

### 5.7 Testes (RSpec)

- `spec/tasks/receita_import_spec.rb`: fixture NDJSON com 6 linhas (matriz ativa, filial baixada, cartório, linha malformada, sócio PJ, firma sem QSA); idempotência; `first/last_seen_release`.
- `spec/services/receita/society_matcher_spec.rb`: casos nomeados LEON (nome igual, sócios diferentes → unmatched), FIGUEIRERO (nome diferente, sócio igual → verified), DANIELA HUDSON (matriz + filial → verified na matriz), duas raízes com sócio comum → ambiguous, associado fora do QSA não derruba o match.
- `spec/services/receita/partner_linker_spec.rb`: nome único na UF liga; homônimo não liga.
- `spec/requests/api/v1/cnpj_spec.rb`: local, cache expirado chama a API (WebMock), 404 negativo, CNPJ inválido 422, sem chave 401.
- `spec/requests/api/v1/receita_companies_spec.rb`: filtros, cursor, default de natureza.
- `spec/serializers/lawyer_serializer_spec.rb`: bloco `receita` e `partners` só com `verified`.

## 6. ProcStudio

### 6.1 Backend

**`LegalData::LegalDataService#extract_societies`** passa a copiar `cnpj`, `receita` e `partners` da sociedade. `clean_zip_code` e `clean_phone` já existentes aplicam-se aos campos da Receita.

**Signup** (`Public::UserRegistrationController#create_office_from_society`), atrás de `ENV['RECEITA_ENRICHMENT_ENABLED']` (default `true` em dev/HML, decidido no deploy em prod):

- `offices.cnpj` = `society[:cnpj]`; `foundation` = `data_inicio_atividade`; `society` = `'individual'` se natureza contém `Unipessoal`, senão `'company'`.
- Endereço: se a OAB não trouxe endereço, usa o da Receita já estruturado (street = `tipo_logradouro + logradouro`, number, complement, neighborhood, zip, city, state) sem passar pelo `split_address`. Se a OAB trouxe, mantém o da OAB (comportamento atual) e **não** cria um segundo.
- Telefone e e-mail: cria `phones` e `emails` do escritório com os da Receita quando a OAB não trouxe telefone; e-mail sempre (OAB não tem e-mail de sociedade).
- `user_offices` do próprio advogado: `entry_date` = `data_entrada_sociedade` do sócio cujo `oab_id` é o do usuário. `is_administrator` continua `true` e o percentual continua 100, como hoje: é o único usuário do time e a Receita não informa quota. A qualificação da Receita fica só no snapshot.
- Snapshot em coluna nova `offices.receita_data` (jsonb, default `{}`) com o bloco `receita` e `partners`, mais `receita_synced_at`. É o que a UI lê; nenhuma segunda chamada ao legal_data.
- Continua não-crítico: qualquer falha aqui loga e segue o cadastro.

**Novos endpoints**, autenticados, no `OfficesController` ou controller próprio `CnpjLookupsController`:

- `GET /api/v1/cnpj/:cnpj` → `LegalData::CnpjLookupService.call(cnpj)` → `GET {LEGAL_DATA_BASE}/cnpj/:cnpj`. Devolve subconjunto permitido (`CNPJ_LOOKUP_DATA_KEYS`: razao_social, nome_fantasia, situacao_cadastral, foundation, society, natureza_juridica, address{street,number,complement,neighborhood,zip_code,city,state}, phones[], email, partners[]). Nunca 500: falha vira `{found: false}`. Rate limit por usuário 60/dia (mesmo mecanismo de `lookup_oab`, 20/dia).
- `LEGAL_DATA_BASE` deriva de `LEGAL_DATA_ENDPOINT` removendo o sufixo `/lawyer/`; sem env nova.

**Criação e edição de escritório** (`OfficesController#create/#update`): sem mudança de regra; o prefill é do frontend. `receita_data` e `receita_synced_at` **não** entram em `office_permitted_attributes`: só o servidor escreve neles, no signup e em `POST /api/v1/offices/:id/receita_sync`, que refaz a consulta pelo CNPJ gravado no escritório e atualiza o snapshot. O formulário chama `receita_sync` depois de salvar um escritório cujo CNPJ foi preenchido ou alterado.

### 6.2 Frontend

- **Formulário de escritório** (`teams/OfficeForm.svelte` + `OfficeBasicInformation.svelte`): botão "Buscar dados do CNPJ" ao lado do campo CNPJ, habilitado quando o CNPJ valida localmente (`validation/cnpj.ts`). Chama `officeService.lookupCnpj` → `GET /api/v1/cnpj/:cnpj`. Prefill via `mergeOabPrefill`-like (`utils/cnpj-prefill.ts`, mesma semântica: nunca sobrescreve o que o usuário digitou, descarta resposta atrasada, nunca bloqueia). Preenche nome (só se vazio), fundação, tipo de sociedade, endereço, telefone e e-mail. Não preenche site nem dados fiscais. Feedback inline com os textos de `oab-lookup-feedback.ts` adaptados.
- **Sócios no formulário**: seção "Sócios na Receita" lista `partners` com nome, qualificação, desde e OAB quando houver, com botão "Convidar" que abre o modal de convite de time existente (`team_invites`, por e-mail; o sócio digita o e-mail). Sócio que já é usuário do time aparece com link para o vínculo. Não cria `user_offices` automaticamente para terceiros.
- **Completude de perfil** (`users/ProfileCompletion.svelte`): card "Escritório identificado na Receita" no passo Dados Básicos, lido de `office.receita_data`: razão social, CNPJ, situação, fundação e os sócios com o mesmo botão Convidar. Botão "Não é meu escritório" leva ao formulário de escritório para editar. Card some quando `receita_data` está vazio.
- **Planilha** (`stores/planilhaStore.svelte.ts:1255`): `openCnpjService.fetchMany` passa a chamar `GET /api/v1/cnpj/:cnpj` do ProcStudio (mesma concorrência 5, mesmo cache em memória). `api-external/services/opencnpj-service.ts` é removido; o `BASE_URL` externo deixa de existir no frontend.

### 6.3 Testes

- Request spec do signup: payload do legal_data stubado com `cnpj`, `receita`, `partners` → office com cnpj, foundation, society, endereço da Receita quando OAB vazia, phone/email, `receita_data`, `entry_date`; flag desligada → comportamento atual; payload sem `receita` → comportamento atual.
- Request spec de `GET /api/v1/cnpj/:cnpj`: sucesso, legal_data fora (`found: false`), CNPJ inválido 422, rate limit.
- Vitest: `cnpj-prefill.ts` (blank-only, resposta atrasada), `planilhaStore` chamando o endpoint interno.
- E2E Playwright existente de criação de escritório ganha um cenário com o botão (dados mockados na rota).

## 7. FFD (ai-dashboard)

### 7.1 Tabela `legal_crm_firms` (`lib/db/schema.ts` + `lib/db/migrations.ts`)

| Coluna | Tipo |
|---|---|
| cnpj | text PK |
| cnpj_root, razao_social, nome_fantasia, state, city, cep | text |
| email, phone_1, phone_2 | text |
| natureza, situacao, porte, opcao_simples | text |
| founded_at | text (ISO date), índice |
| unipessoal | integer 0/1 |
| society_id, match_confidence | text |
| partners_json | text `[{nome, qualificacao, desde, oab_id, lawyer_id}]` |
| known_oab_ids_json | text `["PR_54159"]` |
| stage | text, default `discovered` (mesmos valores de `lib/legal-crm/constants.ts`) |
| contacted_at, notes | text |
| last_synced_at | text, not null |

Índices: (state, stage), founded_at, (state, unipessoal). Suprimida por `lead_suppression` quando algum `known_oab_id` está lá.

### 7.2 Sync

- `lib/legal-crm/firms-sync.ts`: `syncFirms(db, cfg, state, { since })` chama `GET /receita/companies?uf=&unmatched=true&situacao=Ativa&matriz=true&updated_since=&from_cnpj=&limit=500` até `next_from_cnpj` nulo, `INSERT ... ON CONFLICT(cnpj) DO UPDATE` preservando `stage`, `contacted_at`, `notes`. Cliente em `lib/legal-crm/client.ts` (`fetchReceitaCompanies`).
- `POST /api/legal-crm/firms/sync` (sessão) com `states` no body; default `['PR']` como o sync atual, configurável em `app_settings` chave `legal_crm_firm_states`.
- Agendador diário às 07:30 em `instrumentation.ts`, ao lado do classificador DJEN, com `since` = último `last_synced_at`.

### 7.3 UI — `/marketing/crm/firmas`

- Tabela (padrão `ListView.tsx` / `UsageTable.tsx`): razão social, cidade/UF, fundada em, natureza (chip Unipessoal), sócios (nome + chip OAB quando conhecida, link para `/marketing/crm/[oab]` quando o advogado está em `legal_crm_lawyers`; senão botão "Importar" que chama `range-fetch` para a OAB), e-mail, telefone, estágio (select), ações.
- Filtros (`FilterBar` adaptado): UF, cidade (`CityAutocomplete`), fundada desde (atalhos 30/60/90 dias e "após corte OAB"), unipessoal, sócio conhecido, com e-mail, estágio. Filtro salvo reaproveita `legal_crm_saved_filters` com `kind: 'firms'`.
- Sinais (`SignalPill`): **Nova** (fundada < 60 dias), **Sem advogado na base**, **Sócio já contatado** (algum `known_oab_id` com `contacted_at`).
- Contato rápido: `QuickContact` com `wa.me` do `phone_1` e `mailto` do `email`, templates do canal com variáveis `{{firma}}`, `{{socio}}`, `{{cidade}}`. Registro em `legal_crm_activity_log` com coluna nova `cnpj` (migration `ALTER TABLE ... ADD COLUMN cnpj TEXT` + índice), `oab_id` nulo e `kind: 'message_sent'`.
- Sem exportação CSV, sem envio automático, sem mapa.

### 7.4 Testes (Vitest)

- `firms-sync.test.ts`: paginação por cursor, upsert preserva `stage`/`notes`, supressão.
- `app/api/legal-crm/firms/route.test.ts`: filtros e ordenação (fundada desc).

## 8. Erros, limites e LGPD

- Dados da Receita são públicos; CPF nunca completo; o legal_data já guarda 1,85 M terceiros. Nomes e faixa etária de sócios ficam em `receita_partners` com a mesma política dos advogados.
- Nenhuma consulta de CNPJ bloqueia signup, formulário ou planilha: falha = campos vazios + mensagem.
- API pública do OpenCNPJ: limite não documentado no site; o legal_data faz 1 tentativa por CNPJ, cache de 30 dias e `Cache-Control` de 24 h já vem da própria API. Se a API devolver 429, resposta `503` nossa com `retry_after` e sem cache.
- Firma baixada ou inapta entra na base com `situacao_cadastral`; filtros do FFD e o payload do advogado a expõem mas não a escondem.
- `receita_companies.raw` guarda a linha inteira: 261 k linhas × ~2 KB ≈ 600 MB por release; aceito. Releases antigas não são mantidas na tabela (upsert sobrescreve), só os NDJSON em disco por 3 meses.

## 9. Fora de escopo nesta rodada

- Base completa (72,8 M) no Postgres.
- Diff de quadro societário como evento ou alerta (os campos `first/last_seen_release` já permitem no futuro).
- Prefill de cliente PJ e sugestão de representantes a partir do QSA.
- Cron mensal automático do refresh (manual nas duas primeiras).
- Flag por time (não existe o sistema ainda; usa ENV).
- Canal de envio real no FFD.

## 10. Entrega

| PR | Repo | Conteúdo | Depende de |
|---|---|---|---|
| 1 | prc_legal_data | migrations, importador, normalizador compartilhado, matcher, linker, refresh, 3 mudanças de API, changelog 1.6, deploy + primeira carga 2026-08 | — |
| 2 | ProcStudio-Docker | `extract_societies`, signup, `receita_data`, `GET /cnpj/:cnpj`, `receita_sync`, prefill no formulário, card na completude, planilha via proxy | PR 1 em produção |
| 3 | ai-dashboard | tabela, sync, agendador, página de firmas | PR 1 em produção |
| 4 | prc_legal_data | ajustes pós primeira carga real + segunda release (2026-09) pelo `receita:refresh` | PR 1 |

Cards no Linear (time PRC): um por PR, labels Backend/Feature (1, 2), Frontend/Feature (2), Improvement (3), com link para esta spec. Execução por subagentes, um por tarefa do plano.
