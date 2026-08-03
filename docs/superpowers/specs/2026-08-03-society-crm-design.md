# CRM de Sociedades (PJ) — Design Spec

**Date:** 2026-08-03
**Status:** Approved
**Owner:** Bruno Pellizzetti
**Branch:** `feat/mg-import-2026-08`

## Goal

Dar à pessoa jurídica (`Society`) a mesma capacidade de enriquecimento que a pessoa
física (`Lawyer`) já tem: um campo `crm_data` JSONB e um endpoint de escrita que
aceita sub-hashes livres vindos do scraper de IA.

Hoje a assimetria é total: `Lawyer` tem `crm_data` + `store_accessor` +
`POST /lawyer/:oab/crm` com deep-merge; `Society` não tem nada equivalente.

## Estado de partida (importante)

O commit `005b17a` (lote OAB-MG) já entregou parte do que parecia faltar:

| Item | Estado |
|---|---|
| `societies.email`, `.website`, `.source`, `.cnpj` | ✅ existe (migração `20260802000001`) |
| `:email` etc. nos strong params de create/update | ✅ existe |
| `SocietySerializer` expondo `email`/`website`/`source`/`cnpj` | ✅ existe |
| `societies.cnpja_data` (jsonb) | ✅ existe |
| `societies.crm_data` (jsonb) | ❌ este spec |
| `POST /society/:inscricao/crm` | ❌ este spec |
| Entrada no `config/changelog.yml` | ❌ este spec (cobre também a dívida de `005b17a`) |

## Decisão central: `crm_data` ≠ `cnpja_data`

São campos distintos, com donos distintos:

- **`cnpja_data`** — payload cru da Receita Federal via CNPJA. Escrito pelo
  `Cnpja::EnrichSocietyJob` (PLANO-CNPJA §5.4) e **sobrescrito a cada sync**.
- **`crm_data`** — estado de prospecção nosso (`researched`, `contacted`,
  `mail_marketing`, sub-hashes `scraper`/`outreach`/`signals`). Escrito por humano
  ou pelo scraper de IA.

Reaproveitar `cnpja_data` para CRM faria o próximo sync do CNPJA apagar o histórico
de contato. Separados por construção.

## Migração

`db/migrate/20260803000001_add_crm_data_to_societies.rb` — espelho exato de
`20260117025441_add_crm_data_to_lawyers.rb`:

```ruby
class AddCrmDataToSocieties < ActiveRecord::Migration[8.1]
  def change
    add_column :societies, :crm_data, :jsonb, default: {}, null: false
    add_index :societies, :crm_data, using: :gin
  end
end
```

## Model

`Society` ganha o mesmo `store_accessor` do `Lawyer`, menos os campos que só fazem
sentido para PF (`trial_active` é sobre atuação processual do advogado):

```ruby
store_accessor :crm_data,
  :researched,
  :last_research_date,
  :tried_procstudio,
  :mail_marketing,
  :mail_marketing_origin,
  :contacted,
  :contacted_by,
  :contacted_when,
  :contact_notes
```

Sem validações novas. `crm_data` é livre por design.

## Rota

```ruby
post 'society/:inscricao/crm', to: 'societies#update_crm'
```

Segue a convenção do repo: `POST` (não `PATCH`), path singular `society/`, e o
parâmetro chama-se `:inscricao` mas aceita os dois identificadores — número de
inscrição do CNA **ou** `oab_id` no formato `MG_<ordem>_SOCIEDADE` para sociedades
do portal da OAB-MG, que não têm inscrição. Isso já é responsabilidade do
`set_society` existente (`societies_controller.rb`), que basta incluir `:update_crm`
na sua lista de `before_action`.

Não há endpoint de leitura novo: `GET /society/:inscricao` passa a devolver
`crm_data` no payload que já existe.

## Auth

| Endpoint | API key | `authorize_write!` |
|---|---|---|
| `POST /society/:inscricao/crm` | sim | **sim** (admin) |
| `GET /society/:inscricao` | sim | não |

Espelha `LawyersController`, onde `update_crm` está em `authorize_write!`.

## Controller

`SocietiesController#update_crm`, cópia fiel de `LawyersController#update_crm`:

1. 404 se `@society` nil.
2. `params.permit` dos campos escalares do `store_accessor` (+ `mail_marketing_origin: []`).
3. Para cada uma de `%i[scraper outreach signals]`, se presente, `deep_permit_hash`.
4. 400 se o hash resultante ficou vazio.
5. `current_crm.deep_merge(crm_params.compact)` → `update(crm_data: new_crm)`.
6. 200 com `{ message:, inscricao:, oab_id:, crm_data: }`.

### Refactor: `deep_permit_hash` vira concern

`deep_permit_hash` é hoje um método privado de `LawyersController`
(`lawyers_controller.rb:635`). Como os dois controllers passam a precisar dele,
extrair para `app/controllers/concerns/crm_params.rb` e incluir nos dois. Código
idêntico, sem mudança de comportamento — os specs existentes de
`lawyer_update_crm_spec.rb` seguem verdes como rede de proteção.

### Semântica de merge

Idêntica à da PF, incluindo as limitações já documentadas no spec de 2026-04-25:
`compact` remove `nil` de topo (não dá para "desligar" uma chave mandando `null`),
arrays substituem, hashes internos fazem deep merge. Deleção de chave profunda
segue fora de escopo.

## Serializer

`SocietySerializer#base_attributes` ganha `crm_data: @society.crm_data || {}`.

Emitido sempre, mesmo vazio — mesma regra do `LawyerCrmSerializer`, para o
consumidor não precisar distinguir "ausente" de "vazio".

## Changelog

Uma entrada minor `1.4` no topo de `config/changelog.yml`, cobrindo **tudo** que
passou a vazar para a API pública nesta branch:

- `crm_data` em sociedades + `POST /society/:inscricao/crm` (este spec)
- `email`, `website`, `source`, `cnpj` no payload de sociedade (dívida de `005b17a`)
- `society/:inscricao` aceitando `oab_id` de sociedade do portal MG (dívida de `005b17a`)

## Testes

`spec/requests/api/v1/society_update_crm_spec.rb`, espelhando
`lawyer_update_crm_spec.rb`:

- Campos escalares persistem (`researched`, `contacted`, `contact_notes`).
- `scraper: { scraped: true, lead_score: 75 }` persiste.
- Chamadas sequenciais fazem deep-merge (`sources` preservado ao gravar `lead_score`).
- Aninhamento de 2 níveis (`scraper: { social: { instagram: "@x" } }`) persiste inteiro.
- Sociedade do portal MG (sem `inscricao`) é encontrada pelo `oab_id`.
- 404 para chave inexistente.
- 400 quando nenhum parâmetro de CRM é enviado.
- 403 com key `read`; 200 com key `admin`.

`spec/factories/societies.rb` ganha um trait `:with_crm` para os casos de merge.

Rodar também `spec/requests/api/v1/society_create_spec.rb` e
`lawyer_update_crm_spec.rb` — o refactor do concern toca os dois lados.

## Fora de escopo

- **Índice batch de sociedades** (`GET /api/v1/societies?state=&scraped=`) para o
  scraper varrer PJ em lote. Decidido conscientemente: entra numa PR própria quando
  houver requisito real de varredura de sociedades.
- **`GET /society/:inscricao/crm` dedicado.** O `show` de sociedade já é enxuto;
  um segundo endpoint de leitura seria redundante hoje.
- **Enriquecimento CNPJA** (`Cnpja::EnrichSocietyJob`, coluna `cnpj`,
  `cnpja_match_confidence`). É a Fase 1 do PLANO-CNPJA, frente separada.
- **Contatos múltiplos por sociedade.** `email` continua uma string canônica;
  e-mails secundários cabem em `crm_data.scraper` sem migração.
- **Deleção de chave profunda no JSONB.** Mesma limitação da PF.

## Dívida registrada (não resolvida aqui)

`PLANO-CNPJA.md` §7 recomendava a opção **(a)** (tabela `prospect_societies`
separada) para sociedades sem inscrição OAB. O commit `005b17a` implementou de
fato a opção **(b)** (`inscricao` nullable + flag `source`), porque o portal da
OAB-MG não expõe o número de inscrição das sociedades. O documento está
desatualizado em relação ao código e deveria ser corrigido numa passada própria.
