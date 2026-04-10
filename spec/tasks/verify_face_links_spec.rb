require 'rails_helper'

RSpec.describe 'Face match links verification', type: :task do
  # These tests verify the face match links were applied correctly in any environment.
  # Run after applying rake tasks on production: bundle exec rspec spec/tasks/verify_face_links_spec.rb

  describe 'known singles (must be linked)' do
    # DAVID SOMBRA PEIXOTO: CE_16477 (ADVOGADO) -> 19 supplementaries
    it 'DAVID SOMBRA PEIXOTO: supplementaries point to CE_16477' do
      principal = Lawyer.find_by(oab_id: 'CE_16477')
      skip 'CE_16477 not in this DB' unless principal

      supps = %w[AC_4775 AL_14673 AM_1175 AP_3503 BA_39585 DF_52043 ES_31885
                 GO_43245 MG_195596 MS_24595 PA_24346 PB_16477 PE_2038 PI_7847
                 RJ_185026 RN_807 RO_8222 SP_388253 TO_9777]

      supps.each do |oab|
        lawyer = Lawyer.find_by(oab_id: oab)
        next unless lawyer
        expect(lawyer.principal_lawyer_id).to eq(principal.id),
          "Expected #{oab} to link to #{principal.oab_id} (id: #{principal.id}), got #{lawyer.principal_lawyer_id}"
      end
    end

    # GUSTAVO DAL BOSCO: multiple supplementaries
    it 'GUSTAVO DAL BOSCO: has linked supplementaries' do
      principal = Lawyer.find_by(oab_id: 'PR_66498')
      skip 'PR_66498 not in this DB' unless principal

      linked = Lawyer.where(principal_lawyer_id: principal.id)
      expect(linked.count).to be >= 10, "Expected at least 10 supplementaries for GUSTAVO DAL BOSCO"
    end

    # CAROLINA LOUZADA PETRARCA
    it 'CAROLINA LOUZADA PETRARCA: has linked supplementaries' do
      principal = Lawyer.find_by(oab_id: 'PR_50592')
      skip 'PR_50592 not in this DB' unless principal

      linked = Lawyer.where(principal_lawyer_id: principal.id)
      expect(linked.count).to be >= 10
    end

    # ADAHILTON DE OLIVEIRA PINHO (batch 21-50)
    it 'ADAHILTON DE OLIVEIRA PINHO: SP_152305 has supplementaries linked' do
      principal = Lawyer.find_by(oab_id: 'SP_152305')
      skip 'SP_152305 not in this DB' unless principal

      linked = Lawyer.where(principal_lawyer_id: principal.id)
      expect(linked.count).to be >= 15, "Expected at least 15 supplementaries for ADAHILTON"
    end
  end

  describe 'known edge cases (multi-person, must be separate)' do
    # PAULO ROBERTO DOS SANTOS: 2 different people
    it 'PAULO ROBERTO DOS SANTOS: DF_11837 and MG_171899 are separate people' do
      p1 = Lawyer.find_by(oab_id: 'DF_11837')
      p2 = Lawyer.find_by(oab_id: 'MG_171899')
      skip 'DF_11837 or MG_171899 not in this DB' unless p1 && p2

      # MG_164361 should link to DF_11837
      mg = Lawyer.find_by(oab_id: 'MG_164361')
      expect(mg&.principal_lawyer_id).to eq(p1.id) if mg

      # PR_33243 should link to MG_171899, NOT to DF_11837
      pr = Lawyer.find_by(oab_id: 'PR_33243')
      expect(pr&.principal_lawyer_id).to eq(p2.id) if pr
      expect(pr&.principal_lawyer_id).not_to eq(p1.id) if pr
    end

    # CARLOS ALBERTO FERNANDES: 3 different people
    it 'CARLOS ALBERTO FERNANDES: 3 separate clusters' do
      p1 = Lawyer.find_by(oab_id: 'DF_42173')
      p2 = Lawyer.find_by(oab_id: 'MG_762')
      p3 = Lawyer.find_by(oab_id: 'MS_7248')
      skip 'Missing OABs' unless p1 && p2 && p3

      # SP_61447 -> MG_762
      sp61 = Lawyer.find_by(oab_id: 'SP_61447')
      expect(sp61&.principal_lawyer_id).to eq(p2.id) if sp61

      # SP_57203 -> MS_7248
      sp57 = Lawyer.find_by(oab_id: 'SP_57203')
      expect(sp57&.principal_lawyer_id).to eq(p3.id) if sp57

      # None should point to DF_42173's cluster
      expect(sp61&.principal_lawyer_id).not_to eq(p1.id) if sp61
      expect(sp57&.principal_lawyer_id).not_to eq(p1.id) if sp57
    end

    # ADRIANO SANTOS DE ALMEIDA: 2 people, PE_35607 alone
    it 'ADRIANO SANTOS DE ALMEIDA: AC_6640 cluster is separate from PE_35607' do
      pe = Lawyer.find_by(oab_id: 'PE_35607')
      ac = Lawyer.find_by(oab_id: 'AC_6640')
      skip 'PE_35607 or AC_6640 not in this DB' unless pe && ac

      # AC_6640 supplementaries should NOT point to PE_35607
      ac_supps = Lawyer.where(principal_lawyer_id: ac.id)
      expect(ac_supps.count).to be >= 10

      pe_supps = Lawyer.where(principal_lawyer_id: pe.id)
      expect(pe_supps.count).to eq(0), "PE_35607 should have 0 supplementaries (different person)"
    end
  end

  describe 'global consistency checks' do
    it 'no lawyer points to itself as principal' do
      self_refs = Lawyer.where('principal_lawyer_id = id')
      expect(self_refs.count).to eq(0), "Found #{self_refs.count} self-referencing lawyers"
    end

    it 'all principal_lawyer_ids reference existing lawyers' do
      orphans = Lawyer.where.not(principal_lawyer_id: nil)
                      .where.not(principal_lawyer_id: Lawyer.select(:id))
      expect(orphans.count).to eq(0), "Found #{orphans.count} orphan principal_lawyer_id references"
    end

    it 'linked lawyers have suplementary=true' do
      mismatched = Lawyer.where.not(principal_lawyer_id: nil).where(suplementary: false)
      expect(mismatched.count).to eq(0), "Found #{mismatched.count} linked lawyers with suplementary=false"
    end

    it 'at least 57000 lawyers are linked (sanity check)' do
      skip 'No lawyers in DB (test env)' if Lawyer.count == 0
      linked = Lawyer.where.not(principal_lawyer_id: nil).count
      expect(linked).to be >= 57000, "Only #{linked} linked, expected at least 57000"
    end
  end
end
