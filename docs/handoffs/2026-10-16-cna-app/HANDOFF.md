# Handoff — ingestão dos lotes do app CNA (desambiguação, sociedades, conflitos)

Data: 2026-10-16
Estado: **brainstorming em andamento, nada codado**. Formato da tela de revisão aprovado pelo Bruno; faltam dois cruzamentos no banco antes de fechar o desenho e escrever o plano.
Próximo passo de processo: terminar o desenho (`docs/superpowers/specs/2026-10-16-cna-app-ingestion-design.md`), depois `superpowers:writing-plans`.

## 1. Pedido original (Bruno, 2026-10-16)

Os crawlers do app CNA (repo `ProcStudioOrg/prc_oab`, Android) voltaram a rodar em lotes pequenos. Dados de sociedade vêm incompletos, mas seguimos. Precisamos facilitar a ingestão no legal_data:

1. **Desambiguar homônimos.** A OAB não indexa pessoa: cada inscrição é uma linha solta. Quem monta "Bruno Pellizzetti = PR principal + RS/SC/DF suplementares" somos nós (`principal_lawyer_id`). Hoje o vínculo nasce do nome normalizado; "José da Silva" vira falso positivo.
2. **Adicionar as sociedades** citadas pelo lote.
3. **Resolver conflitos** com o que já existe no banco.
4. **Enriquecer com CNPJ** — já está aplicado (ver §4), é o de menos.

Decisões já tomadas na conversa:

- Importador liga suplementar → principal sozinho quando **nome + um segundo sinal** batem (sociedade em comum, UF do endereço, telefone). Quando só o nome bate ou há 2+ candidatos, cai numa **fila de revisão manual**.
- A revisão é um **HTML local, estático**, gerado por rake a partir do lote: Bruno olha foto e campos e decide à mão (antigamente havia um script Python de comparação facial em lote; com lotes pequenos a revisão humana basta).
- **Formato aprovado da tela**: lista, todos os casos numa página, um embaixo do outro. Cada caso é uma tabela: suplementar nova na coluna azul, candidatos nas colunas ao lado, **campo a campo na mesma linha** (foto, inscrição, data, endereço, telefone, sociedades). Verde = bate, vermelho = contradiz. Última linha = decisão (um botão por candidato + "pessoa nova"). Caso resolvido pelo importador já vem marcado com o motivo. Botão "Exportar decisões (JSON)" → uma task aplica no banco. Mockup: `mockup-comparador-lista.html` nesta pasta (fotos substituídas por placeholder). A primeira versão, "um caso por vez em cards", foi **rejeitada** ("muito confuso").
- Perguntas ainda em aberto para o Bruno: (a) mostrar os automáticos na lista já marcados ou só no resumo? (b) o que fazer quando o registro já existe e o lote traz dado diferente (ver §3.3).

## 2. O lote de amostra

Pasta original (nesta máquina Linux, **não** está no repo): `/home/brpl/Downloads/cna_2026-10-16_073343`. O `legal_data.jsonl` (303 registros) está copiado nesta pasta do handoff; fotos (`images/`, 300 jpg) e `raw_results/` não.

- `LEIA-ME-do-lote.txt` (cópia) descreve o pacote. Resumo: 305 consultas, 303 encontradas (297 PR, 6 MG), 72 com sociedade, 27 SUPLEMENTAR, 297 fotos nomeadas no padrão `cna_picture` (`PR_131031.jpg`).
- Formato de cada linha: `oab_number, state, full_name, address, city, zip_code, phone_number_1/2, situation (REGULAR|CANCELADO), subsecao, tipo_inscricao (ADVOGADO|ADVOGADA|SUPLEMENTAR), inscription_date (dd/mm/yyyy), societies[{name, inscricao, state}], cna_picture, source: cna_app, scraped_at`.
- `raw_results/<n>_<UF>.json` tem o original do app com `endereco_profissional` e `telefones_profissionais` (a suplementar traz endereço/telefone **da principal**, em outra UF — é a pista mais forte depois da sociedade).
- Nenhuma consulta devolveu mais de um resultado (`list_parsed` sempre 1): o lote em si não tem ambiguidade de busca.
- O próprio LEIA-ME avisa: **não usar `rake mg:import`** (fixa `state=MG`, pula advogado existente, não casa sociedade por inscrição, não sobe foto).

## 3. O que já foi cruzado com produção (API, só GET) — `crosscheck_api.py` / `crosscheck_api_result.json`

Rodado com a key de leitura de `~/code/env` (`LEGAL_DATA_API_KEY`, endpoint `procstudio.api.br/api/v1`). Versão em produção: 1.10, commit f55d42f.

| | Qtd |
|---|---|
| Advogados já no banco | 6 (todos MG) |
| Advogados novos | 297 (bloco PR 131031–131306, inscritos jul/2025+, depois do corte do scrape CNA de 11/07/2025) |
| Suplementares (todas novas) | 27 |
| Sociedades distintas citadas | 84 (PR 68, SP 10, MG 3, RJ 2, RS 2, SC 1) |

### 3.1 Homônimos — NÃO medido ainda

A API não tem busca por nome e as 27 suplementares são novas, então os candidatos só aparecem consultando o banco. Pistas que o lote dá para elas: 14 trazem sociedade com UF, 20 trazem UF no endereço, 21 trazem telefone. Só 3 chegam com nome e foto e nada mais: PR 131050 (cancelada), 131187, 131238.

→ **Rodar `server_crosscheck.rb` no H1** (instruções no cabeçalho do script). Ele devolve, por suplementar, todos os registros com o mesmo nome normalizado e o tipo que o `Lawyers::ClusterClassifier` atual daria.

### 3.2 Sociedades — achado estrutural

Em produção, **`societies.inscricao` é o id interno do CNA (IdtSoci)**, não o número OAB da sociedade. O número OAB fica em **`societies.oab_id`** (string, ex.: Pellizzetti e Walber = `oab_id "000015154"`, `inscricao 386179`). Origem: `lib/tasks/society.rake` linhas 174–176. O app traz **só o número OAB + UF**.

Consequências para o importador novo:

- Casar sociedade por **`[oab_id, state]`**, nunca por `inscricao`. Não existe índice único nessa dupla para `source: cna` (só o parcial de `oab_portal`).
- `Society` valida `inscricao presence unless portal_sourced?` — o app não tem IdtSoci. Precisa de `source: 'cna_app'` (com validação própria e índice único `[state, oab_id]`) ou relaxar.
- `GET /api/v1/society/:inscricao` só busca numérico por `inscricao`; o cruzamento inicial por essa rota deu 4 "conflitos de UF" que são **falso alarme** (número OAB de PR colidindo com IdtSoci de MG/DF/ES). Ignorar essa parte do `crosscheck_api_result.json`.
- Formatos de `inscricao` no lote: PR com 9 dígitos (`000021802`, 52×), PR prefixado (`OABPR2624428`, 16×), SP/RS/SC/MG curtos (`12244`), RJ com 8–9 dígitos (`67302023`). **Não sei se o banco guarda `OABPR…` assim** — `server_crosscheck.rb` lista os formatos de `oab_id` das sociedades PR existentes.
- Existência das 84 no banco: desconhecida pela API; o script do servidor responde por `[oab_id, state]` e, se não achar, por nome normalizado na UF.

### 3.3 Conflitos nos 6 MG existentes

- `situation`: banco guarda `"situação regular"`, lote traz `"REGULAR"` / `"CANCELADO"`. O importador precisa normalizar antes de comparar (e decidir o formato canônico).
- MG 69856: regular no banco → **CANCELADO** no lote (mudança real).
- MG 69859 (cancelado): `GET /lawyer/MG_69859` responde **422 "Status Inválido (Principal)"** — a API recusa principal cancelado. Não é bug do lote, mas afeta qualquer conferência via API.
- Pergunta em aberto: quando o registro existe, o lote **sobrescreve** endereço/telefone/situação? Minha proposta (não validada): o lote vence para `situation`, `address`, `city`, `zip_code`, `phone_*`, `cna_picture`; nunca mexe em `crm_data`, `principal_lawyer_id`, `email`, `profile_picture`; guarda `scraped_at` em `crm_data`.

## 4. CNPJ — já resolvido, nada a fazer além de rodar

Pipeline OpenCNPJ no próprio servidor (`lib/tasks/receita.rake`, spec em `docs/superpowers/specs/2026-10-06-receita-cnpj-enrichment-design.md`, operação no README §"Receita Federal"). `societies.cnpj` só recebe match `verified`. O "cadastro nacional de CNPJs no SSD do Mac mini" é o mesmo dump; o servidor baixa sozinho (`receita:refresh RELEASE=AAAA-MM`). Para sociedades novas do lote: `rake receita:match_societies STATE=PR` depois do import.

## 5. Estado do código relevante

- `lib/tasks/import_mg.rake` — referência de estilo (idempotente, DRY_RUN, stats), mas MG-only e pula existentes.
- `lib/lawyers/cluster_classifier.rb` + `Lawyers::Linker` + `lib/tasks/duplicate_names.rake` (`find_unlinked_clusters`, `apply_name_links`) — classificação por nome; tipos SAFE ligam sozinho, AMBIGUOUS esperam face-match.
- `lib/tasks/link_face_matches.rake` — aplica `face_match_results.json` gerado por script Python externo (não está em nenhum repo local; procurei).
- Fotos: bucket S3 `oabapi-profile-pic` (`config/initializers/s3_config.rb`), chave = `cna_picture` (`PR_131031.jpg`). O importador precisa fazer o upload de `images/`.
- `app/models/society.rb` / `lawyer_society.rb` — sem portão de capacidade; `number_of_partners` é informativo (`sync_number_of_partners!`).
- Sem SSH para o H1 nesta máquina Linux (a chave `~/.ssh/deploy_prc_legal` do README não existe aqui); banco local tem 1 advogado. Por isso tudo foi via API.

## 6. Esqueleto do desenho (minha proposta, para você validar)

```
rake cna:import FILE=<pasta do lote> [DRY_RUN=true] [UPLOAD_PHOTOS=true]
  1. advogado: upsert por oab_id (STATE_NUMERO) respeitando state do registro
  2. sociedade: find_or_create por [state, oab_id] com source cna_app; vínculo LawyerSociety
  3. suplementar: candidatos = mesmo nome normalizado, não-suplementar, regular
       - 0 candidatos            → fica solta, entra na fila como "pessoa nova?"
       - 1 candidato + 2º sinal  → liga, registra motivo em crm_data.link_reason
       - resto                   → fila (tmp/cna_review_<lote>.json)
  4. fotos → S3 (chave = cna_picture)
  5. resumo + gera tmp/cna_review_<lote>.html (formato §1)
rake cna:apply_review INPUT=decisoes.json [DRY_RUN=true]
rake receita:match_societies STATE=PR
```

Segundo sinal, em ordem de força: sociedade `[state, oab_id]` em comum > telefone igual (só dígitos) > UF do `endereco_profissional` == UF do candidato (e único candidato nessa UF). Data de inscrição: principal sempre mais antiga que a suplementar (descarta candidato mais novo).

## 7. Arquivos nesta pasta

| Arquivo | O que é |
|---|---|
| `HANDOFF.md` | este documento |
| `legal_data.jsonl` | os 303 registros normalizados do lote |
| `LEIA-ME-do-lote.txt` | README original do pacote do crawler |
| `crosscheck_api.py` | cruzamento via API (`python3 -I crosscheck_api.py <pasta_lote> saida.json`; lê `~/code/env`) |
| `crosscheck_api_result.json` | resultado do cruzamento de 2026-10-16 (seção `societies` com o falso alarme de §3.2) |
| `server_crosscheck.rb` | **rodar no H1** com `rails runner`; só leitura; responde §3.1 e §3.2 |
| `mockup-comparador-lista.html` | tela aprovada (abrir no navegador; fotos são placeholder) |
