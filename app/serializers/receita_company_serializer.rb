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
      capital_social: c.capital_social && format('%.2f', c.capital_social),
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
