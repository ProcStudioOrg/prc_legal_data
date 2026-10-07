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
