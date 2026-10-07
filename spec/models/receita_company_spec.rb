require 'rails_helper'

RSpec.describe ReceitaCompany, type: :model do
  it 'belongs_to society (optional)' do
    expect(described_class.reflect_on_association(:society).options[:optional]).to be_truthy
  end

  it 'has_many receita_partners (dependent: delete_all)' do
    expect(described_class.reflect_on_association(:receita_partners).options[:dependent]).to eq(:delete_all)
  end

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
