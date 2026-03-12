require 'rails_helper'

RSpec.describe LawyerSociety, type: :model do
  describe 'validations' do
    it 'requires partnership_type' do
      ls = build(:lawyer_society, partnership_type: nil)
      expect(ls).not_to be_valid
    end

    it 'validates uniqueness of lawyer_id scoped to society_id' do
      lawyer = create(:lawyer)
      society = create(:society)
      create(:lawyer_society, lawyer: lawyer, society: society)

      duplicate = build(:lawyer_society, lawyer: lawyer, society: society)
      expect(duplicate).not_to be_valid
    end
  end

  describe 'associations' do
    it 'belongs to a lawyer' do
      ls = create(:lawyer_society)
      expect(ls.lawyer).to be_a(Lawyer)
    end

    it 'belongs to a society' do
      ls = create(:lawyer_society)
      expect(ls.society).to be_a(Society)
    end
  end

  describe 'partnership_type enum' do
    it 'allows socio type' do
      ls = build(:lawyer_society, partnership_type: :socio)
      expect(ls.socio?).to be true
    end

    it 'allows associado type' do
      ls = build(:lawyer_society, partnership_type: :associado)
      expect(ls.associado?).to be true
    end

    it 'allows socio_de_servico type' do
      ls = build(:lawyer_society, partnership_type: :socio_de_servico)
      expect(ls.socio_de_servico?).to be true
    end
  end

  describe 'capacity validation' do
    it 'prevents adding lawyer when society is at capacity' do
      society = create(:society, :with_lawyer, number_of_partners: 1)
      new_lawyer = create(:lawyer)

      ls = build(:lawyer_society, lawyer: new_lawyer, society: society)
      expect(ls).not_to be_valid
      expect(ls.errors[:society]).to include(a_string_matching(/at full capacity/))
    end
  end

  describe '#destroy_orphan_society callback' do
    it 'auto-deletes society when last member is removed' do
      society = create(:society, number_of_partners: 1)
      lawyer = create(:lawyer)
      lawyer_society = create(:lawyer_society, lawyer: lawyer, society: society)

      expect { lawyer_society.destroy }.to change(Society, :count).by(-1)
      expect(Society.exists?(society.id)).to be false
    end

    it 'does not delete society when other members remain' do
      society = create(:society, :with_lawyers, number_of_partners: 3, lawyers_count: 2)
      lawyer_society = society.lawyer_societies.first

      expect { lawyer_society.destroy }.not_to change(Society, :count)
      expect(Society.exists?(society.id)).to be true
    end

    it 'keeps the lawyer after society is auto-deleted' do
      society = create(:society, number_of_partners: 1)
      lawyer = create(:lawyer)
      lawyer_society = create(:lawyer_society, lawyer: lawyer, society: society)

      expect { lawyer_society.destroy }.not_to change(Lawyer, :count)
      expect(Lawyer.exists?(lawyer.id)).to be true
    end
  end
end
