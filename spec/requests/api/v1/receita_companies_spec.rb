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

  it 'situacao=Baixada devolve só baixadas' do
    create(:receita_company, uf: 'PR', cnpj: '10000000000100')
    baixada = create(:receita_company, uf: 'PR', cnpj: '10000000000200', situacao_cadastral: 'Baixada')

    expect(get_companies(uf: 'PR', situacao: 'Baixada')['companies'].map { |c| c['cnpj'] }).to eq([baixada.cnpj])
  end

  it 'natureza=all não filtra e reporta all em filters_applied' do
    create(:receita_company, uf: 'PR', cnpj: '10000000000100')
    cartorio = create(:receita_company, uf: 'PR', cnpj: '10000000000200', natureza_juridica: 'Serviço Notarial e Registral (Cartório)')

    body = get_companies(uf: 'PR', natureza: 'all')
    expect(body['companies'].map { |c| c['cnpj'] }).to include(cartorio.cnpj)
    expect(body['meta']['filters_applied']['natureza']).to eq('all')
  end

  it 'devolve 400 em pt-BR para datas inválidas' do
    %i[founded_since updated_since].each do |param|
      get '/api/v1/receita/companies', params: { uf: 'PR', param => 'garbage' }, headers: headers
      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body['error']).to start_with('Parâmetro de data inválido')
    end
  end

  it 'não gera N+1 ao serializar sócios' do
    count_queries = lambda do
      count = 0
      counter = ->(*, payload) { count += 1 unless payload[:name] =~ /SCHEMA|TRANSACTION/ }
      ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') { get '/api/v1/receita/companies', params: { uf: 'PR' }, headers: headers }
      count
    end
    make = lambda do |i|
      company = create(:receita_company, uf: 'PR', cnpj: format('%014d', 40_000_000_000_100 + i * 100))
      create(:receita_partner, receita_company: company, lawyer: create(:lawyer), last_seen_release: company.release)
    end

    make.call(0)
    count_queries.call # aquece caches (api key, schema)
    one = count_queries.call
    2.times { |i| make.call(i + 1) }
    expect(count_queries.call).to eq(one)
  end
end
