require 'rails_helper'

RSpec.describe Receita::CnpjLookup do
  let(:cnpj) { '11222333000181' }
  let(:api_url) { "https://api.opencnpj.org/#{cnpj}" }
  let(:api_body) do
    { 'cnpj' => cnpj, 'razao_social' => 'FIRMA DA API LTDA', 'situacao_cadastral' => 'Ativa', 'matriz_filial' => 'Matriz',
      'data_inicio_atividade' => '2020-01-10', 'cnae_principal' => '6911701', 'natureza_juridica' => 'Sociedade Simples Pura',
      'uf' => 'SP', 'municipio' => 'SAO PAULO', 'email' => 'x@y.com', 'telefones' => [], 'capital_social' => '1000,00',
      'QSA' => [ { 'nome_socio' => 'SOCIA UM', 'cnpj_cpf_socio' => '***111222**', 'qualificacao_socio' => 'Sócio-Administrador',
                  'data_entrada_sociedade' => '2020-01-10', 'identificador_socio' => 'Pessoa Física', 'faixa_etaria' => '41 a 50 anos' } ] }
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

  it 'erro de conexão fora da lista clássica vira unavailable sem gravar nada' do
    stub_request(:get, api_url).to_raise(Errno::ECONNRESET)
    expect(described_class.call(cnpj).status).to eq(:unavailable)
    expect(ReceitaCompany.where(cnpj: cnpj)).to be_empty
  end

  it 'corpo 200 que não é objeto JSON vira unavailable sem gravar nada' do
    stub_request(:get, api_url).to_return(status: 200, body: '[]')
    expect(described_class.call(cnpj).status).to eq(:unavailable)
    expect(ReceitaCompany.where(cnpj: cnpj)).to be_empty
  end
end
