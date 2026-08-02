require 'rails_helper'

RSpec.describe Society, type: :model do
  describe 'validations' do
    it 'requires inscricao' do
      society = build(:society, inscricao: nil)
      expect(society).not_to be_valid
    end

    it 'requires name' do
      society = build(:society, name: nil)
      expect(society).not_to be_valid
    end

    it 'requires state' do
      society = build(:society, state: nil)
      expect(society).not_to be_valid
    end

    it 'requires number_of_partners' do
      society = build(:society, number_of_partners: nil)
      expect(society).not_to be_valid
    end

    it 'validates uniqueness of inscricao' do
      create(:society, inscricao: 12345)
      society = build(:society, inscricao: 12345)
      expect(society).not_to be_valid
    end
  end

  # A aba "Sociedade de Advogados" do portal da OAB-MG não expõe inscrição
  # nenhuma — só nome, endereço, CEP, telefone, e-mail e site. Essas sociedades
  # são identificadas pelo advogado que as revelou.
  describe 'sociedade vinda do portal da OAB (sem inscrição)' do
    let(:portal_attrs) do
      { inscricao: nil, source: Society::OAB_PORTAL, oab_id: 'MG_206787_SOCIEDADE',
        state: 'MG', name: 'DANUBIA ROSARIO - SOCIEDADE INDIVIDUAL DE ADVOCACIA',
        number_of_partners: 1 }
    end

    it 'é válida sem inscrição quando a origem é o portal' do
      expect(build(:society, **portal_attrs)).to be_valid
    end

    it 'exige oab_id, que é a chave dessas linhas' do
      expect(build(:society, **portal_attrs, oab_id: nil)).not_to be_valid
    end

    it 'segue exigindo inscrição para o que vem do CNA' do
      expect(build(:society, inscricao: nil, source: 'cna')).not_to be_valid
    end

    it 'permite várias sociedades do portal sem inscrição (nil não colide)' do
      create(:society, **portal_attrs)
      outra = build(:society, **portal_attrs, oab_id: 'MG_206788_SOCIEDADE', name: 'OUTRA')
      expect(outra).to be_valid
    end

    it 'aparece no escopo from_oab_portal' do
      portal = create(:society, **portal_attrs)
      create(:society, inscricao: 999_111, source: 'cna')
      expect(Society.from_oab_portal).to contain_exactly(portal)
    end
  end

  describe 'associations' do
    it 'has many lawyer_societies' do
      society = create(:society, :with_lawyers, number_of_partners: 2, lawyers_count: 2)
      expect(society.lawyer_societies.count).to eq(2)
    end

    it 'has many lawyers through lawyer_societies' do
      society = create(:society, :with_lawyers, number_of_partners: 2, lawyers_count: 2)
      expect(society.lawyers.count).to eq(2)
    end

    it 'destroys lawyer_societies when destroyed' do
      society = create(:society, :with_lawyers, number_of_partners: 2, lawyers_count: 2)
      expect { society.destroy }.to change(LawyerSociety, :count).by(-2)
    end
  end

  describe 'scopes' do
    describe '.with_members' do
      it 'returns societies that have at least one lawyer' do
        society_with_member = create(:society, :with_lawyer)
        society_without_member = create(:society)

        expect(Society.with_members).to include(society_with_member)
        expect(Society.with_members).not_to include(society_without_member)
      end
    end

    describe '.orphans' do
      it 'returns societies with no lawyers' do
        society_with_member = create(:society, :with_lawyer)
        society_without_member = create(:society)

        expect(Society.orphans).to include(society_without_member)
        expect(Society.orphans).not_to include(society_with_member)
      end
    end
  end

  describe '#can_add_lawyer?' do
    it 'returns true when society has room' do
      society = create(:society, number_of_partners: 3)
      expect(society.can_add_lawyer?).to be true
    end

    # Deixou de ser portão: sempre aceita. `at_capacity?`/`remaining_spots`
    # seguem informativos e continuam sendo servidos pelo SocietySerializer.
    it 'continua true mesmo com a sociedade lotada' do
      society = create(:society, :with_lawyer, number_of_partners: 1)
      expect(society.can_add_lawyer?).to be true
      expect(society.at_capacity?).to be true
    end
  end

  describe '#at_capacity?' do
    it 'returns false when society has room' do
      society = create(:society, number_of_partners: 3)
      expect(society.at_capacity?).to be false
    end

    it 'returns true when society is full' do
      society = create(:society, :with_lawyer, number_of_partners: 1)
      expect(society.at_capacity?).to be true
    end
  end

  describe '#has_members?' do
    it 'returns true when society has lawyers' do
      society = create(:society, :with_lawyer)
      expect(society.has_members?).to be true
    end

    it 'returns false when society has no lawyers' do
      society = create(:society)
      expect(society.has_members?).to be false
    end
  end

  describe '#orphan?' do
    it 'returns false when society has lawyers' do
      society = create(:society, :with_lawyer)
      expect(society.orphan?).to be false
    end

    it 'returns true when society has no lawyers' do
      society = create(:society)
      expect(society.orphan?).to be true
    end
  end

  describe '.destroy_orphans!' do
    it 'destroys all societies without members' do
      orphan1 = create(:society)
      orphan2 = create(:society)
      society_with_member = create(:society, :with_lawyer)

      expect { Society.destroy_orphans! }.to change(Society, :count).by(-2)
      expect(Society.exists?(orphan1.id)).to be false
      expect(Society.exists?(orphan2.id)).to be false
      expect(Society.exists?(society_with_member.id)).to be true
    end
  end

  describe 'cascade deletion' do
    it 'destroys associated lawyer_societies when destroyed' do
      society = create(:society, :with_lawyers, number_of_partners: 3, lawyers_count: 2)
      expect { society.destroy }.to change(LawyerSociety, :count).by(-2)
    end

    it 'does not destroy the lawyers themselves' do
      society = create(:society, :with_lawyers, number_of_partners: 3, lawyers_count: 2)
      expect { society.destroy }.not_to change(Lawyer, :count)
    end
  end
end
