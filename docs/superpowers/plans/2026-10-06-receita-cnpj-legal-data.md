# Receita/OpenCNPJ no legal_data (PR 1) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ingerir o recorte de advocacia do dump OpenCNPJ no Postgres do legal_data, casar as sociedades OAB com seus CNPJs e expor três mudanças de API (payload do advogado, `GET /cnpj/:cnpj`, `GET /receita/companies`) para o ProcStudio e o FFD.

**Architecture:** Duas tabelas novas (`receita_companies`, `receita_partners`) alimentadas por um importador idempotente por release. Um matcher offline (sem HTTP) grava `societies.cnpj` só com confiança `verified`. Um serviço de lookup consulta a tabela e, na falta, a API pública do OpenCNPJ com cache de 30 dias. Tudo em `app/services/receita/` e `lib/tasks/receita.rake`, seguindo os padrões de `lib/tasks/import_mg.rake`, `Cnpja::SocietyMatcher` e `UsageReportJob`.

**Tech Stack:** Rails 8.1 API-only, Postgres 16, RSpec + FactoryBot + WebMock, `upsert_all`, Net::HTTP, rake. Ruby 3.4.7.

**Spec:** `docs/superpowers/specs/2026-10-06-receita-cnpj-enrichment-design.md` (seções 5 e 8). Divergência deliberada: a coluna `cpf_mascarado` da spec chama-se `documento` aqui, porque sócio Pessoa Jurídica traz CNPJ de 14 dígitos no mesmo campo.

## Global Constraints

- Branch de trabalho: `brpl/receita-cnpj` em `/Users/brpl/code/ProcStudio/prc_legal_data` (já existe, com a spec commitada). Todas as tarefas commitam nela.
- Toda rota exige `X-API-KEY` (concern `ApiAuthentication`); rotas GET novas incluem `UsageTracking`. Mensagens de erro em pt-BR.
- Mudança pública de API exige entrada no topo de `config/changelog.yml`: versão `"1.6"`, data `"06/10/2026"` (regra do `CLAUDE.md`).
- Normalização de nome única: `ActiveSupport::Inflector.transliterate(name.to_s).gsub(/[^A-Za-z ]+/, ' ').strip.upcase.squeeze(' ')`.
- `ambiguous` nunca é promovido a `verified` automaticamente. `societies.cnpj` só recebe valor com `verified`.
- Prospect (firma sem sociedade OAB) nunca cria linha em `societies` nem `lawyer_societies`.
- Nenhum CPF completo é gravado. O campo `documento` guarda o valor mascarado tal como vem do dump (`***146406**`).
- Rodar testes com `bundle exec rspec <arquivo>`; banco de teste `legal_data_api_test` já existe em localhost. WebMock bloqueia rede nos testes (`spec/support/webmock.rb`).
- Commits em pt-BR no padrão do repo: `feat(receita): ...`, `test(receita): ...`, `docs(receita): ...`, terminando com `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

## Review Focus

1. **CNPJ alfanumérico (regra de julho/2026)** em `GET /cnpj/:cnpj`: `12.ABC.345/01DE-35` deve normalizar e validar o dígito pela tabela ASCII−48; um CNPJ com dígito errado deve devolver 422, não consultar a API. Teste em Task 6 (`spec/lib/receita/cnpj_spec.rb`).
2. **Duas sociedades OAB casando a mesma firma**: o índice unique em `societies.cnpj` não pode explodir o matcher; a segunda vira `ambiguous` com motivo `cnpj_taken`. Teste em Task 4.
3. **Linha do dump sem QSA ou só com sócio PJ**: importa a empresa, grava o sócio PJ sem vínculo e não cria vínculo com advogado. Teste em Task 3.
4. **API OpenCNPJ devolvendo 429 ou estourando timeout**: resposta 503 com `retry_after`, sem gravar cache negativo. Teste em Task 7.
5. **`GET /receita/companies` sem `uf` ou com `limit` acima de 500**: 400 em pt-BR no primeiro caso, teto 500 no segundo. Teste em Task 8.

---

### Task 1: Migration e models `ReceitaCompany` / `ReceitaPartner`

**Files:**
- Create: `db/migrate/20261006120000_create_receita_companies.rb`
- Create: `app/models/receita_company.rb`
- Create: `app/models/receita_partner.rb`
- Modify: `app/models/society.rb` (adicionar `has_one :receita_company`)
- Modify: `app/models/lawyer.rb` (adicionar `has_many :receita_partners`)
- Create: `spec/factories/receita_companies.rb`
- Create: `spec/factories/receita_partners.rb`
- Test: `spec/models/receita_company_spec.rb`

**Interfaces:**
- Produces: tabelas e models com as colunas abaixo; `ReceitaCompany::SOCIETY_NATURES`, scopes `ativas`, `matrizes`, `advocacia`; `ReceitaCompany#current_partners`, `#unipessoal?`; `Society#receita_company`.

- [ ] **Step 1: Escrever o teste de model**

```ruby
# spec/models/receita_company_spec.rb
require 'rails_helper'

RSpec.describe ReceitaCompany, type: :model do
  it { is_expected.to belong_to(:society).optional }
  it { is_expected.to have_many(:receita_partners).dependent(:delete_all) }

  describe '.advocacia' do
    it 'exclui cartório e órgão público' do
      firma = create(:receita_company, natureza_juridica: 'Sociedade Unipessoal de Advocacia')
      create(:receita_company, natureza_juridica: 'Serviço Notarial e Registral (Cartório)')
      expect(described_class.advocacia).to contain_exactly(firma)
    end
  end

  describe '#current_partners' do
    it 'devolve só sócios vistos na release da empresa' do
      company = create(:receita_company, release: '2026-09')
      atual = create(:receita_partner, receita_company: company, last_seen_release: '2026-09')
      create(:receita_partner, receita_company: company, last_seen_release: '2026-08', name_normalized: 'ANTIGO')
      expect(company.current_partners).to contain_exactly(atual)
    end
  end

  describe '#unipessoal?' do
    it 'reconhece a natureza unipessoal' do
      expect(build(:receita_company, natureza_juridica: 'Sociedade Unipessoal de Advocacia')).to be_unipessoal
      expect(build(:receita_company, natureza_juridica: 'Sociedade Simples Pura')).not_to be_unipessoal
    end
  end

  it 'impede CNPJ duplicado' do
    create(:receita_company, cnpj: '49780032000146')
    expect { create(:receita_company, cnpj: '49780032000146') }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `bundle exec rspec spec/models/receita_company_spec.rb`
Expected: FAIL com `uninitialized constant ReceitaCompany`

- [ ] **Step 3: Escrever a migration**

```ruby
# db/migrate/20261006120000_create_receita_companies.rb
# Recorte de advocacia (CNAE 6911701) do dump mensal do OpenCNPJ, mais linhas
# avulsas vindas da API pública (source = 'opencnpj_api'). Ver a spec em
# docs/superpowers/specs/2026-10-06-receita-cnpj-enrichment-design.md §5.1.
#
# `receita_partners` nunca apaga sócio que saiu: `last_seen_release` fica na
# release antiga e isso é o diff de quadro societário.
class CreateReceitaCompanies < ActiveRecord::Migration[8.1]
  def change
    create_table :receita_companies do |t|
      t.string :cnpj, null: false, limit: 14
      t.string :cnpj_root, null: false, limit: 8
      t.string :razao_social
      t.string :nome_fantasia
      t.string :name_normalized
      t.string :situacao_cadastral
      t.date :data_situacao_cadastral
      t.string :motivo_situacao
      t.boolean :matriz, null: false, default: true
      t.date :data_inicio_atividade
      t.string :cnae_principal
      t.string :natureza_juridica
      t.string :tipo_logradouro
      t.string :logradouro
      t.string :numero
      t.string :complemento
      t.string :bairro
      t.string :cep
      t.string :uf
      t.string :municipio
      t.string :codigo_municipio
      t.string :email
      t.jsonb :telefones, null: false, default: []
      t.decimal :capital_social, precision: 15, scale: 2
      t.string :porte_empresa
      t.string :opcao_simples
      t.date :data_opcao_simples
      t.string :opcao_mei
      t.jsonb :raw, null: false, default: {}
      t.string :source, null: false, default: 'dump'
      t.string :release
      t.datetime :fetched_at, null: false
      t.references :society, foreign_key: true
      t.string :match_confidence
      t.datetime :matched_at

      t.timestamps
    end

    add_index :receita_companies, :cnpj, unique: true
    add_index :receita_companies, :cnpj_root
    add_index :receita_companies, [:uf, :name_normalized]
    add_index :receita_companies, :data_inicio_atividade
    add_index :receita_companies, :natureza_juridica
    add_index :receita_companies, :updated_at

    create_table :receita_partners do |t|
      t.references :receita_company, null: false, foreign_key: true, index: false
      t.string :nome_socio
      t.string :name_normalized
      t.string :documento
      t.string :identificador
      t.string :qualificacao
      t.date :data_entrada_sociedade
      t.string :faixa_etaria
      t.references :lawyer, foreign_key: true
      t.string :first_seen_release
      t.string :last_seen_release

      t.timestamps
    end

    add_index :receita_partners, [:receita_company_id, :name_normalized, :documento],
              unique: true, name: 'index_receita_partners_unique_member'
    add_index :receita_partners, :name_normalized
  end
end
```

- [ ] **Step 4: Escrever os models e associações**

```ruby
# app/models/receita_company.rb
# Estabelecimento da Receita Federal (dump OpenCNPJ ou API pública).
# Chave natural: `cnpj` (14 caracteres, unique). `cnpj_root` agrupa matriz e
# filiais. `society_id` só é preenchido pelo Receita::SocietyMatcher com
# confiança verified.
class ReceitaCompany < ApplicationRecord
  belongs_to :society, optional: true
  has_many :receita_partners, dependent: :delete_all

  SOURCE_DUMP = 'dump'
  SOURCE_API = 'opencnpj_api'

  # Naturezas jurídicas que são sociedade de advogados de verdade. Cartório e
  # órgão público também têm CNAE 6911701 e ficam fora por default.
  SOCIETY_NATURES = [
    'Sociedade Unipessoal de Advocacia',
    'Sociedade Simples Pura',
    'Sociedade Simples Limitada',
    'Sociedade Empresária Limitada',
    'Empresário (Individual)'
  ].freeze

  validates :cnpj, presence: true, length: { is: 14 }
  validates :cnpj_root, presence: true, length: { is: 8 }
  validates :source, inclusion: { in: [SOURCE_DUMP, SOURCE_API] }

  scope :ativas, -> { where(situacao_cadastral: 'Ativa') }
  scope :matrizes, -> { where(matriz: true) }
  scope :advocacia, -> { where(natureza_juridica: SOCIETY_NATURES) }
  scope :from_dump, -> { where(source: SOURCE_DUMP) }

  # Sócios presentes na release desta empresa. Para linha vinda da API (sem
  # release) devolve todos.
  def current_partners
    return receita_partners if release.blank?

    receita_partners.where(last_seen_release: release)
  end

  def unipessoal?
    natureza_juridica.to_s.include?('Unipessoal')
  end

  def negative_cache?
    source == SOURCE_API && raw.blank?
  end
end
```

```ruby
# app/models/receita_partner.rb
# Membro do QSA de um ReceitaCompany. `documento` é o CPF mascarado
# (`***146406**`) ou o CNPJ cheio quando o sócio é pessoa jurídica.
# `lawyer_id` é preenchido por Receita::SocietyMatcher (sócio de sociedade
# casada) ou Receita::PartnerLinker (nome único na UF).
class ReceitaPartner < ApplicationRecord
  belongs_to :receita_company
  belongs_to :lawyer, optional: true

  PESSOA_FISICA = 'Pessoa Física'

  scope :pessoa_fisica, -> { where(identificador: PESSOA_FISICA) }
  scope :linked, -> { where.not(lawyer_id: nil) }
  scope :unlinked, -> { where(lawyer_id: nil) }
end
```

Em `app/models/society.rb`, logo após `has_many :lawyers, through: :lawyer_societies`, adicionar:

```ruby
  # Estabelecimento da Receita casado com confiança verified (Receita::SocietyMatcher).
  has_one :receita_company, dependent: :nullify
```

Em `app/models/lawyer.rb`, logo após `has_one :djen_monitoring, dependent: :destroy`, adicionar:

```ruby
  has_many :receita_partners, dependent: :nullify
```

- [ ] **Step 5: Factories**

```ruby
# spec/factories/receita_companies.rb
FactoryBot.define do
  factory :receita_company do
    sequence(:cnpj) { |n| format('%014d', 10_000_000_000_100 + n * 100) }
    cnpj_root { cnpj[0, 8] }
    sequence(:razao_social) { |n| "FIRMA #{n} ADVOGADOS ASSOCIADOS" }
    name_normalized { Receita::NameNormalizer.call(razao_social) }
    situacao_cadastral { 'Ativa' }
    matriz { true }
    data_inicio_atividade { Date.new(2019, 3, 4) }
    cnae_principal { '6911701' }
    natureza_juridica { 'Sociedade Simples Pura' }
    tipo_logradouro { 'RUA' }
    logradouro { 'PARANA' }
    numero { '3056' }
    bairro { 'CENTRO' }
    cep { '85810010' }
    uf { 'PR' }
    municipio { 'CASCAVEL' }
    email { 'contato@firma.adv.br' }
    telefones { [{ 'ddd' => '45', 'numero' => '30355898', 'is_fax' => false }] }
    capital_social { 10_000 }
    porte_empresa { 'Micro Empresa (ME)' }
    opcao_simples { 'S' }
    raw { { 'cnpj' => cnpj } }
    source { ReceitaCompany::SOURCE_DUMP }
    release { '2026-08' }
    fetched_at { Time.current }

    trait :from_api do
      source { ReceitaCompany::SOURCE_API }
      release { nil }
    end

    trait :negative_cache do
      from_api
      raw { {} }
      razao_social { nil }
      name_normalized { nil }
      situacao_cadastral { nil }
    end
  end
end
```

```ruby
# spec/factories/receita_partners.rb
FactoryBot.define do
  factory :receita_partner do
    receita_company
    sequence(:nome_socio) { |n| "SOCIO NUMERO #{n}" }
    name_normalized { Receita::NameNormalizer.call(nome_socio) }
    sequence(:documento) { |n| format('***%06d**', n) }
    identificador { ReceitaPartner::PESSOA_FISICA }
    qualificacao { 'Sócio-Administrador' }
    data_entrada_sociedade { Date.new(2019, 3, 4) }
    faixa_etaria { '31 a 40 anos' }
    first_seen_release { '2026-08' }
    last_seen_release { '2026-08' }
  end
end
```

A factory usa `Receita::NameNormalizer`, criado na Task 2. Para esta tarefa passar sozinha, crie já o arquivo mínimo (a Task 2 escreve os testes dele):

```ruby
# app/services/receita/name_normalizer.rb
# frozen_string_literal: true

module Receita
  # Única normalização de nome do repo para casar sociedade, sócio e advogado:
  # sem acento, só letras e espaço, caixa alta, espaços colapsados.
  # Idêntica à que Cnpja::SocietyMatcher usava — ele passa a chamar aqui.
  module NameNormalizer
    def self.call(name)
      ActiveSupport::Inflector.transliterate(name.to_s)
                              .gsub(/[^A-Za-z ]+/, ' ')
                              .strip
                              .upcase
                              .squeeze(' ')
    end
  end
end
```

- [ ] **Step 6: Migrar e rodar o teste**

Run: `bin/rails db:migrate && RAILS_ENV=test bin/rails db:migrate && bundle exec rspec spec/models/receita_company_spec.rb`
Expected: 5 examples, 0 failures. `db/schema.rb` atualizado com as duas tabelas.

- [ ] **Step 7: Commit**

```bash
git add db/migrate/20261006120000_create_receita_companies.rb db/schema.rb app/models/receita_company.rb app/models/receita_partner.rb app/models/society.rb app/models/lawyer.rb app/services/receita/name_normalizer.rb spec/factories/receita_companies.rb spec/factories/receita_partners.rb spec/models/receita_company_spec.rb
git commit -m "feat(receita): tabelas receita_companies e receita_partners

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: `Receita::NameNormalizer` compartilhado e `Receita::Cnpj`

**Files:**
- Modify: `app/services/receita/name_normalizer.rb` (criado na Task 1; só ganha testes)
- Modify: `app/services/cnpja/society_matcher.rb:70-77` (método `normalize` passa a delegar)
- Create: `app/lib/receita/cnpj.rb`
- Test: `spec/services/receita/name_normalizer_spec.rb`, `spec/lib/receita/cnpj_spec.rb`

**Interfaces:**
- Produces: `Receita::NameNormalizer.call(String) -> String`; `Receita::Cnpj.normalize(String) -> String(14) | nil` (nil = inválido); `Receita::Cnpj.valid?(String) -> Boolean`.

- [ ] **Step 1: Testes do normalizador**

```ruby
# spec/services/receita/name_normalizer_spec.rb
require 'rails_helper'

RSpec.describe Receita::NameNormalizer do
  it 'remove acento, pontuação e dígitos, sobe caixa e colapsa espaços' do
    expect(described_class.call("Sant'Anna & Figueirêdo  Advogados 2")).to eq('SANT ANNA FIGUEIREDO ADVOGADOS')
  end

  it 'devolve string vazia para nil' do
    expect(described_class.call(nil)).to eq('')
  end

  it 'é a mesma regra do Cnpja::SocietyMatcher' do
    matcher = Cnpja::SocietyMatcher.allocate
    expect(matcher.send(:normalize, 'José da Silva-Neto')).to eq(described_class.call('José da Silva-Neto'))
  end
end
```

- [ ] **Step 2: Testes do CNPJ**

```ruby
# spec/lib/receita/cnpj_spec.rb
require 'rails_helper'

RSpec.describe Receita::Cnpj do
  describe '.normalize' do
    it 'aceita com máscara e devolve 14 dígitos' do
      expect(described_class.normalize('11.222.333/0001-81')).to eq('11222333000181')
    end

    it 'aceita o CNPJ alfanumérico de 2026 e valida pelo ASCII-48' do
      # Dígitos calculados pela regra oficial (letra vale ord - 48).
      expect(described_class.normalize('12.ABC.345/01DE-35')).to eq('12ABC34501DE35')
    end

    it 'rejeita dígito verificador errado' do
      expect(described_class.normalize('11.222.333/0001-82')).to be_nil
    end

    it 'rejeita tamanho errado e sequência repetida' do
      expect(described_class.normalize('123')).to be_nil
      expect(described_class.normalize('00000000000000')).to be_nil
    end

    it 'rejeita nil' do
      expect(described_class.normalize(nil)).to be_nil
    end
  end
end
```

- [ ] **Step 3: Rodar e ver falhar**

Run: `bundle exec rspec spec/services/receita/name_normalizer_spec.rb spec/lib/receita/cnpj_spec.rb`
Expected: FAIL (`uninitialized constant Receita::Cnpj`; o 3º teste do normalizador passa por acaso, os outros dois passam).

- [ ] **Step 4: Implementar `Receita::Cnpj`**

Confirme que `app/lib` está no autoload (`config/application.rb` — Rails 8 autoloada `app/*` por padrão; se o diretório não existir, criar basta).

```ruby
# app/lib/receita/cnpj.rb
# frozen_string_literal: true

module Receita
  # Normalização e validação de CNPJ, incluindo o formato alfanumérico vigente
  # desde julho de 2026: os 12 primeiros caracteres podem ser letra ou dígito,
  # cada caractere vale `ord - 48` no cálculo, e os 2 verificadores continuam
  # numéricos. Letras sobem para caixa alta antes de validar.
  module Cnpj
    WEIGHTS_FIRST = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2].freeze
    WEIGHTS_SECOND = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2].freeze
    FORMAT = /\A[0-9A-Z]{12}\d{2}\z/

    def self.normalize(input)
      value = input.to_s.gsub(/[^0-9A-Za-z]/, '').upcase
      return nil unless value.match?(FORMAT)
      return nil if value.chars.uniq.size == 1

      valid?(value) ? value : nil
    end

    def self.valid?(value)
      base = value[0, 12].chars.map { |c| c.ord - 48 }
      first = check_digit(base, WEIGHTS_FIRST)
      second = check_digit(base + [first], WEIGHTS_SECOND)
      value[12, 2] == "#{first}#{second}"
    end

    def self.check_digit(values, weights)
      remainder = values.each_with_index.sum { |v, i| v * weights[i] } % 11
      remainder < 2 ? 0 : 11 - remainder
    end
    private_class_method :check_digit
  end
end
```

- [ ] **Step 5: Delegar o `normalize` do `Cnpja::SocietyMatcher`**

Em `app/services/cnpja/society_matcher.rb`, substituir o método privado `normalize` por:

```ruby
    def normalize(name)
      Receita::NameNormalizer.call(name)
    end
```

Não mexer em `lib/tasks/import_mg.rake`: o `mg:normalize_name` mantém dígitos de propósito (índice do lote MG) e não casa com a Receita.

- [ ] **Step 6: Rodar e ver passar**

Run: `bundle exec rspec spec/services/receita/name_normalizer_spec.rb spec/lib/receita/cnpj_spec.rb spec/services/cnpja`
Expected: todos passando. Se o teste alfanumérico falhar por dígito, recalcule os verificadores de `12ABC34501DE` pela função e ajuste o literal do teste — a regra (ord−48) é a que vale.

- [ ] **Step 7: Commit**

```bash
git add app/lib/receita/cnpj.rb app/services/receita/name_normalizer.rb app/services/cnpja/society_matcher.rb spec/services/receita/name_normalizer_spec.rb spec/lib/receita/cnpj_spec.rb
git commit -m "feat(receita): normalizador de nome compartilhado e validação de CNPJ alfanumérico

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: `Receita::RowMapper` e `Receita::Importer` + `rake receita:import`

**Files:**
- Create: `app/services/receita/row_mapper.rb`
- Create: `app/services/receita/importer.rb`
- Create: `lib/tasks/receita.rake` (só a task `import` nesta tarefa; as outras tasks acrescentam)
- Create: `spec/fixtures/receita/advocacia_sample.ndjson`
- Test: `spec/services/receita/row_mapper_spec.rb`, `spec/services/receita/importer_spec.rb`

**Interfaces:**
- Consumes: `Receita::NameNormalizer.call`, models da Task 1.
- Produces: `Receita::RowMapper.company_attrs(record, source:, release:, now:) -> Hash`; `Receita::RowMapper.partner_attrs(record, company_id:, release:, now:) -> Array<Hash>`; `Receita::Importer.new(file:, release:, dry_run: false, logger:).call -> Hash stats` com chaves `:read, :malformed_line, :companies_upserted, :partners_upserted, :skipped_no_cnpj`; `Receita::Importer#import_records(Array<Hash>) -> Integer` (usado pelo lookup da Task 7).

- [ ] **Step 1: Fixture com 6 linhas**

Gerar a partir do dump real para manter o formato idêntico. No Mac:

```bash
cd /Volumes/BPSSD/cnpj-opencnpj/2026-08
# 1 matriz ativa com QSA PF, 1 filial baixada, 1 cartório, 1 sem QSA, 1 com sócio PJ
{ grep -m1 '"matriz_filial":"Matriz","data_inicio_atividade":"20[12]' advocacia_6911701.ndjson | grep '"identificador_socio":"Pessoa F' ;
  grep -m1 '"matriz_filial":"Filial"' advocacia_6911701.ndjson | grep -m1 'Baixada' ;
  grep -m1 'Cart' advocacia_6911701.ndjson ;
  grep -m1 '"QSA":\[\]' advocacia_6911701.ndjson ;
  grep -m1 '"identificador_socio":"Pessoa Jur' advocacia_6911701.ndjson ; } > /Users/brpl/code/ProcStudio/prc_legal_data/spec/fixtures/receita/advocacia_sample.ndjson
echo '{"cnpj":"quebrada' >> /Users/brpl/code/ProcStudio/prc_legal_data/spec/fixtures/receita/advocacia_sample.ndjson
wc -l /Users/brpl/code/ProcStudio/prc_legal_data/spec/fixtures/receita/advocacia_sample.ndjson   # 6
```

Se algum `grep -m1 ... | grep` vier vazio, troque o filtro até cada uma das 5 linhas existir (confira com `python3 -I -c 'import json,sys; [print(json.loads(l)["cnpj"], json.loads(l)["matriz_filial"], json.loads(l)["situacao_cadastral"], len(json.loads(l)["QSA"])) for l in open(sys.argv[1]) if l.startswith("{\"cnpj\":\"0") or l.startswith("{\"cnpj\":\"1") or l.startswith("{\"cnpj\":\"2") or l.startswith("{\"cnpj\":\"3") or l.startswith("{\"cnpj\":\"4") or l.startswith("{\"cnpj\":\"5") or l.startswith("{\"cnpj\":\"6") or l.startswith("{\"cnpj\":\"7") or l.startswith("{\"cnpj\":\"8") or l.startswith("{\"cnpj\":\"9")]' spec/fixtures/receita/advocacia_sample.ndjson`). Anote no teste os CNPJs reais que entraram (lendo a fixture no `before`), em vez de literais.

- [ ] **Step 2: Teste do RowMapper**

```ruby
# spec/services/receita/row_mapper_spec.rb
require 'rails_helper'

RSpec.describe Receita::RowMapper do
  let(:now) { Time.zone.parse('2026-10-06 12:00:00') }
  let(:record) do
    {
      'cnpj' => '49780032000146', 'razao_social' => 'PELLIZZETTI E WALBER ADVOGADOS ASSOCIADOS', 'nome_fantasia' => '',
      'situacao_cadastral' => 'Ativa', 'data_situacao_cadastral' => '2019-03-04', 'matriz_filial' => 'Matriz',
      'data_inicio_atividade' => '2019-03-04', 'cnae_principal' => '6911701',
      'natureza_juridica' => 'Sociedade Simples Pura',
      'tipo_logradouro' => 'RUA', 'logradouro' => 'PARANA', 'numero' => '3056', 'complemento' => 'SALA 2',
      'bairro' => 'CENTRO', 'cep' => '85810010', 'uf' => 'PR', 'municipio' => 'CASCAVEL', 'codigo_municipio' => '7497',
      'email' => 'ADV5898S@GMAIL.COM', 'telefones' => [{ 'ddd' => '45', 'numero' => '30355898', 'is_fax' => false }],
      'capital_social' => '10000,00', 'porte_empresa' => 'Micro Empresa (ME)',
      'opcao_simples' => 'S', 'data_opcao_simples' => '2019-03-04', 'opcao_mei' => 'N',
      'motivo_situacao_cadastral' => { 'codigo' => '00', 'descricao' => 'SEM MOTIVO' },
      'QSA' => [
        { 'nome_socio' => 'BRUNO PELLIZZETTI', 'cnpj_cpf_socio' => '***146406**', 'qualificacao_socio' => 'Sócio-Administrador',
          'data_entrada_sociedade' => '2019-03-04', 'identificador_socio' => 'Pessoa Física', 'faixa_etaria' => '31 a 40 anos' },
        { 'nome_socio' => 'HOLDING X LTDA', 'cnpj_cpf_socio' => '12345678000199', 'qualificacao_socio' => 'Sócio',
          'data_entrada_sociedade' => '', 'identificador_socio' => 'Pessoa Jurídica', 'faixa_etaria' => 'Não se aplica' }
      ]
    }
  end

  describe '.company_attrs' do
    subject(:attrs) { described_class.company_attrs(record, source: 'dump', release: '2026-08', now: now) }

    it 'mapeia campos escalares, normaliza nome e e-mail e converte capital' do
      expect(attrs).to include(
        cnpj: '49780032000146', cnpj_root: '49780032', name_normalized: 'PELLIZZETTI E WALBER ADVOGADOS ASSOCIADOS',
        nome_fantasia: nil, matriz: true, email: 'adv5898s@gmail.com', capital_social: BigDecimal('10000.00'),
        data_inicio_atividade: Date.new(2019, 3, 4), motivo_situacao: 'SEM MOTIVO',
        source: 'dump', release: '2026-08', fetched_at: now, created_at: now, updated_at: now
      )
      expect(attrs[:raw]).to eq(record)
    end

    it 'trata data vazia como nil' do
      record['data_opcao_simples'] = ''
      expect(attrs[:data_opcao_simples]).to be_nil
    end
  end

  describe '.partner_attrs' do
    subject(:rows) { described_class.partner_attrs(record, company_id: 7, release: '2026-08', now: now) }

    it 'gera uma linha por membro do QSA, PF e PJ, com documento como veio' do
      expect(rows.size).to eq(2)
      expect(rows.first).to include(
        receita_company_id: 7, nome_socio: 'BRUNO PELLIZZETTI', name_normalized: 'BRUNO PELLIZZETTI',
        documento: '***146406**', identificador: 'Pessoa Física', qualificacao: 'Sócio-Administrador',
        data_entrada_sociedade: Date.new(2019, 3, 4), first_seen_release: '2026-08', last_seen_release: '2026-08'
      )
      expect(rows.last).to include(documento: '12345678000199', identificador: 'Pessoa Jurídica', data_entrada_sociedade: nil)
    end

    it 'devolve vazio sem QSA' do
      record['QSA'] = []
      expect(rows).to eq([])
    end
  end
end
```

- [ ] **Step 3: Teste do Importer**

```ruby
# spec/services/receita/importer_spec.rb
require 'rails_helper'

RSpec.describe Receita::Importer do
  let(:file) { Rails.root.join('spec/fixtures/receita/advocacia_sample.ndjson') }
  let(:lines) { File.readlines(file).filter_map { |l| JSON.parse(l) rescue nil } }

  it 'importa empresas e sócios, ignora linha malformada e é idempotente' do
    stats = described_class.new(file: file, release: '2026-08', logger: Logger.new(nil)).call

    expect(stats[:read]).to eq(5)
    expect(stats[:malformed_line]).to eq(1)
    expect(ReceitaCompany.count).to eq(5)
    expect(ReceitaCompany.pluck(:cnpj)).to match_array(lines.map { |l| l['cnpj'] })
    expect(ReceitaPartner.count).to eq(lines.sum { |l| l['QSA'].size })
    expect(ReceitaPartner.where(lawyer_id: nil).count).to eq(ReceitaPartner.count) # importador nunca vincula

    expect { described_class.new(file: file, release: '2026-08', logger: Logger.new(nil)).call }
      .not_to(change { [ReceitaCompany.count, ReceitaPartner.count, ReceitaCompany.order(:id).pluck(:updated_at)] })
  end

  it 'em release nova atualiza last_seen_release e preserva first_seen_release e o vínculo com society' do
    described_class.new(file: file, release: '2026-08', logger: Logger.new(nil)).call
    company = ReceitaCompany.first
    society = create(:society)
    company.update_columns(society_id: society.id, match_confidence: 'verified')

    described_class.new(file: file, release: '2026-09', logger: Logger.new(nil)).call

    expect(company.reload.release).to eq('2026-09')
    expect(company.society_id).to eq(society.id)
    expect(company.match_confidence).to eq('verified')
    expect(ReceitaPartner.pluck(:first_seen_release).uniq).to eq(['2026-08'])
    expect(ReceitaPartner.pluck(:last_seen_release).uniq).to eq(['2026-09'])
  end

  it 'sócio que saiu do QSA fica com last_seen_release antigo' do
    described_class.new(file: file, release: '2026-08', logger: Logger.new(nil)).call
    with_qsa = lines.find { |l| l['QSA'].any? }
    Tempfile.create(['dump', '.ndjson']) do |f|
      f.puts(with_qsa.merge('QSA' => []).to_json)
      f.flush
      described_class.new(file: f.path, release: '2026-09', logger: Logger.new(nil)).call
    end
    company = ReceitaCompany.find_by!(cnpj: with_qsa['cnpj'])
    expect(company.receita_partners.count).to eq(with_qsa['QSA'].size)
    expect(company.current_partners.count).to eq(0)
  end

  it 'DRY_RUN não grava nada' do
    stats = described_class.new(file: file, release: '2026-08', dry_run: true, logger: Logger.new(nil)).call
    expect(stats[:read]).to eq(5)
    expect(ReceitaCompany.count).to eq(0)
  end
end
```

- [ ] **Step 4: Rodar e ver falhar**

Run: `bundle exec rspec spec/services/receita/row_mapper_spec.rb spec/services/receita/importer_spec.rb`
Expected: FAIL com `uninitialized constant Receita::RowMapper`

- [ ] **Step 5: Implementar RowMapper**

```ruby
# app/services/receita/row_mapper.rb
# frozen_string_literal: true

module Receita
  # Traduz uma linha do dump OpenCNPJ (ou a resposta da API pública, que tem o
  # mesmo formato) para os atributos de ReceitaCompany e ReceitaPartner.
  # Puro: sem banco, sem efeito colateral. Usado pelo Importer e pelo CnpjLookup.
  module RowMapper
    COMPANY_UPDATE_COLUMNS = %i[
      cnpj_root razao_social nome_fantasia name_normalized situacao_cadastral data_situacao_cadastral
      motivo_situacao matriz data_inicio_atividade cnae_principal natureza_juridica tipo_logradouro logradouro
      numero complemento bairro cep uf municipio codigo_municipio email telefones capital_social porte_empresa
      opcao_simples data_opcao_simples opcao_mei raw source release fetched_at updated_at
    ].freeze

    PARTNER_UPDATE_COLUMNS = %i[nome_socio qualificacao data_entrada_sociedade faixa_etaria identificador last_seen_release updated_at].freeze

    def self.company_attrs(record, source:, release:, now:)
      cnpj = record['cnpj'].to_s
      {
        cnpj: cnpj,
        cnpj_root: cnpj[0, 8],
        razao_social: blank_to_nil(record['razao_social']),
        nome_fantasia: blank_to_nil(record['nome_fantasia']),
        name_normalized: NameNormalizer.call(record['razao_social']).presence,
        situacao_cadastral: blank_to_nil(record['situacao_cadastral']),
        data_situacao_cadastral: parse_date(record['data_situacao_cadastral']),
        motivo_situacao: blank_to_nil(record.dig('motivo_situacao_cadastral', 'descricao')),
        matriz: record['matriz_filial'] != 'Filial',
        data_inicio_atividade: parse_date(record['data_inicio_atividade']),
        cnae_principal: blank_to_nil(record['cnae_principal']),
        natureza_juridica: blank_to_nil(record['natureza_juridica']),
        tipo_logradouro: blank_to_nil(record['tipo_logradouro']),
        logradouro: blank_to_nil(record['logradouro']),
        numero: blank_to_nil(record['numero']),
        complemento: blank_to_nil(record['complemento']),
        bairro: blank_to_nil(record['bairro']),
        cep: blank_to_nil(record['cep']),
        uf: blank_to_nil(record['uf']),
        municipio: blank_to_nil(record['municipio']),
        codigo_municipio: blank_to_nil(record['codigo_municipio']),
        email: blank_to_nil(record['email'])&.downcase,
        telefones: Array(record['telefones']),
        capital_social: parse_decimal(record['capital_social']),
        porte_empresa: blank_to_nil(record['porte_empresa']),
        opcao_simples: blank_to_nil(record['opcao_simples']),
        data_opcao_simples: parse_date(record['data_opcao_simples']),
        opcao_mei: blank_to_nil(record['opcao_mei']),
        raw: record,
        source: source,
        release: release,
        fetched_at: now,
        created_at: now,
        updated_at: now
      }
    end

    def self.partner_attrs(record, company_id:, release:, now:)
      Array(record['QSA']).map do |member|
        {
          receita_company_id: company_id,
          nome_socio: blank_to_nil(member['nome_socio']),
          name_normalized: NameNormalizer.call(member['nome_socio']),
          documento: member['cnpj_cpf_socio'].to_s,
          identificador: blank_to_nil(member['identificador_socio']),
          qualificacao: blank_to_nil(member['qualificacao_socio']),
          data_entrada_sociedade: parse_date(member['data_entrada_sociedade']),
          faixa_etaria: blank_to_nil(member['faixa_etaria']),
          first_seen_release: release,
          last_seen_release: release,
          created_at: now,
          updated_at: now
        }
      end
    end

    def self.blank_to_nil(value)
      v = value.to_s.strip
      v.empty? ? nil : v
    end

    def self.parse_date(value)
      return nil if value.to_s.strip.empty?

      Date.iso8601(value.to_s)
    rescue Date::Error
      nil
    end

    # "4800,00" -> 4800.00 ; "" -> nil
    def self.parse_decimal(value)
      v = value.to_s.strip
      return nil if v.empty?

      BigDecimal(v.delete('.').tr(',', '.'))
    rescue ArgumentError
      nil
    end
  end
end
```

- [ ] **Step 6: Implementar Importer**

```ruby
# app/services/receita/importer.rb
# frozen_string_literal: true

module Receita
  # Importa um NDJSON do OpenCNPJ em receita_companies/receita_partners.
  #
  # Idempotente por (cnpj) e (empresa, nome normalizado, documento): rodar a
  # mesma release duas vezes não muda nada. Em release nova, a empresa é
  # sobrescrita (menos society_id/match_confidence/matched_at, que são nossos),
  # e os sócios ganham last_seen_release; quem saiu do QSA fica com a release
  # antiga — é assim que se enxerga mudança de quadro societário.
  #
  # Mesmo esqueleto de lib/tasks/import_mg.rake: fatias, uma transação por
  # fatia, linha malformada contada e ignorada.
  class Importer
    SLICE = 2000

    def initialize(file:, release:, dry_run: false, logger: Rails.logger, source: ReceitaCompany::SOURCE_DUMP)
      @file = file
      @release = release
      @dry_run = dry_run
      @logger = logger
      @source = source
      @stats = Hash.new(0)
    end

    def call
      @logger.info("Receita::Importer: lendo #{@file} release=#{@release}#{@dry_run ? ' (DRY RUN)' : ''}")

      File.foreach(@file).each_slice(SLICE) do |lines|
        records = lines.filter_map { |line| parse(line) }
        next if records.empty? || @dry_run

        import_records(records)
        @logger.info("Receita::Importer: #{@stats[:read]} lidas, #{@stats[:companies_upserted]} empresas")
      end

      @stats
    end

    # Grava um lote de registros já parseados. Devolve quantas empresas foram
    # gravadas. Público porque o CnpjLookup reaproveita para a linha da API.
    def import_records(records)
      now = Time.current
      records = records.select { |r| r['cnpj'].to_s.length == 14 }.uniq { |r| r['cnpj'] }
      return 0 if records.empty?

      ActiveRecord::Base.transaction do
        companies = records.map { |r| RowMapper.company_attrs(r, source: @source, release: @release, now: now) }
        ReceitaCompany.upsert_all(companies, unique_by: :index_receita_companies_on_cnpj,
                                             update_only: RowMapper::COMPANY_UPDATE_COLUMNS)
        @stats[:companies_upserted] += companies.size

        ids = ReceitaCompany.where(cnpj: records.map { |r| r['cnpj'] }).pluck(:cnpj, :id).to_h
        partners = records.flat_map { |r| RowMapper.partner_attrs(r, company_id: ids.fetch(r['cnpj']), release: @release, now: now) }
        partners.uniq! { |p| [p[:receita_company_id], p[:name_normalized], p[:documento]] }
        if partners.any?
          ReceitaPartner.upsert_all(partners, unique_by: :index_receita_partners_unique_member,
                                              update_only: RowMapper::PARTNER_UPDATE_COLUMNS)
          @stats[:partners_upserted] += partners.size
        end
      end

      records.size
    end

    private

    def parse(line)
      line = line.strip
      return nil if line.empty?

      record = JSON.parse(line)
      @stats[:read] += 1
      if record['cnpj'].to_s.length != 14
        @stats[:skipped_no_cnpj] += 1
        return nil
      end
      record
    rescue JSON::ParserError => e
      @stats[:malformed_line] += 1
      @logger.warn("Receita::Importer: linha malformada ignorada: #{e.message[0, 80]}")
      nil
    end
  end
end
```

Atenção ao teste de idempotência: `upsert_all` com `update_only` ainda escreve `updated_at` se ele estiver na lista. Para que a segunda rodada da mesma release não mude `updated_at`, use em `upsert_all` de empresas a cláusula `on_duplicate: Arel.sql(...)`? Não: mais simples e previsível é **filtrar antes**: em `import_records`, remova dos `records` os que já existem com `release == @release` e `source == @source`:

```ruby
      existing = ReceitaCompany.where(cnpj: records.map { |r| r['cnpj'] }, release: @release, source: @source).pluck(:cnpj).to_set
      records = records.reject { |r| existing.include?(r['cnpj']) }
      @stats[:companies_unchanged] += existing.size
      return 0 if records.empty?
```

Coloque isso logo após o `uniq`, antes da transação.

- [ ] **Step 7: Rake task**

```ruby
# lib/tasks/receita.rake
# frozen_string_literal: true

# Receita Federal via dump OpenCNPJ (recorte CNAE 6911701, advocacia).
#
#   bundle exec rake receita:import FILE=storage/receita/2026-08/advocacia.ndjson RELEASE=2026-08 [DRY_RUN=true]
#
# Spec: docs/superpowers/specs/2026-10-06-receita-cnpj-enrichment-design.md §5
namespace :receita do
  desc 'Importa um NDJSON do OpenCNPJ em receita_companies/receita_partners'
  task import: :environment do
    file = ENV.fetch('FILE')
    release = ENV.fetch('RELEASE')
    dry_run = ENV['DRY_RUN'] == 'true'

    stats = Receita::Importer.new(file: file, release: release, dry_run: dry_run, logger: Logger.new($stdout)).call
    puts "FIM import release=#{release} #{stats.map { |k, v| "#{k}=#{v}" }.join(' ')}"
  end
end
```

- [ ] **Step 8: Rodar e ver passar**

Run: `bundle exec rspec spec/services/receita/row_mapper_spec.rb spec/services/receita/importer_spec.rb`
Expected: todos passando. Se o teste de idempotência falhar em `updated_at`, confirme que o filtro `existing` do Step 6 está antes da transação.

- [ ] **Step 9: Importar de verdade no banco local e medir**

Run: `time bundle exec rake receita:import FILE=/Volumes/BPSSD/cnpj-opencnpj/2026-08/advocacia_6911701.ndjson RELEASE=2026-08`
Expected: `read=261347`, `companies_upserted=261347`, `partners_upserted≈400000`, sem exceção, em menos de 15 minutos. Anote o tempo no commit.

- [ ] **Step 10: Commit**

```bash
git add app/services/receita/row_mapper.rb app/services/receita/importer.rb lib/tasks/receita.rake spec/fixtures/receita/advocacia_sample.ndjson spec/services/receita/row_mapper_spec.rb spec/services/receita/importer_spec.rb
git commit -m "feat(receita): importador idempotente do recorte de advocacia do OpenCNPJ

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: `Receita::SocietyMatcher` + `rake receita:match_societies`

**Files:**
- Create: `app/services/receita/society_matcher.rb`
- Modify: `lib/tasks/receita.rake` (adicionar task `match_societies`)
- Test: `spec/services/receita/society_matcher_spec.rb`

**Interfaces:**
- Consumes: models da Task 1, `Receita::NameNormalizer`.
- Produces: `Receita::SocietyMatcher.new(state:, release:, dry_run: false, logger:).call -> Hash stats` com chaves `:societies, :verified, :verified_exact_name, :verified_partners_only, :ambiguous, :ambiguous_cnpj_taken, :unmatched, :no_lawyers, :already_verified`. Efeitos: `societies.cnpj`, `societies.cnpja_match_confidence`, `societies.cnpja_synced_at`, `receita_companies.society_id/match_confidence/matched_at`, `receita_partners.lawyer_id`.

- [ ] **Step 1: Testes com os casos do PLANO-CNPJA**

```ruby
# spec/services/receita/society_matcher_spec.rb
require 'rails_helper'

RSpec.describe Receita::SocietyMatcher do
  let(:release) { '2026-08' }
  let(:logger) { Logger.new(nil) }

  def society_with(name, *lawyer_names, state: 'PR')
    society = create(:society, name: name, state: state)
    lawyer_names.each do |ln|
      lawyer = create(:lawyer, full_name: ln, state: state)
      create(:lawyer_society, society: society, lawyer: lawyer)
    end
    society
  end

  def firm(name, *partner_names, cnpj: nil, uf: 'PR', matriz: true, situacao: 'Ativa')
    attrs = { razao_social: name, uf: uf, matriz: matriz, situacao_cadastral: situacao, release: release }
    attrs[:cnpj] = cnpj if cnpj
    company = create(:receita_company, **attrs)
    partner_names.each { |pn| create(:receita_partner, receita_company: company, nome_socio: pn, last_seen_release: release) }
    company
  end

  def run(state = 'PR')
    described_class.new(state: state, release: release, logger: logger).call
  end

  it 'nome igual e um sócio batendo -> verified, grava cnpj e vincula o sócio ao advogado' do
    society = society_with('LEON ADVOGADOS ASSOCIADOS', 'ESDRAS LEON', 'ISABELA LEON')
    company = firm('LEON ADVOGADOS ASSOCIADOS', 'ESDRAS LEON', 'OUTRO SOCIO')

    stats = run
    expect(stats[:verified]).to eq(1)
    expect(society.reload.cnpj).to eq(company.cnpj)
    expect(society.cnpja_match_confidence).to eq('verified')
    expect(company.reload.society_id).to eq(society.id)
    expect(company.receita_partners.find_by(nome_socio: 'ESDRAS LEON').lawyer.full_name).to eq('ESDRAS LEON')
    expect(company.receita_partners.find_by(nome_socio: 'OUTRO SOCIO').lawyer_id).to be_nil
  end

  it 'caso LEON: nome igual e sócios totalmente diferentes -> unmatched' do
    society = society_with('LEON ADVOGADOS ASSOCIADOS', 'ESDRAS LEON', 'ISABELA LEON')
    firm('LEON ADVOGADOS ASSOCIADOS', 'OVIDIO LEON', 'JAQUELINE LEON')

    expect(run[:unmatched]).to eq(1)
    expect(society.reload.cnpj).to be_nil
  end

  it 'caso FIGUEIRERO: nome da firma diferente mas dois sócios batendo -> verified' do
    society = society_with('FIGUEIREDO E SILVA ADVOGADOS', 'EVANES CESAR FIGUEIREDO', 'MARIA SILVA')
    company = firm('FIGUEIRERO E SILVA ADVOGADOS', 'EVANES CESAR FIGUEIREDO', 'MARIA SILVA')

    stats = run
    expect(stats[:verified_partners_only]).to eq(1)
    expect(society.reload.cnpj).to eq(company.cnpj)
  end

  it 'nome diferente e só um sócio batendo -> unmatched (homônimo em outra firma)' do
    society_with('A E B ADVOGADOS', 'JOAO DA SILVA', 'PEDRO ALVES')
    firm('C E D ADVOCACIA', 'JOAO DA SILVA', 'LUCAS ROCHA')

    expect(run[:unmatched]).to eq(1)
  end

  it 'caso DANIELA HUDSON: matriz ativa e filial baixada da mesma raiz -> verified na matriz' do
    society = society_with('DANIELA HUDSON ADVOGADOS', 'DANIELA HUDSON')
    matriz = firm('DANIELA HUDSON ADVOGADOS', 'DANIELA HUDSON', cnpj: '11222333000181', matriz: true)
    firm('DANIELA HUDSON ADVOGADOS', 'DANIELA HUDSON', cnpj: '11222333000262', matriz: false, situacao: 'Baixada')

    expect(run[:verified]).to eq(1)
    expect(society.reload.cnpj).to eq(matriz.cnpj)
  end

  it 'duas raízes de CNPJ com sócio em comum -> ambiguous, nada gravado em cnpj' do
    society = society_with('GRUPO X ADVOGADOS', 'FULANO X')
    firm('GRUPO X ADVOGADOS', 'FULANO X', cnpj: '11222333000181')
    firm('GRUPO X ADVOGADOS', 'FULANO X', cnpj: '12345678000195')

    expect(run[:ambiguous]).to eq(1)
    expect(society.reload.cnpj).to be_nil
    expect(society.cnpja_match_confidence).to eq('ambiguous')
    expect(ReceitaCompany.where(match_confidence: 'ambiguous').count).to eq(2)
  end

  it 'associado fora do QSA não derruba o match' do
    society = society_with('OLIVIERI CARVALHO E LIEVORI', 'A OLIVIERI', 'B CARVALHO', 'C LIEVORI', 'D ASSOCIADO')
    firm('OLIVIERI CARVALHO E LIEVORI', 'A OLIVIERI', 'B CARVALHO', 'C LIEVORI')

    expect(run[:verified]).to eq(1)
    expect(society.reload.cnpj).to be_present
  end

  it 'segunda sociedade casando a mesma firma vira ambiguous cnpj_taken em vez de estourar o unique' do
    first = society_with('DUPLA ADVOGADOS', 'SOCIO UM')
    second = society_with('DUPLA ADVOGADOS', 'SOCIO UM')
    company = firm('DUPLA ADVOGADOS', 'SOCIO UM')

    stats = run
    expect(stats[:verified]).to eq(1)
    expect(stats[:ambiguous_cnpj_taken]).to eq(1)
    expect([first.reload.cnpj, second.reload.cnpj].compact).to eq([company.cnpj])
    expect([first.cnpja_match_confidence, second.cnpja_match_confidence]).to contain_exactly('verified', 'ambiguous')
  end

  it 'sociedade já verified só ganha cnpja_synced_at novo' do
    society = society_with('JA CASADA ADVOGADOS', 'SOCIO UM')
    company = firm('JA CASADA ADVOGADOS', 'SOCIO UM')
    society.update_columns(cnpj: company.cnpj, cnpja_match_confidence: 'verified', cnpja_synced_at: 1.month.ago)

    stats = run
    expect(stats[:already_verified]).to eq(1)
    expect(society.reload.cnpja_synced_at).to be > 1.minute.ago
  end

  it 'ignora firma de outra UF e sociedade sem advogados' do
    create(:society, name: 'SEM SOCIOS', state: 'PR')
    society_with('FORA DA UF ADVOGADOS', 'SOCIO UM')
    firm('FORA DA UF ADVOGADOS', 'SOCIO UM', uf: 'SP')

    stats = run
    expect(stats[:no_lawyers]).to eq(1)
    expect(stats[:unmatched]).to eq(1)
  end

  it 'dry_run não grava' do
    society = society_with('DRY ADVOGADOS', 'SOCIO UM')
    firm('DRY ADVOGADOS', 'SOCIO UM')

    stats = described_class.new(state: 'PR', release: release, dry_run: true, logger: logger).call
    expect(stats[:verified]).to eq(1)
    expect(society.reload.cnpj).to be_nil
  end
end
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `bundle exec rspec spec/services/receita/society_matcher_spec.rb`
Expected: FAIL com `uninitialized constant Receita::SocietyMatcher`

- [ ] **Step 3: Implementar**

```ruby
# app/services/receita/society_matcher.rb
# frozen_string_literal: true

module Receita
  # Casa Society (OAB) com ReceitaCompany, 100% offline, por UF.
  #
  # Regras herdadas do PLANO-CNPJA.md §2 (cada uma custou um caso real):
  #   - nome igual NÃO basta (LEON): precisa de sócio batendo;
  #   - nome igual não é obrigatório (FIGUEIRERO): 2+ sócios batendo bastam;
  #   - autoridade = sobreposição de nome de sócio; nome da firma é pista;
  #   - contagem de sócios não é critério (associado não entra no QSA);
  #   - matriz e filial são a MESMA raiz de CNPJ: escolhe a matriz ativa;
  #   - raízes diferentes com sócio comum: ambiguous, humano decide.
  #
  # Só verified grava societies.cnpj. Nunca promove ambiguous.
  class SocietyMatcher
    VERIFIED = 'verified'
    AMBIGUOUS = 'ambiguous'
    UNMATCHED = 'unmatched'
    MIN_PARTNERS_WITHOUT_NAME = 2

    Candidate = Struct.new(:id, :cnpj, :root, :name, :matriz, :ativa, :partners, keyword_init: true)

    def initialize(state:, release:, dry_run: false, logger: Rails.logger)
      @state = state.to_s.upcase
      @release = release
      @dry_run = dry_run
      @logger = logger
      @stats = Hash.new(0)
    end

    def call
      load_companies
      taken_cnpjs = Society.where.not(cnpj: nil).pluck(:cnpj).to_set

      Society.where(state: @state).includes(:lawyers).find_each do |society|
        @stats[:societies] += 1
        lawyer_names = society.lawyers.each_with_object({}) do |l, h|
          key = NameNormalizer.call(l.full_name)
          next if key.empty?

          # Dois advogados da mesma sociedade com o mesmo nome normalizado: não dá
          # para saber qual é qual, então nenhum recebe o vínculo.
          h[key] = h.key?(key) ? nil : l.id
        end
        next @stats[:no_lawyers] += 1 if lawyer_names.empty?

        if society.cnpja_match_confidence == VERIFIED && society.cnpj.present?
          @stats[:already_verified] += 1
          touch_synced(society)
          next
        end

        decide(society, lawyer_names, taken_cnpjs)
      end

      @logger.info("Receita::SocietyMatcher #{@state}: #{@stats.map { |k, v| "#{k}=#{v}" }.join(' ')}")
      @stats
    end

    private

    # Índices em memória da UF: por nome da firma e por nome de sócio PF.
    def load_companies
      @by_id = {}
      @by_name = Hash.new { |h, k| h[k] = [] }
      @by_partner = Hash.new { |h, k| h[k] = [] }

      ReceitaCompany.where(uf: @state).from_dump
                    .pluck(:id, :cnpj, :cnpj_root, :name_normalized, :matriz, :situacao_cadastral)
                    .each do |id, cnpj, root, name, matriz, situacao|
        c = Candidate.new(id: id, cnpj: cnpj, root: root, name: name, matriz: matriz, ativa: situacao == 'Ativa', partners: {})
        @by_id[id] = c
        @by_name[name] << c if name.present?
      end

      ReceitaPartner.pessoa_fisica
                    .where(receita_company_id: @by_id.keys, last_seen_release: @release)
                    .pluck(:receita_company_id, :name_normalized, :id)
                    .each do |company_id, name, partner_id|
        next if name.blank?

        c = @by_id[company_id]
        c.partners[name] = partner_id
        @by_partner[name] << c
      end
    end

    def decide(society, lawyer_names, taken_cnpjs)
      society_name = NameNormalizer.call(society.name)
      candidates = @by_name[society_name].to_set
      lawyer_names.each_key { |n| candidates.merge(@by_partner[n]) }

      strong = candidates.filter_map do |c|
        hits = c.partners.keys & lawyer_names.keys
        next if hits.empty?
        next unless c.name == society_name || hits.size >= MIN_PARTNERS_WITHOUT_NAME

        [c, hits]
      end

      if strong.empty?
        @stats[:unmatched] += 1
        return
      end

      roots = strong.map { |c, _| c.root }.uniq
      if roots.size > 1
        mark_ambiguous(society, strong.map(&:first))
        return
      end

      pick, hits = strong.min_by { |c, _| [c.matriz ? 0 : 1, c.ativa ? 0 : 1, c.cnpj] }
      if taken_cnpjs.include?(pick.cnpj)
        @stats[:ambiguous_cnpj_taken] += 1
        mark_ambiguous(society, [pick])
        return
      end

      taken_cnpjs << pick.cnpj
      @stats[:verified] += 1
      @stats[pick.name == society_name ? :verified_exact_name : :verified_partners_only] += 1
      write_verified(society, pick, hits, lawyer_names)
    end

    def write_verified(society, pick, hits, lawyer_names)
      return if @dry_run

      now = Time.current
      ActiveRecord::Base.transaction do
        society.update_columns(cnpj: pick.cnpj, cnpja_match_confidence: VERIFIED, cnpja_synced_at: now)
        ReceitaCompany.where(id: pick.id).update_all(society_id: society.id, match_confidence: VERIFIED, matched_at: now)
        hits.each do |name|
          lawyer_id = lawyer_names[name]
          next if lawyer_id.nil?

          ReceitaPartner.where(id: pick.partners[name]).update_all(lawyer_id: lawyer_id)
        end
      end
    end

    def mark_ambiguous(society, companies)
      @stats[:ambiguous] += 1
      return if @dry_run

      now = Time.current
      society.update_columns(cnpja_match_confidence: AMBIGUOUS, cnpja_synced_at: now)
      ReceitaCompany.where(id: companies.map(&:id), society_id: nil).update_all(match_confidence: AMBIGUOUS, matched_at: now)
    end

    def touch_synced(society)
      return if @dry_run

      society.update_columns(cnpja_synced_at: Time.current)
    end
  end
end
```

- [ ] **Step 4: Rake task**

Acrescentar em `lib/tasks/receita.rake`, dentro do `namespace :receita`:

```ruby
  desc 'Casa sociedades OAB com estabelecimentos da Receita (STATE=PR ou todos) e grava cnpj só com verified'
  task match_societies: :environment do
    release = ENV.fetch('RELEASE')
    dry_run = ENV['DRY_RUN'] == 'true'
    states = ENV['STATE'].present? ? [ENV['STATE'].upcase] : Society.distinct.pluck(:state).compact.sort

    total = Hash.new(0)
    states.each do |state|
      stats = Receita::SocietyMatcher.new(state: state, release: release, dry_run: dry_run, logger: Logger.new($stdout)).call
      stats.each { |k, v| total[k] += v }
    end
    puts "FIM match release=#{release} #{total.map { |k, v| "#{k}=#{v}" }.join(' ')}"
  end
```

- [ ] **Step 5: Rodar e ver passar**

Run: `bundle exec rspec spec/services/receita/society_matcher_spec.rb`
Expected: 11 examples, 0 failures.

- [ ] **Step 6: Rodar contra o banco local (dry run e depois real)**

Run: `bundle exec rake receita:match_societies RELEASE=2026-08 DRY_RUN=true`
Expected: `verified` perto de 148.000, `ambiguous` perto de 2.000 (spike: 148.140 / 1.952). Diferença acima de 2% em `verified` indica bug: parar e comparar com `/private/tmp/.../scratchpad/spike/verified.json` da sessão de brainstorming.

Run: `bundle exec rake receita:match_societies RELEASE=2026-08`
Expected: mesmos números gravados. `psql -h localhost -U postgres -d legal_data_api_development -Atc "select count(*) from societies where cnpj is not null"` ≈ 148.000.

- [ ] **Step 7: Commit**

```bash
git add app/services/receita/society_matcher.rb lib/tasks/receita.rake spec/services/receita/society_matcher_spec.rb
git commit -m "feat(receita): matcher offline sociedade OAB x estabelecimento da Receita

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: `Receita::PartnerLinker` + `rake receita:link_partners`

**Files:**
- Create: `app/services/receita/partner_linker.rb`
- Modify: `lib/tasks/receita.rake`
- Test: `spec/services/receita/partner_linker_spec.rb`

**Interfaces:**
- Produces: `Receita::PartnerLinker.new(state:, release:, dry_run: false, logger:).call -> Hash stats` com `:candidates, :linked, :homonym_skipped, :no_lawyer`.

- [ ] **Step 1: Testes**

```ruby
# spec/services/receita/partner_linker_spec.rb
require 'rails_helper'

RSpec.describe Receita::PartnerLinker do
  let(:release) { '2026-08' }

  def run
    described_class.new(state: 'PR', release: release, logger: Logger.new(nil)).call
  end

  it 'liga sócio PF a advogado principal com nome único na UF' do
    lawyer = create(:lawyer, full_name: 'Ana Beatriz Rocha', state: 'PR')
    company = create(:receita_company, uf: 'PR', release: release)
    partner = create(:receita_partner, receita_company: company, nome_socio: 'ANA BEATRIZ ROCHA', last_seen_release: release)

    expect(run[:linked]).to eq(1)
    expect(partner.reload.lawyer_id).to eq(lawyer.id)
  end

  it 'não liga homônimo na mesma UF' do
    create(:lawyer, full_name: 'JOAO DA SILVA', state: 'PR')
    create(:lawyer, full_name: 'João da Silva', state: 'PR')
    company = create(:receita_company, uf: 'PR', release: release)
    partner = create(:receita_partner, receita_company: company, nome_socio: 'JOAO DA SILVA', last_seen_release: release)

    stats = run
    expect(stats[:homonym_skipped]).to eq(1)
    expect(partner.reload.lawyer_id).to be_nil
  end

  it 'ignora advogado suplementar, sócio PJ, sócio de outra UF e sócio já vinculado' do
    principal = create(:lawyer, full_name: 'CARLA MENDES', state: 'PR')
    create(:lawyer, full_name: 'CARLA MENDES', state: 'PR', principal_lawyer: principal, suplementary: true)
    company = create(:receita_company, uf: 'PR', release: release)
    pf = create(:receita_partner, receita_company: company, nome_socio: 'CARLA MENDES', last_seen_release: release)
    pj = create(:receita_partner, receita_company: company, nome_socio: 'CARLA MENDES LTDA', identificador: 'Pessoa Jurídica', last_seen_release: release)
    sp = create(:receita_partner, receita_company: create(:receita_company, uf: 'SP', release: release), nome_socio: 'CARLA MENDES', last_seen_release: release)
    already = create(:receita_partner, receita_company: company, nome_socio: 'OUTRA PESSOA', lawyer: create(:lawyer, state: 'PR'), last_seen_release: release)

    stats = run
    expect(stats[:linked]).to eq(1)
    expect(pf.reload.lawyer_id).to eq(principal.id)
    expect([pj, sp].map { |p| p.reload.lawyer_id }).to eq([nil, nil])
    expect(already.reload.lawyer_id).not_to eq(principal.id)
  end
end
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `bundle exec rspec spec/services/receita/partner_linker_spec.rb`
Expected: FAIL com `uninitialized constant Receita::PartnerLinker`

- [ ] **Step 3: Implementar**

```ruby
# app/services/receita/partner_linker.rb
# frozen_string_literal: true

module Receita
  # Liga sócio PF (ainda sem lawyer_id) ao advogado PRINCIPAL da mesma UF cujo
  # nome normalizado é único. Homônimo na UF => sem vínculo (melhor sem do que
  # errado). Complementa o SocietyMatcher para firmas que NÃO são sociedade OAB
  # nossa (prospects), onde não há sociedade para dar autoridade.
  class PartnerLinker
    def initialize(state:, release:, dry_run: false, logger: Rails.logger)
      @state = state.to_s.upcase
      @release = release
      @dry_run = dry_run
      @logger = logger
      @stats = Hash.new(0)
    end

    def call
      index = lawyer_index

      ReceitaPartner.pessoa_fisica.unlinked
                    .joins(:receita_company)
                    .where(receita_companies: { uf: @state }, last_seen_release: @release)
                    .where.not(name_normalized: [nil, ''])
                    .in_batches(of: 5000) do |batch|
        updates = Hash.new { |h, k| h[k] = [] }
        batch.pluck(:id, :name_normalized).each do |partner_id, name|
          @stats[:candidates] += 1
          ids = index[name]
          if ids.nil?
            @stats[:no_lawyer] += 1
          elsif ids.size > 1
            @stats[:homonym_skipped] += 1
          else
            updates[ids.first] << partner_id
          end
        end
        next if @dry_run

        updates.each { |lawyer_id, partner_ids| ReceitaPartner.where(id: partner_ids).update_all(lawyer_id: lawyer_id) }
        @stats[:linked] += updates.values.sum(&:size)
      end

      @logger.info("Receita::PartnerLinker #{@state}: #{@stats.map { |k, v| "#{k}=#{v}" }.join(' ')}")
      @stats
    end

    private

    # nome normalizado -> [ids de advogado principal] na UF
    def lawyer_index
      index = Hash.new { |h, k| h[k] = [] }
      Lawyer.where(state: @state, principal_lawyer_id: nil).pluck(:id, :full_name).each do |id, full_name|
        key = NameNormalizer.call(full_name)
        index[key] << id unless key.empty?
      end
      index
    end
  end
end
```

- [ ] **Step 4: Rake task**

Acrescentar em `lib/tasks/receita.rake`:

```ruby
  desc 'Liga sócios PF a advogados principais com nome único na UF (prospects)'
  task link_partners: :environment do
    release = ENV.fetch('RELEASE')
    dry_run = ENV['DRY_RUN'] == 'true'
    states = ENV['STATE'].present? ? [ENV['STATE'].upcase] : ReceitaCompany.distinct.pluck(:uf).compact.sort

    total = Hash.new(0)
    states.each do |state|
      stats = Receita::PartnerLinker.new(state: state, release: release, dry_run: dry_run, logger: Logger.new($stdout)).call
      stats.each { |k, v| total[k] += v }
    end
    puts "FIM link release=#{release} #{total.map { |k, v| "#{k}=#{v}" }.join(' ')}"
  end
```

- [ ] **Step 5: Rodar e ver passar; rodar no banco local**

Run: `bundle exec rspec spec/services/receita/partner_linker_spec.rb` → 3 examples, 0 failures.
Run: `bundle exec rake receita:link_partners RELEASE=2026-08` → `linked` na casa de dezenas de milhares (spike: 59.016 prospects com sócio conhecido).

- [ ] **Step 6: Commit**

```bash
git add app/services/receita/partner_linker.rb lib/tasks/receita.rake spec/services/receita/partner_linker_spec.rb
git commit -m "feat(receita): vínculo sócio PF -> advogado por nome único na UF

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: `ReceitaCompanySerializer` e bloco Receita no payload do advogado

**Files:**
- Create: `app/serializers/receita_company_serializer.rb`
- Modify: `app/serializers/lawyer_serializer.rb:60-83` (`society_attributes`)
- Modify: `app/controllers/api/v1/lawyers_controller.rb:164,192,197` (eager load)
- Test: `spec/serializers/receita_company_serializer_spec.rb`, `spec/serializers/lawyer_serializer_spec.rb` (criar se não existir; se existir, acrescentar o `describe`)

**Interfaces:**
- Produces: `ReceitaCompanySerializer.new(company).receita_block -> Hash`, `#partners_block -> Array<Hash>`, `#as_json -> Hash` (identidade + receita_block + `partners`). Campos exatos abaixo; o ProcStudio (PR 2) e o FFD (PR 3) leem estes nomes.

- [ ] **Step 1: Teste do serializer**

```ruby
# spec/serializers/receita_company_serializer_spec.rb
require 'rails_helper'

RSpec.describe ReceitaCompanySerializer do
  let(:company) { create(:receita_company, cnpj: '49780032000146', razao_social: 'PELLIZZETTI E WALBER ADVOGADOS ASSOCIADOS', complemento: 'SALA 2', release: '2026-08') }
  let(:lawyer) { create(:lawyer, oab_id: 'PR_54159', state: 'PR') }

  before do
    create(:receita_partner, receita_company: company, nome_socio: 'BRUNO PELLIZZETTI', lawyer: lawyer, last_seen_release: '2026-08')
    create(:receita_partner, receita_company: company, nome_socio: 'FULANO WALBER', qualificacao: 'Sócio com Capital', last_seen_release: '2026-08')
    create(:receita_partner, receita_company: company, nome_socio: 'SAIU DA FIRMA', last_seen_release: '2026-07')
  end

  it 'monta o bloco receita com endereço estruturado e capital como string decimal' do
    block = described_class.new(company).receita_block
    expect(block).to eq(
      situacao_cadastral: 'Ativa', data_situacao_cadastral: nil, data_inicio_atividade: '2019-03-04',
      natureza_juridica: 'Sociedade Simples Pura', capital_social: '10000.00', porte_empresa: 'Micro Empresa (ME)',
      opcao_simples: 'S', opcao_mei: nil, email: 'contato@firma.adv.br',
      telefones: [{ 'ddd' => '45', 'numero' => '30355898', 'is_fax' => false }],
      endereco: { tipo_logradouro: 'RUA', logradouro: 'PARANA', numero: '3056', complemento: 'SALA 2', bairro: 'CENTRO',
                  cep: '85810010', municipio: 'CASCAVEL', uf: 'PR' },
      release: '2026-08'
    )
  end

  it 'lista só sócios da release atual, com oab_id quando vinculado' do
    partners = described_class.new(company).partners_block
    expect(partners.map { |p| p[:nome] }).to contain_exactly('BRUNO PELLIZZETTI', 'FULANO WALBER')
    bruno = partners.find { |p| p[:nome] == 'BRUNO PELLIZZETTI' }
    expect(bruno).to include(qualificacao: 'Sócio-Administrador', data_entrada: '2019-03-04', faixa_etaria: '31 a 40 anos',
                             oab_id: 'PR_54159', lawyer_id: lawyer.id)
    expect(partners.find { |p| p[:nome] == 'FULANO WALBER' }).to include(oab_id: nil, lawyer_id: nil)
  end

  it 'as_json junta identidade, bloco receita e sócios' do
    json = described_class.new(company).as_json
    expect(json).to include(cnpj: '49780032000146', razao_social: 'PELLIZZETTI E WALBER ADVOGADOS ASSOCIADOS',
                            nome_fantasia: nil, matriz: true, cnae_principal: '6911701', situacao_cadastral: 'Ativa',
                            society_id: nil, match_confidence: nil, source: 'dump')
    expect(json[:partners].size).to eq(2)
  end
end
```

- [ ] **Step 2: Teste do payload do advogado**

```ruby
# spec/serializers/lawyer_serializer_spec.rb  (acrescentar este describe se o arquivo existir)
require 'rails_helper'

RSpec.describe LawyerSerializer do
  describe 'sociedade com dados da Receita' do
    let(:lawyer) { create(:lawyer, oab_id: 'PR_54159', state: 'PR') }
    let(:society) { create(:society, state: 'PR') }

    before { create(:lawyer_society, lawyer: lawyer, society: society) }

    it 'traz cnpj, receita e partners quando a sociedade está verified' do
      company = create(:receita_company, society: society, match_confidence: 'verified', release: '2026-08')
      create(:receita_partner, receita_company: company, nome_socio: 'BRUNO PELLIZZETTI', lawyer: lawyer, last_seen_release: '2026-08')
      society.update_columns(cnpj: company.cnpj, cnpja_match_confidence: 'verified')

      s = described_class.new(lawyer).as_json[:societies].first
      expect(s[:cnpj]).to eq(company.cnpj)
      expect(s[:receita][:situacao_cadastral]).to eq('Ativa')
      expect(s[:partners].first).to include(nome: 'BRUNO PELLIZZETTI', oab_id: 'PR_54159')
    end

    it 'traz cnpj nulo, receita nulo e partners vazio sem match verified' do
      company = create(:receita_company, society: society, match_confidence: 'ambiguous')
      society.update_columns(cnpja_match_confidence: 'ambiguous')

      s = described_class.new(lawyer).as_json[:societies].first
      expect(s).to include(cnpj: nil, receita: nil, partners: [])
    end
  end
end
```

- [ ] **Step 3: Rodar e ver falhar**

Run: `bundle exec rspec spec/serializers/receita_company_serializer_spec.rb spec/serializers/lawyer_serializer_spec.rb`
Expected: FAIL com `uninitialized constant ReceitaCompanySerializer`

- [ ] **Step 4: Implementar o serializer**

```ruby
# app/serializers/receita_company_serializer.rb
# Formato único dos dados da Receita para: sociedade no payload do advogado
# (receita_block + partners_block), GET /cnpj/:cnpj e GET /receita/companies
# (as_json). ProcStudio e FFD dependem destes nomes — mudança aqui é mudança
# pública (changelog).
class ReceitaCompanySerializer
  def initialize(company)
    @company = company
  end

  def as_json
    return nil unless @company

    {
      cnpj: @company.cnpj,
      razao_social: @company.razao_social,
      nome_fantasia: @company.nome_fantasia,
      matriz: @company.matriz,
      cnae_principal: @company.cnae_principal,
      society_id: @company.society_id,
      match_confidence: @company.match_confidence,
      source: @company.source
    }.merge(receita_block).merge(partners: partners_block)
  end

  def receita_block
    c = @company
    {
      situacao_cadastral: c.situacao_cadastral,
      data_situacao_cadastral: c.data_situacao_cadastral&.iso8601,
      data_inicio_atividade: c.data_inicio_atividade&.iso8601,
      natureza_juridica: c.natureza_juridica,
      capital_social: c.capital_social&.to_s('F'),
      porte_empresa: c.porte_empresa,
      opcao_simples: c.opcao_simples,
      opcao_mei: c.opcao_mei,
      email: c.email,
      telefones: c.telefones,
      endereco: {
        tipo_logradouro: c.tipo_logradouro, logradouro: c.logradouro, numero: c.numero, complemento: c.complemento,
        bairro: c.bairro, cep: c.cep, municipio: c.municipio, uf: c.uf
      },
      release: c.release
    }
  end

  def partners_block
    @company.current_partners.includes(:lawyer).map do |p|
      {
        nome: p.nome_socio,
        qualificacao: p.qualificacao,
        data_entrada: p.data_entrada_sociedade&.iso8601,
        faixa_etaria: p.faixa_etaria,
        identificador: p.identificador,
        oab_id: p.lawyer&.oab_id,
        lawyer_id: p.lawyer_id
      }
    end
  end

  def self.serialize_collection(companies)
    companies.map { |c| new(c).as_json }
  end
end
```

`capital_social.to_s('F')` de `BigDecimal('10000')` devolve `"10000.0"`, não `"10000.00"`. Use `format('%.2f', c.capital_social)` quando presente:

```ruby
      capital_social: c.capital_social && format('%.2f', c.capital_social),
```

- [ ] **Step 5: Alterar `LawyerSerializer#society_attributes`**

Substituir o bloco inteiro do método por:

```ruby
  def society_attributes
    return {} unless @include_societies

    societies_data = @lawyer.lawyer_societies.includes(society: { receita_company: { receita_partners: :lawyer } }).map do |ls|
      society = ls.society
      receita = society.receita_company if society.cnpja_match_confidence == Receita::SocietyMatcher::VERIFIED && society.cnpj.present?
      serializer = receita && ReceitaCompanySerializer.new(receita)
      {
        id: society.id,
        name: society.name,
        oab_id: society.oab_id,
        inscricao: society.inscricao,
        state: society.state,
        city: society.city,
        address: society.address,
        phone: society.phone,
        situacao: society.situacao,
        number_of_partners: society.number_of_partners,
        society_link: society.society_link,
        partnership_type: ls.partnership_type,
        partnership_type_label: ls.partnership_type_before_type_cast,
        cnpj: receita ? society.cnpj : nil,
        receita: serializer&.receita_block,
        partners: serializer ? serializer.partners_block : []
      }
    end

    { societies: societies_data }
  end
```

- [ ] **Step 6: Eager load no controller**

Em `app/controllers/api/v1/lawyers_controller.rb`, nas três ocorrências de `includes(... :lawyer_societies, :societies)` das linhas 164, 192 e 197, trocar `:societies` por `societies: { receita_company: { receita_partners: :lawyer } }`. Exemplo da linha 164:

```ruby
        found_lawyer = Lawyer.includes(:principal_lawyer, :supplementary_lawyers, :lawyer_societies,
                                       societies: { receita_company: { receita_partners: :lawyer } }).find_by(oab_id: oab)
```

- [ ] **Step 7: Rodar e ver passar (inclusive a suíte de requests existente)**

Run: `bundle exec rspec spec/serializers spec/requests`
Expected: tudo verde. Se algum request spec antigo comparar o hash da sociedade por igualdade exata, atualize-o acrescentando `cnpj: nil, receita: nil, partners: []`.

- [ ] **Step 8: Commit**

```bash
git add app/serializers/receita_company_serializer.rb app/serializers/lawyer_serializer.rb app/controllers/api/v1/lawyers_controller.rb spec/serializers
git commit -m "feat(receita): cnpj, bloco receita e sócios na sociedade do payload do advogado

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: `GET /api/v1/cnpj/:cnpj` com fallback na API pública

**Files:**
- Create: `app/services/receita/opencnpj_client.rb`
- Create: `app/services/receita/cnpj_lookup.rb`
- Create: `app/controllers/api/v1/cnpj_controller.rb`
- Modify: `config/routes.rb` (dentro de `namespace :v1`, após as rotas de sociedades)
- Test: `spec/services/receita/cnpj_lookup_spec.rb`, `spec/requests/api/v1/cnpj_spec.rb`

**Interfaces:**
- Consumes: `Receita::Cnpj.normalize`, `Receita::Importer#import_records`, `ReceitaCompanySerializer`.
- Produces: `Receita::OpencnpjClient.new.fetch(cnpj) -> Hash | nil` (nil = 404), levanta `Receita::OpencnpjClient::RateLimited` (429) e `Receita::OpencnpjClient::Error` (outros); `Receita::CnpjLookup.call(cnpj) -> Receita::CnpjLookup::Result` com `status` em `:found, :not_found, :invalid, :unavailable`, `company`, `retry_after`.

- [ ] **Step 1: Teste do serviço**

```ruby
# spec/services/receita/cnpj_lookup_spec.rb
require 'rails_helper'

RSpec.describe Receita::CnpjLookup do
  let(:cnpj) { '11222333000181' }
  let(:api_url) { "https://api.opencnpj.org/#{cnpj}" }
  let(:api_body) do
    { 'cnpj' => cnpj, 'razao_social' => 'FIRMA DA API LTDA', 'situacao_cadastral' => 'Ativa', 'matriz_filial' => 'Matriz',
      'data_inicio_atividade' => '2020-01-10', 'cnae_principal' => '6911701', 'natureza_juridica' => 'Sociedade Simples Pura',
      'uf' => 'SP', 'municipio' => 'SAO PAULO', 'email' => 'x@y.com', 'telefones' => [], 'capital_social' => '1000,00',
      'QSA' => [{ 'nome_socio' => 'SOCIA UM', 'cnpj_cpf_socio' => '***111222**', 'qualificacao_socio' => 'Sócio-Administrador',
                  'data_entrada_sociedade' => '2020-01-10', 'identificador_socio' => 'Pessoa Física', 'faixa_etaria' => '41 a 50 anos' }] }
  end

  it 'devolve invalid para CNPJ com dígito errado sem chamar a API' do
    result = described_class.call('11.222.333/0001-82')
    expect(result.status).to eq(:invalid)
    expect(a_request(:get, /opencnpj/)).not_to have_been_made
  end

  it 'devolve a linha do dump sem chamar a API' do
    company = create(:receita_company, cnpj: cnpj)
    result = described_class.call(cnpj)
    expect(result.status).to eq(:found)
    expect(result.company).to eq(company)
    expect(a_request(:get, api_url)).not_to have_been_made
  end

  it 'na falta, consulta a API, grava como opencnpj_api com sócios e devolve' do
    stub_request(:get, api_url).to_return(status: 200, body: api_body.to_json, headers: { 'Content-Type' => 'application/json' })

    result = described_class.call(cnpj)
    expect(result.status).to eq(:found)
    expect(result.company.source).to eq('opencnpj_api')
    expect(result.company.release).to be_nil
    expect(result.company.receita_partners.count).to eq(1)
  end

  it 'reutiliza cache da API com menos de 30 dias e refaz depois' do
    stub = stub_request(:get, api_url).to_return(status: 200, body: api_body.to_json)
    create(:receita_company, :from_api, cnpj: cnpj, fetched_at: 29.days.ago)
    described_class.call(cnpj)
    expect(stub).not_to have_been_requested

    ReceitaCompany.find_by!(cnpj: cnpj).update_columns(fetched_at: 31.days.ago)
    described_class.call(cnpj)
    expect(stub).to have_been_requested.once
  end

  it '404 da API vira not_found com cache negativo de 7 dias' do
    stub = stub_request(:get, api_url).to_return(status: 404, body: '')
    expect(described_class.call(cnpj).status).to eq(:not_found)
    expect(ReceitaCompany.find_by!(cnpj: cnpj)).to be_negative_cache

    expect(described_class.call(cnpj).status).to eq(:not_found)
    expect(stub).to have_been_requested.once

    ReceitaCompany.find_by!(cnpj: cnpj).update_columns(fetched_at: 8.days.ago)
    described_class.call(cnpj)
    expect(stub).to have_been_requested.twice
  end

  it '429 vira unavailable com retry_after e não grava nada' do
    stub_request(:get, api_url).to_return(status: 429, headers: { 'Retry-After' => '30' })
    result = described_class.call(cnpj)
    expect(result.status).to eq(:unavailable)
    expect(result.retry_after).to eq(30)
    expect(ReceitaCompany.where(cnpj: cnpj)).to be_empty
  end

  it 'timeout vira unavailable sem gravar nada' do
    stub_request(:get, api_url).to_timeout
    expect(described_class.call(cnpj).status).to eq(:unavailable)
    expect(ReceitaCompany.where(cnpj: cnpj)).to be_empty
  end
end
```

- [ ] **Step 2: Teste de request**

```ruby
# spec/requests/api/v1/cnpj_spec.rb
require 'rails_helper'

RSpec.describe 'Api::V1::Cnpj', type: :request do
  let(:user) { User.create!(email: 'cnpj@example.com', password: 'password', admin: false) }
  let(:api_key) { ApiKey.create!(user: user, active: true, role: 'read') }
  let(:headers) { { 'X-API-KEY' => api_key.key } }

  it 'exige API key' do
    get '/api/v1/cnpj/11222333000181'
    expect(response).to have_http_status(:unauthorized)
  end

  it 'devolve 422 em pt-BR para CNPJ inválido' do
    get '/api/v1/cnpj/11222333000182', headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('CNPJ inválido')
  end

  it 'devolve a empresa do dump no formato do ReceitaCompanySerializer, aceitando máscara' do
    company = create(:receita_company, cnpj: '11222333000181')
    create(:receita_partner, receita_company: company, nome_socio: 'SOCIA UM', last_seen_release: company.release)

    get '/api/v1/cnpj/11.222.333%2F0001-81', headers: headers
    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body['cnpj']).to eq('11222333000181')
    expect(body['endereco']['municipio']).to eq('CASCAVEL')
    expect(body['partners'].first['nome']).to eq('SOCIA UM')
    expect(UsageEvent.count).to eq(1)
  end

  it 'devolve 404 quando a API pública não conhece o CNPJ' do
    stub_request(:get, 'https://api.opencnpj.org/11222333000181').to_return(status: 404)
    get '/api/v1/cnpj/11222333000181', headers: headers
    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body['error']).to eq('CNPJ não encontrado na Receita')
  end

  it 'devolve 503 com retry_after quando a API pública limita' do
    stub_request(:get, 'https://api.opencnpj.org/11222333000181').to_return(status: 429, headers: { 'Retry-After' => '45' })
    get '/api/v1/cnpj/11222333000181', headers: headers
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body).to include('error' => 'Receita indisponível no momento', 'retry_after' => 45)
  end
end
```

- [ ] **Step 3: Rodar e ver falhar**

Run: `bundle exec rspec spec/services/receita/cnpj_lookup_spec.rb spec/requests/api/v1/cnpj_spec.rb`
Expected: FAIL com `uninitialized constant Receita::CnpjLookup` e rotas inexistentes.

- [ ] **Step 4: Cliente HTTP**

```ruby
# app/services/receita/opencnpj_client.rb
# frozen_string_literal: true

require 'net/http'
require 'json'

module Receita
  # API pública do OpenCNPJ (mesmo JSON do dump). Sem chave. Limite público não
  # documentado: 1 tentativa por CNPJ, timeouts curtos, e quem chama decide o
  # cache. A própria API manda Cache-Control de 24h.
  class OpencnpjClient
    HOST = 'api.opencnpj.org'
    OPEN_TIMEOUT = 3
    READ_TIMEOUT = 5

    class Error < StandardError; end

    class RateLimited < Error
      attr_reader :retry_after

      def initialize(retry_after)
        @retry_after = retry_after
        super("OpenCNPJ 429, retry em #{retry_after}s")
      end
    end

    # Hash do estabelecimento, ou nil quando a Receita não conhece o CNPJ (404).
    def fetch(cnpj)
      uri = URI::HTTPS.build(host: HOST, path: "/#{cnpj}")
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
        http.get(uri.request_uri, { 'Accept' => 'application/json', 'User-Agent' => 'legal_data (procstudio.api.br)' })
      end

      case response
      when Net::HTTPSuccess then JSON.parse(response.body)
      when Net::HTTPNotFound then nil
      when Net::HTTPTooManyRequests then raise RateLimited, response['Retry-After'].to_i.clamp(1, 3600)
      else raise Error, "OpenCNPJ HTTP #{response.code}"
      end
    rescue JSON::ParserError, Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, OpenSSL::SSL::SSLError => e
      raise Error, "#{e.class}: #{e.message}"
    end
  end
end
```

- [ ] **Step 5: Serviço de lookup**

```ruby
# app/services/receita/cnpj_lookup.rb
# frozen_string_literal: true

module Receita
  # Lookup de um CNPJ qualquer: primeiro a tabela (dump ou cache da API), depois
  # a API pública. Linha da API vale 30 dias; "não existe" vale 7 dias (cache
  # negativo = linha com raw vazio). Falha de rede/429 nunca grava nada.
  class CnpjLookup
    API_TTL = 30.days
    NEGATIVE_TTL = 7.days

    Result = Struct.new(:status, :company, :retry_after, keyword_init: true)

    def self.call(input, client: OpencnpjClient.new)
      new(input, client: client).call
    end

    def initialize(input, client:)
      @cnpj = Cnpj.normalize(input)
      @client = client
    end

    def call
      return Result.new(status: :invalid) if @cnpj.nil?

      cached = ReceitaCompany.find_by(cnpj: @cnpj)
      return result_for(cached) if cached && fresh?(cached)

      refresh_from_api
    end

    private

    def fresh?(company)
      return true if company.source == ReceitaCompany::SOURCE_DUMP

      ttl = company.negative_cache? ? NEGATIVE_TTL : API_TTL
      company.fetched_at > ttl.ago
    end

    def result_for(company)
      return Result.new(status: :not_found) if company.negative_cache?

      Result.new(status: :found, company: company)
    end

    def refresh_from_api
      record = @client.fetch(@cnpj)
      if record.nil?
        store_negative
        return Result.new(status: :not_found)
      end

      Importer.new(file: nil, release: nil, source: ReceitaCompany::SOURCE_API, logger: Rails.logger)
              .import_records([record.merge('cnpj' => @cnpj)])
      Result.new(status: :found, company: ReceitaCompany.find_by!(cnpj: @cnpj))
    rescue OpencnpjClient::RateLimited => e
      Result.new(status: :unavailable, retry_after: e.retry_after)
    rescue OpencnpjClient::Error => e
      Rails.logger.warn("Receita::CnpjLookup #{@cnpj}: #{e.message}")
      Result.new(status: :unavailable)
    end

    def store_negative
      now = Time.current
      ReceitaCompany.upsert_all(
        [{ cnpj: @cnpj, cnpj_root: @cnpj[0, 8], raw: {}, source: ReceitaCompany::SOURCE_API, release: nil,
           fetched_at: now, created_at: now, updated_at: now, telefones: [] }],
        unique_by: :index_receita_companies_on_cnpj,
        update_only: %i[raw source release fetched_at updated_at]
      )
    end
  end
end
```

O `Importer#import_records` da Task 3 filtra registros já existentes com a **mesma** release e source; para a API (`release: nil`) um registro expirado precisa ser sobrescrito. Ajuste em `Importer#import_records`: aplique o filtro de `existing` só quando `@release.present?`.

- [ ] **Step 6: Controller e rota**

```ruby
# app/controllers/api/v1/cnpj_controller.rb
module Api
  module V1
    class CnpjController < ApplicationController
      include ApiAuthentication
      include UsageTracking

      # GET /api/v1/cnpj/:cnpj — tabela local primeiro, API pública do OpenCNPJ na falta.
      def show
        result = Receita::CnpjLookup.call(params[:cnpj])

        case result.status
        when :found
          render json: ReceitaCompanySerializer.new(result.company).as_json, status: :ok
        when :invalid
          render json: { error: 'CNPJ inválido' }, status: :unprocessable_entity
        when :not_found
          render json: { error: 'CNPJ não encontrado na Receita' }, status: :not_found
        else
          response.headers['Retry-After'] = result.retry_after.to_s if result.retry_after
          render json: { error: 'Receita indisponível no momento', retry_after: result.retry_after }, status: :service_unavailable
        end
      end
    end
  end
end
```

Em `config/routes.rb`, após `delete 'society/:inscricao', to: 'societies#destroy'`:

```ruby
      # Receita Federal (dump OpenCNPJ + API pública). `:cnpj` aceita máscara (pontos, barra, hífen) — a
      # constraint libera esses caracteres para o parâmetro.
      get 'cnpj/:cnpj', to: 'cnpj#show', constraints: { cnpj: %r{[0-9A-Za-z.\-/%]+} }
```

- [ ] **Step 7: Rodar e ver passar**

Run: `bundle exec rspec spec/services/receita/cnpj_lookup_spec.rb spec/requests/api/v1/cnpj_spec.rb spec/services/receita/importer_spec.rb`
Expected: tudo verde (o importer continua idempotente para release presente).

- [ ] **Step 8: Commit**

```bash
git add app/services/receita/opencnpj_client.rb app/services/receita/cnpj_lookup.rb app/services/receita/importer.rb app/controllers/api/v1/cnpj_controller.rb config/routes.rb spec/services/receita/cnpj_lookup_spec.rb spec/requests/api/v1/cnpj_spec.rb
git commit -m "feat(receita): GET /cnpj/:cnpj com fallback na API pública do OpenCNPJ e cache de 30 dias

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: `GET /api/v1/receita/companies` com filtros e cursor

**Files:**
- Create: `app/controllers/api/v1/receita/companies_controller.rb`
- Modify: `config/routes.rb`
- Test: `spec/requests/api/v1/receita_companies_spec.rb`

**Interfaces:**
- Consumes: `ReceitaCompanySerializer.serialize_collection`, scopes de `ReceitaCompany`.
- Produces: resposta `{ companies: [...], meta: { returned:, next_from_cnpj:, filters_applied: {...} } }`.

- [ ] **Step 1: Teste de request**

```ruby
# spec/requests/api/v1/receita_companies_spec.rb
require 'rails_helper'

RSpec.describe 'Api::V1::Receita::Companies', type: :request do
  let(:user) { User.create!(email: 'ffd@example.com', password: 'password', admin: false) }
  let(:api_key) { ApiKey.create!(user: user, active: true, role: 'read') }
  let(:headers) { { 'X-API-KEY' => api_key.key } }

  def get_companies(params = {})
    get '/api/v1/receita/companies', params: params, headers: headers
    response.parsed_body
  end

  it 'exige uf válida' do
    get '/api/v1/receita/companies', headers: headers
    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body['error']).to eq('Parâmetro uf é obrigatório')

    get '/api/v1/receita/companies', params: { uf: 'XX' }, headers: headers
    expect(response).to have_http_status(:bad_request)
  end

  it 'por default devolve só ativas, matriz e naturezas de sociedade, em ordem de cnpj' do
    a = create(:receita_company, uf: 'PR', cnpj: '10000000000100')
    create(:receita_company, uf: 'PR', cnpj: '10000000000200', situacao_cadastral: 'Baixada')
    create(:receita_company, uf: 'PR', cnpj: '10000000000300', matriz: false)
    create(:receita_company, uf: 'PR', cnpj: '10000000000400', natureza_juridica: 'Serviço Notarial e Registral (Cartório)')
    create(:receita_company, uf: 'SP', cnpj: '10000000000500')
    b = create(:receita_company, uf: 'PR', cnpj: '10000000000600')

    body = get_companies(uf: 'pr')
    expect(body['companies'].map { |c| c['cnpj'] }).to eq([a.cnpj, b.cnpj])
    expect(body['meta']['returned']).to eq(2)
    expect(body['meta']['next_from_cnpj']).to be_nil
  end

  it 'unmatched exclui firma casada e filiais da mesma raiz; known_lawyer exige sócio vinculado' do
    society = create(:society, state: 'PR')
    matched = create(:receita_company, uf: 'PR', cnpj: '11222333000181', society: society, match_confidence: 'verified')
    create(:receita_company, uf: 'PR', cnpj: '11222333000262')  # mesma raiz, filial não casada
    prospect = create(:receita_company, uf: 'PR', cnpj: '12345678000195')
    create(:receita_partner, receita_company: prospect, lawyer: create(:lawyer), last_seen_release: prospect.release)
    other = create(:receita_company, uf: 'PR', cnpj: '22345678000149')

    cnpjs = get_companies(uf: 'PR', unmatched: 'true')['companies'].map { |c| c['cnpj'] }
    expect(cnpjs).to contain_exactly(prospect.cnpj, other.cnpj)
    expect(cnpjs).not_to include(matched.cnpj)

    cnpjs = get_companies(uf: 'PR', known_lawyer: 'true')['companies'].map { |c| c['cnpj'] }
    expect(cnpjs).to eq([prospect.cnpj])
  end

  it 'filtra por founded_since, natureza e updated_since' do
    nova = create(:receita_company, uf: 'PR', data_inicio_atividade: Date.new(2026, 9, 1), natureza_juridica: 'Sociedade Unipessoal de Advocacia')
    create(:receita_company, uf: 'PR', data_inicio_atividade: Date.new(2015, 1, 1))

    expect(get_companies(uf: 'PR', founded_since: '2026-01-01')['companies'].map { |c| c['cnpj'] }).to eq([nova.cnpj])
    expect(get_companies(uf: 'PR', natureza: 'Sociedade Unipessoal de Advocacia')['companies'].map { |c| c['cnpj'] }).to eq([nova.cnpj])
    expect(get_companies(uf: 'PR', updated_since: 1.hour.from_now.iso8601)['companies']).to eq([])
  end

  it 'pagina por cursor e limita a 500' do
    3.times { |i| create(:receita_company, uf: 'PR', cnpj: format('%014d', 30_000_000_000_100 + i * 100)) }

    page1 = get_companies(uf: 'PR', limit: 2)
    expect(page1['companies'].size).to eq(2)
    expect(page1['meta']['next_from_cnpj']).to eq(page1['companies'].last['cnpj'])

    page2 = get_companies(uf: 'PR', limit: 2, from_cnpj: page1['meta']['next_from_cnpj'])
    expect(page2['companies'].size).to eq(1)
    expect(page2['meta']['next_from_cnpj']).to be_nil

    expect(get_companies(uf: 'PR', limit: 9999)['meta']['filters_applied']['limit']).to eq(500)
  end

  it 'situacao=all inclui baixadas e matriz=false inclui filiais' do
    create(:receita_company, uf: 'PR', situacao_cadastral: 'Baixada', matriz: false)
    expect(get_companies(uf: 'PR', situacao: 'all', matriz: 'false')['companies'].size).to eq(1)
  end
end
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `bundle exec rspec spec/requests/api/v1/receita_companies_spec.rb`
Expected: FAIL (rota não existe).

- [ ] **Step 3: Controller**

```ruby
# app/controllers/api/v1/receita/companies_controller.rb
module Api
  module V1
    module Receita
      # Listagem de estabelecimentos da Receita para prospecção (FFD).
      # Cursor por cnpj crescente, limite 500. Defaults conservadores: ativas,
      # matriz, só naturezas de sociedade de advogados.
      class CompaniesController < ApplicationController
        include ApiAuthentication
        include UsageTracking

        MAX_LIMIT = 500
        DEFAULT_LIMIT = 100
        VALID_STATES = Api::V1::LawyersController::VALID_STATES

        def index
          uf = params[:uf].to_s.upcase
          return render json: { error: 'Parâmetro uf é obrigatório' }, status: :bad_request if uf.blank?
          return render json: { error: "uf inválida. Válidas: #{VALID_STATES.join(', ')}" }, status: :bad_request unless VALID_STATES.include?(uf)

          limit = params[:limit].to_i
          limit = DEFAULT_LIMIT if limit <= 0
          limit = [limit, MAX_LIMIT].min

          scope = ::ReceitaCompany.from_dump.where(uf: uf)
          scope = scope.ativas unless params[:situacao].to_s == 'all'
          scope = scope.where(situacao_cadastral: params[:situacao]) if params[:situacao].present? && params[:situacao] != 'all'
          scope = scope.matrizes unless params[:matriz].to_s == 'false'
          scope = apply_natureza(scope)
          scope = scope.where('data_inicio_atividade >= ?', Date.iso8601(params[:founded_since])) if params[:founded_since].present?
          scope = scope.where('receita_companies.updated_at >= ?', Time.iso8601(params[:updated_since])) if params[:updated_since].present?
          scope = scope.where(society_id: nil).where.not(cnpj_root: ::ReceitaCompany.where.not(society_id: nil).select(:cnpj_root)) if params[:unmatched].to_s == 'true'
          scope = scope.where(id: ::ReceitaPartner.linked.select(:receita_company_id)) if params[:known_lawyer].to_s == 'true'
          scope = scope.where('cnpj > ?', params[:from_cnpj]) if params[:from_cnpj].present?

          records = scope.order(:cnpj).limit(limit + 1).includes(receita_partners: :lawyer).to_a
          has_more = records.size > limit
          page = has_more ? records.first(limit) : records

          render json: {
            companies: ReceitaCompanySerializer.serialize_collection(page),
            meta: {
              returned: page.size,
              next_from_cnpj: has_more ? page.last.cnpj : nil,
              filters_applied: { uf: uf, limit: limit, situacao: params[:situacao].presence || 'Ativa',
                                 matriz: params[:matriz].to_s != 'false', natureza: natureza_filter,
                                 founded_since: params[:founded_since], updated_since: params[:updated_since],
                                 unmatched: params[:unmatched].to_s == 'true', known_lawyer: params[:known_lawyer].to_s == 'true' }
            }
          }, status: :ok
        rescue ArgumentError, Date::Error => e
          render json: { error: "Parâmetro de data inválido: #{e.message}" }, status: :bad_request
        end

        private

        def natureza_filter
          params[:natureza].presence&.split(',')&.map(&:strip) || ::ReceitaCompany::SOCIETY_NATURES
        end

        def apply_natureza(scope)
          return scope if params[:natureza].to_s == 'all'

          scope.where(natureza_juridica: natureza_filter)
        end
      end
    end
  end
end
```

Note o `::ReceitaCompany`: dentro de `Api::V1::Receita`, `Receita` resolve para o módulo do namespace do controller, não para `::Receita` dos serviços. Por isso o controller usa `::ReceitaCompany`/`::ReceitaPartner` e não referencia `Receita::...` dos services.

- [ ] **Step 4: Rota**

Em `config/routes.rb`, após a rota `cnpj/:cnpj`:

```ruby
      namespace :receita do
        get 'companies', to: 'companies#index'
      end
```

- [ ] **Step 5: Rodar e ver passar**

Run: `bundle exec rspec spec/requests/api/v1/receita_companies_spec.rb`
Expected: 6 examples, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/api/v1/receita/companies_controller.rb config/routes.rb spec/requests/api/v1/receita_companies_spec.rb
git commit -m "feat(receita): GET /receita/companies com filtros de prospecção e cursor por cnpj

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 9: `rake receita:download`, `receita:extract`, `receita:refresh` e relatório ao webhook

**Files:**
- Create: `app/services/receita/refresh_report.rb`
- Create: `bin/receita_extract.sh`
- Modify: `lib/tasks/receita.rake`
- Test: `spec/services/receita/refresh_report_spec.rb`, `spec/tasks/receita_extract_spec.rb`

**Interfaces:**
- Produces: `Receita::RefreshReport.call(release:, stats:, webhook_url: ENV['USAGE_WEBHOOK_URL']) -> true | false`; script `bin/receita_extract.sh <data.zip> <saida.ndjson> [cnae]` (stdout: progresso; exit 0).

- [ ] **Step 1: Teste do relatório**

```ruby
# spec/services/receita/refresh_report_spec.rb
require 'rails_helper'

RSpec.describe Receita::RefreshReport do
  it 'posta o resumo da release no webhook do FFD' do
    stub = stub_request(:post, 'https://ffd.example/api/webhooks/usage?token=abc')
             .with(body: hash_including('service' => 'legal_data', 'event' => 'receita_refresh', 'release' => '2026-09'))
             .to_return(status: 200)

    ok = described_class.call(release: '2026-09', stats: { import: { read: 10 }, match: { verified: 3 } },
                              webhook_url: 'https://ffd.example/api/webhooks/usage?token=abc')
    expect(ok).to be(true)
    expect(stub).to have_been_requested
  end

  it 'devolve false sem webhook configurado e sem levantar erro' do
    expect(described_class.call(release: '2026-09', stats: {}, webhook_url: nil)).to be(false)
  end

  it 'devolve false em falha de rede' do
    stub_request(:post, 'https://ffd.example/x').to_timeout
    expect(described_class.call(release: '2026-09', stats: {}, webhook_url: 'https://ffd.example/x')).to be(false)
  end
end
```

- [ ] **Step 2: Teste do script de extração (zip pequeno gerado no teste)**

```ruby
# spec/tasks/receita_extract_spec.rb
require 'rails_helper'

RSpec.describe 'bin/receita_extract.sh' do
  it 'extrai só linhas do CNAE pedido de todos os shards, em streaming' do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, '001.ndjson'), "#{{ cnpj: '1', cnae_principal: '6911701' }.to_json}\n#{{ cnpj: '2', cnae_principal: '4711301' }.to_json}\n")
      File.write(File.join(dir, '002.ndjson'), "#{{ cnpj: '3', cnae_principal: '6911701' }.to_json}\n")
      system('zip', '-q', '-j', File.join(dir, 'data.zip'), File.join(dir, '001.ndjson'), File.join(dir, '002.ndjson')) || skip('zip indisponível')

      out = File.join(dir, 'advocacia.ndjson')
      ok = system(Rails.root.join('bin/receita_extract.sh').to_s, File.join(dir, 'data.zip'), out, '6911701', out: File::NULL)

      expect(ok).to be(true)
      expect(File.readlines(out).map { |l| JSON.parse(l)['cnpj'] }).to eq(%w[1 3])
    end
  end
end
```

- [ ] **Step 3: Rodar e ver falhar**

Run: `bundle exec rspec spec/services/receita/refresh_report_spec.rb spec/tasks/receita_extract_spec.rb`
Expected: FAIL.

- [ ] **Step 4: Script de extração**

```bash
#!/bin/bash
# bin/receita_extract.sh <data.zip> <saida.ndjson> [cnae=6911701]
# Filtra do dump do OpenCNPJ só os estabelecimentos do CNAE pedido, shard a
# shard, sem materializar os ~124 GB descompactados. Mesma receita do
# extract_advocacia.sh usado no Mac em 2026-10 (987 shards, ~20 min).
set -uo pipefail
ZIP="$1"; OUT="$2"; CNAE="${3:-6911701}"
: > "$OUT"
n=0
unzip -Z1 "$ZIP" | while read -r member; do
  unzip -p "$ZIP" "$member" | grep "\"cnae_principal\":\"$CNAE\"" >> "$OUT"
  n=$((n+1))
  if [ $((n % 100)) -eq 0 ]; then echo "$(date +%H:%M:%S) shards=$n linhas=$(wc -l < "$OUT")"; fi
done
echo "FIM shards=$(unzip -Z1 "$ZIP" | wc -l | tr -d ' ') linhas=$(wc -l < "$OUT" | tr -d ' ')"
```

`chmod +x bin/receita_extract.sh`. O `grep` sem match devolve exit 1 em um shard sem advocacia; por isso o script **não** usa `set -e`.

- [ ] **Step 5: Relatório**

```ruby
# app/services/receita/refresh_report.rb
# frozen_string_literal: true

require 'net/http'

module Receita
  # POST do resumo de um refresh para o webhook do FFD (mesmo destino do
  # UsageReportJob). Aparece na página Alertas. Nunca levanta: falha aqui não
  # pode desfazer um refresh que já deu certo.
  module RefreshReport
    def self.call(release:, stats:, webhook_url: ENV['USAGE_WEBHOOK_URL'])
      return false if webhook_url.blank?

      payload = { service: 'legal_data', event: 'receita_refresh', release: release,
                  at: Time.current.iso8601, stats: stats }
      uri = URI(webhook_url)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 10, read_timeout: 30) do |http|
        http.post(uri.request_uri, payload.to_json, { 'Content-Type' => 'application/json' })
      end
      response.is_a?(Net::HTTPSuccess)
    rescue StandardError => e
      Rails.logger.error("Receita::RefreshReport: #{e.class}: #{e.message}")
      false
    end
  end
end
```

- [ ] **Step 6: Tasks de download, extract e refresh**

Acrescentar em `lib/tasks/receita.rake`:

```ruby
  # Diretório por release: storage/receita/<release>/{data.zip,advocacia.ndjson}
  def self.release_dir(release)
    Rails.root.join('storage', 'receita', release).tap { |d| FileUtils.mkdir_p(d) }
  end

  desc 'Baixa o data.zip do OpenCNPJ (retomável) e confere o MD5 do info.json'
  task download: :environment do
    release = ENV.fetch('RELEASE')
    dir = release_dir(release)
    info = JSON.parse(Net::HTTP.get(URI('https://api.opencnpj.org/info.json')))
    receita = info.fetch('datasets').fetch('receita')
    zip = dir.join('data.zip')

    sh "curl -fL -C - --retry 5 -o #{zip} #{receita.fetch('zip_url')}"
    actual = `md5sum #{zip} 2>/dev/null || md5 -q #{zip}`.split.first
    abort "MD5 divergente: esperado #{receita['zip_md5checksum']}, obtido #{actual}" unless actual == receita['zip_md5checksum']
    File.write(dir.join('info.json'), JSON.pretty_generate(info))
    puts "FIM download release=#{release} bytes=#{File.size(zip)} md5=ok"
  end

  desc 'Extrai o recorte de advocacia do data.zip da release'
  task extract: :environment do
    release = ENV.fetch('RELEASE')
    dir = release_dir(release)
    sh Rails.root.join('bin/receita_extract.sh').to_s, dir.join('data.zip').to_s, dir.join('advocacia.ndjson').to_s, ENV.fetch('CNAE', '6911701')
  end

  desc 'Refresh completo de uma release: download, extract, import, match, link, relatório, limpeza'
  task refresh: :environment do
    release = ENV.fetch('RELEASE')
    dir = release_dir(release)
    ndjson = dir.join('advocacia.ndjson')

    unless File.exist?(ndjson)
      Rake::Task['receita:download'].invoke unless File.exist?(dir.join('data.zip'))
      Rake::Task['receita:extract'].invoke
    end

    stats = {}
    stats[:import] = Receita::Importer.new(file: ndjson, release: release, logger: Logger.new($stdout)).call
    stats[:match] = Hash.new(0)
    stats[:link] = Hash.new(0)
    Society.distinct.pluck(:state).compact.sort.each do |state|
      Receita::SocietyMatcher.new(state: state, release: release, logger: Logger.new($stdout)).call.each { |k, v| stats[:match][k] += v }
    end
    ReceitaCompany.distinct.pluck(:uf).compact.sort.each do |uf|
      Receita::PartnerLinker.new(state: uf, release: release, logger: Logger.new($stdout)).call.each { |k, v| stats[:link][k] += v }
    end

    FileUtils.rm_f(dir.join('data.zip'))
    Dir.glob(Rails.root.join('storage', 'receita', '*')).each do |old|
      FileUtils.rm_rf(old) if File.mtime(old) < 3.months.ago
    end

    reported = Receita::RefreshReport.call(release: release, stats: stats)
    puts "FIM refresh release=#{release} reportado=#{reported} #{stats.to_json}"
  end
```

No topo do arquivo, acrescentar `require 'net/http'` e `require 'fileutils'`.

- [ ] **Step 7: Rodar e ver passar**

Run: `bundle exec rspec spec/services/receita/refresh_report_spec.rb spec/tasks/receita_extract_spec.rb && bundle exec rake -T receita`
Expected: testes verdes; `rake -T` lista `receita:download`, `receita:extract`, `receita:import`, `receita:link_partners`, `receita:match_societies`, `receita:refresh`.

- [ ] **Step 8: Commit**

```bash
git add app/services/receita/refresh_report.rb bin/receita_extract.sh lib/tasks/receita.rake spec/services/receita/refresh_report_spec.rb spec/tasks/receita_extract_spec.rb
git commit -m "feat(receita): refresh mensal (download, extract em streaming, import, match, link, relatório)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 10: Changelog 1.6, README e PLANO-CNPJA aposentado

**Files:**
- Modify: `config/changelog.yml` (topo)
- Modify: `README.md` (seção de endpoints: documentar os 3 novos e os campos novos da sociedade)
- Modify: `PLANO-CNPJA.md` (cabeçalho de status)
- Test: `spec/requests/api/v1/version_spec.rb` (se existir, deve continuar verde; se não existir, não criar)

- [ ] **Step 1: Changelog**

Inserir no topo de `config/changelog.yml`, antes da entrada 1.5:

```yaml
- version: "1.6"
  date: "06/10/2026"
  note: "Receita Federal via dump OpenCNPJ: sociedade do advogado ganha cnpj, bloco receita e partners (sócios com oab_id); GET /cnpj/:cnpj com fallback na API pública; GET /receita/companies para prospecção com filtros e cursor"
  pr:
```

- [ ] **Step 2: README**

Adicionar uma seção `## Receita Federal (OpenCNPJ)` no README com: as três rotas (método, caminho, parâmetros, exemplo de resposta copiado do `ReceitaCompanySerializer`), a regra de confiança (`verified` / `ambiguous` / `unmatched`), e a sequência de operação mensal:

```bash
ssh -i ~/.ssh/deploy_prc_legal brpl@168.231.90.14
cd ~/legal_data_api   # confirmar o path real pelo WorkingDirectory de infra/legal_data_api.service
RAILS_ENV=production bundle exec rake receita:refresh RELEASE=2026-09
```

- [ ] **Step 3: PLANO-CNPJA.md**

Trocar a linha `Status: **plano** (nada implementado, nada gravado no banco).` por:

```markdown
Status: **substituído** em 2026-10-06 pelo dump público do OpenCNPJ — ver `docs/superpowers/specs/2026-10-06-receita-cnpj-enrichment-design.md`. As regras de match do §2 continuam valendo e estão implementadas em `Receita::SocietyMatcher`. O cliente `Cnpja::Client` fica no repo mas não é mais o caminho principal.
```

- [ ] **Step 4: Suíte inteira**

Run: `bundle exec rspec`
Expected: 0 failures. Anotar o total de examples.

- [ ] **Step 5: Commit**

```bash
git add config/changelog.yml README.md PLANO-CNPJA.md
git commit -m "docs(receita): changelog 1.6, README dos endpoints e PLANO-CNPJA aposentado

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 11: Deploy, primeira carga em produção e validação

Sem código novo. Passos operacionais, na ordem. Cada um tem a saída esperada.

- [ ] **Step 1: Abrir a PR**

```bash
cd /Users/brpl/code/ProcStudio/prc_legal_data
git push -u origin brpl/receita-cnpj
gh pr create --title "feat(receita): enriquecimento societário via dump OpenCNPJ (API 1.6)" --body-file - <<'EOF'
Implementa a PR 1 da spec `docs/superpowers/specs/2026-10-06-receita-cnpj-enrichment-design.md`.

- tabelas `receita_companies` / `receita_partners` + importador idempotente por release
- matcher offline sociedade OAB x Receita (spike: 87% verified) + vínculo sócio->advogado
- sociedade no payload do advogado: `cnpj`, `receita`, `partners`
- `GET /api/v1/cnpj/:cnpj` (local + API pública com cache 30 d)
- `GET /api/v1/receita/companies` (prospecção, cursor)
- `rake receita:refresh RELEASE=` para o mensal

Operação pós-merge: primeira carga com o NDJSON 2026-08 (Task 11 do plano).

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
```

Expected: CI verde (`.github/workflows/deploy.yml` roda specs antes do deploy).

- [ ] **Step 2: Merge e deploy**

Após aprovação do Bruno: merge em `main`. O workflow faz o deploy (git reset, `db:migrate`, restart). Validar:

```bash
curl -s https://procstudio.api.br/api/v1/version | head -c 300
```

Expected: `"version":"1.6"`.

- [ ] **Step 3: Primeira carga (NDJSON já extraído no Mac)**

```bash
ssh-add ~/.ssh/deploy_prc_legal
APP=$(ssh -i ~/.ssh/deploy_prc_legal brpl@168.231.90.14 "grep WorkingDirectory ~/legal_data_api/infra/legal_data_api.service 2>/dev/null | cut -d= -f2 || echo ~/legal_data_api")
ssh -i ~/.ssh/deploy_prc_legal brpl@168.231.90.14 "mkdir -p $APP/storage/receita/2026-08"
scp -i ~/.ssh/deploy_prc_legal /Volumes/BPSSD/cnpj-opencnpj/2026-08/advocacia_6911701.ndjson brpl@168.231.90.14:$APP/storage/receita/2026-08/advocacia.ndjson
ssh -i ~/.ssh/deploy_prc_legal brpl@168.231.90.14 "cd $APP && RAILS_ENV=production bundle exec rake receita:refresh RELEASE=2026-08 2>&1 | tail -20"
```

Expected: `import read=261347`, `match verified≈148000 ambiguous≈2000`, `link linked` em dezenas de milhares, `reportado=true`. Tempo total abaixo de 30 min. Se o `scp` for lento, alternativa: `rake receita:download RELEASE=2026-08` no H1 (14 GB) e `receita:extract`.

- [ ] **Step 4: Validar os três endpoints em produção**

```bash
KEY=<chave read do ProcStudio, do .env.development do ProcStudio-Docker; nunca colar em commit>
curl -s -H "X-API-KEY: $KEY" https://procstudio.api.br/api/v1/lawyer/PR_54159 | python3 -c 'import json,sys; d=json.load(sys.stdin); s=d["principal"]["societies"][0]; print(s["name"], s["cnpj"], s["receita"]["situacao_cadastral"], [p["nome"] for p in s["partners"]])'
curl -s -H "X-API-KEY: $KEY" https://procstudio.api.br/api/v1/cnpj/49780032000146 | head -c 400
curl -s -H "X-API-KEY: $KEY" "https://procstudio.api.br/api/v1/receita/companies?uf=PR&unmatched=true&founded_since=2026-08-01&limit=3" | head -c 600
```

Expected: a sociedade do Bruno com CNPJ `49780032000146`, situação Ativa e 2 sócios; o `/cnpj` devolvendo a mesma firma; a listagem com 3 prospects do PR fundados em agosto.

- [ ] **Step 5: Registrar**

Comentar na PR (ou no card do Linear) os números reais da carga e o tempo. Atualizar a memória do projeto (`project_receita_cnpj_enrichment.md`) com "PR 1 em produção em <data>, números". Só então começam os planos da PR 2 (ProcStudio) e PR 3 (FFD).

---

## Self-review

**Spec coverage (§5 e §8):** 5.1 tabelas → Task 1; 5.2 importador → Task 3; 5.3 normalização → Task 2; 5.4 matcher e linker → Tasks 4 e 5; 5.5 refresh → Task 9; 5.6 API (payload, `/cnpj`, `/receita/companies`, changelog) → Tasks 6, 7, 8, 10; 5.7 testes → distribuídos; §8 (429 → 503 sem cache, baixadas visíveis, cartórios fora por default, raw guardado) → Tasks 7, 8, 1, 3. Primeira carga → Task 11.

**Divergências da spec, deliberadas:** `cpf_mascarado` → `documento`; `UsageEvent` nas rotas novas via `UsageTracking` (a spec pedia, está); `receita_companies.updated_at` indexado para `updated_since`.

**Tipos e nomes consistentes:** `Receita::NameNormalizer.call`, `Receita::Cnpj.normalize`, `Receita::RowMapper.company_attrs/partner_attrs`, `Receita::Importer#call/#import_records`, `Receita::SocietyMatcher::VERIFIED`, `Receita::CnpjLookup::Result#status`, `ReceitaCompanySerializer#receita_block/#partners_block/#as_json` — usados com o mesmo nome em todas as tarefas. Chaves de resposta (`cnpj`, `receita`, `partners`, `companies`, `meta.next_from_cnpj`) são as que a PR 2 e a PR 3 vão consumir.

**Review Focus:** 1 → Task 2 (`spec/lib/receita/cnpj_spec.rb`, alfanumérico) e Task 7 (422 sem chamar API); 2 → Task 4 (`cnpj_taken`); 3 → Task 3 (fixture com QSA vazio e sócio PJ) e Task 5 (PJ ignorado); 4 → Task 7 (429 e timeout); 5 → Task 8 (uf ausente, limit 9999 → 500).
