require 'rails_helper'

# Verifies the hypothesis behind `lawyers:find_unlinked_clusters`:
# new supplementary OAB inscriptions that didn't go through the face-matcher batch
# can be linked to their principal by exact-name match, IFF the cluster is unambiguous
# (one ADVOGADO/A principal, no conflicting linked-supp evidence).
#
# Each real-DB spec skips if the expected OAB IDs aren't present in the local DB.
RSpec.describe Lawyers::ClusterClassifier, type: :task do
  C = Lawyers::ClusterClassifier

  def fetch(*oab_ids)
    Lawyer.where(oab_id: oab_ids.flatten).to_a
  end

  # Specs run pre-apply (cluster has unlinked supps -> SAFE_*) or post-apply (already linked -> NO_ACTION).
  # Either way, the classifier must identify the correct ADVOGADO/A as `principal`.
  SINGLE_PRINCIPAL_OK = [C::SAFE_SINGLE_PRINCIPAL, C::NO_ACTION].freeze
  REANCHOR_OK         = [C::SAFE_SINGLE_PRINCIPAL_WITH_REANCHOR, C::NO_ACTION].freeze

  # ---------------------------------------------------------------------------
  # SAFE_SINGLE_PRINCIPAL — auto-link candidates from real production data
  # ---------------------------------------------------------------------------
  describe 'SAFE_SINGLE_PRINCIPAL clusters (auto-link candidates)' do
    it '1) VALÉRIA NUNES GUIMARÃES — DF_40007 principal + PR_131010 (linked or to-be-linked)' do
      members = fetch('DF_40007', 'PR_131010')
      skip 'DF_40007 / PR_131010 not in this DB' if members.size < 2

      result = C.classify(members)
      expect(result[:type]).to be_in(SINGLE_PRINCIPAL_OK)
      expect(result[:principal].oab_id).to eq('DF_40007')
      pr = members.find { |m| m.oab_id == 'PR_131010' }
      expect(pr.principal_lawyer_id).to be_in([nil, members.find { |m| m.oab_id == 'DF_40007' }.id])
    end

    it '2) JOSÉ SANTANA LEÃO — SE_716 principal + BA_29629 (linked or to-be-linked)' do
      members = fetch('SE_716', 'BA_29629')
      skip 'cluster not in this DB' if members.size < 2

      result = C.classify(members)
      expect(result[:type]).to be_in(SINGLE_PRINCIPAL_OK)
      expect(result[:principal].oab_id).to eq('SE_716')
      ba = members.find { |m| m.oab_id == 'BA_29629' }
      expect(ba.principal_lawyer_id).to be_in([nil, members.find { |m| m.oab_id == 'SE_716' }.id])
    end

    it '3) ILÍDIA MONICA MUNDIM — GO_10798 principal + BA_33980 unlinked supp' do
      members = fetch('GO_10798', 'BA_33980')
      skip 'cluster not in this DB' if members.size < 2

      result = C.classify(members)
      expect(result[:type]).to be_in(SINGLE_PRINCIPAL_OK)
      expect(result[:principal].oab_id).to eq('GO_10798')
    end

    it '4) RAONI CÉZAR DINIZ GOMES — PE_37680 principal + BA_55634 unlinked supp' do
      members = fetch('PE_37680', 'BA_55634')
      skip 'cluster not in this DB' if members.size < 2

      result = C.classify(members)
      expect(result[:type]).to be_in(SINGLE_PRINCIPAL_OK)
      expect(result[:principal].oab_id).to eq('PE_37680')
    end

    it '5) MARCONE DE JESUS DE ARAGÃO — SE_8279 principal + BA_56927 unlinked supp' do
      members = fetch('SE_8279', 'BA_56927')
      skip 'cluster not in this DB' if members.size < 2

      result = C.classify(members)
      expect(result[:type]).to be_in(SINGLE_PRINCIPAL_OK)
      expect(result[:principal].oab_id).to eq('SE_8279')
    end

    it "6) ODAIR NOSSA SANT'ANA — apostrophe variants normalize to same key (ES_7264 principal)" do
      members = fetch('ES_7264', 'BA_55648')
      skip 'cluster not in this DB' if members.size < 2

      # Same normalized name despite SANT'ANA / SANT´ANA / SANT ANA spellings
      norms = members.map { |m| C.normalize(m.full_name) }.uniq
      expect(norms.size).to eq(1)

      result = C.classify(members)
      expect(result[:type]).to be_in(SINGLE_PRINCIPAL_OK)
      expect(result[:principal].oab_id).to eq('ES_7264')
    end

    it '7) JOSE ALENCAR DA SILVA — SP_290108 principal + BA_146 unlinked supp' do
      members = fetch('SP_290108', 'BA_146')
      skip 'cluster not in this DB' if members.size < 2

      result = C.classify(members)
      expect(result[:type]).to be_in(SINGLE_PRINCIPAL_OK)
      expect(result[:principal].oab_id).to eq('SP_290108')
    end
  end

  # ---------------------------------------------------------------------------
  # Re-anchor: face-matcher legacy clusters where supps were anchored on a sibling supp.
  # Classifier marks them safe to re-anchor onto the actual ADVOGADO.
  # ---------------------------------------------------------------------------
  describe 'SAFE_SINGLE_PRINCIPAL_WITH_REANCHOR (legacy face-matcher misanchor)' do
    it '7b) PAULO ANTÔNIO MULLER — RS_13449 is the principal; pre-apply: REANCHOR; post-apply: NO_ACTION' do
      principal  = Lawyer.find_by(oab_id: 'RS_13449')
      bad_anchor = Lawyer.find_by(oab_id: 'BA_61401')
      skip 'cluster not in this DB' unless principal && bad_anchor

      cluster = Lawyer.where("full_name ILIKE ?", '%PAULO%')
                      .to_a
                      .select { |l| C.normalize(l.full_name) == C.normalize('PAULO ANTÔNIO MULLER') }
      skip 'cluster too small' if cluster.size < 3

      result = C.classify(cluster)
      expect(result[:type]).to be_in(REANCHOR_OK)
      expect(result[:principal].oab_id).to eq('RS_13449')
      # Post-apply: BA_61401 is now linked to RS_13449 (no longer the bad anchor)
      expect(bad_anchor.reload.principal_lawyer_id).to be_in([nil, principal.id])
    end

    it '7c) PAULO ANTÔNIO MULLER — proposed_links yields zero updates after apply, or all targeting RS_13449 before apply' do
      principal  = Lawyer.find_by(oab_id: 'RS_13449')
      bad_anchor = Lawyer.find_by(oab_id: 'BA_61401')
      skip 'cluster not in this DB' unless principal && bad_anchor

      cluster = Lawyer.where("full_name ILIKE ?", '%PAULO%')
                      .to_a
                      .select { |l| C.normalize(l.full_name) == C.normalize('PAULO ANTÔNIO MULLER') }

      result   = C.classify(cluster)
      proposed = C.proposed_links(result)

      if result[:type] == C::NO_ACTION
        expect(proposed).to eq([])
        # All supps in cluster point to RS_13449 (the cluster is healed)
        cluster.select(&:suplementary).each do |s|
          expect(s.principal_lawyer_id).to eq(principal.id)
        end
      else
        expect(proposed.map { |u| u[:new_principal_id] }.uniq).to eq([principal.id])
      end
    end
  end

  # ---------------------------------------------------------------------------
  # AMBIGUOUS — must NOT be auto-linked
  # ---------------------------------------------------------------------------
  describe 'AMBIGUOUS_MULTI_PRINCIPAL clusters (must NOT auto-link)' do
    it '8) ADRIANA DE JESUS SANTOS — 3 distinct ADVOGADAs (SE_16561, SE_11969, GO_75170) + BA_59017 unlinked' do
      members = fetch('SE_16561', 'SE_11969', 'GO_75170', 'BA_59017')
      skip 'cluster not in this DB' if members.size < 4

      result = C.classify(members)
      expect(result[:type]).to eq(C::AMBIGUOUS_MULTI_PRINCIPAL)
      expect(result[:reason]).to eq(:multiple_principals)
      expect(result[:all_principals].map(&:oab_id))
        .to contain_exactly('SE_16561', 'SE_11969', 'GO_75170')
    end

    it '9) MARIA DAS GRACAS ROCHA — 2 ADVOGADAs (MG_45770, RJ_64099) + BA_39425 unlinked' do
      members = fetch('MG_45770', 'RJ_64099', 'BA_39425')
      skip 'cluster not in this DB' if members.size < 3

      result = C.classify(members)
      expect(result[:type]).to eq(C::AMBIGUOUS_MULTI_PRINCIPAL)
      expect(result[:reason]).to eq(:multiple_principals)
    end

    it '10) FABIO TEIXEIRA — 3 distinct principals (PR_32697, SP_164013, SP_325846) + unlinked BA_56038' do
      members = fetch('PR_32697', 'SP_164013', 'SP_325846', 'BA_56038')
      skip 'cluster not in this DB' if members.size < 4

      result = C.classify(members)
      expect(result[:type]).to eq(C::AMBIGUOUS_MULTI_PRINCIPAL)
      expect(result[:all_principals].size).to be >= 2
    end
  end

  # ---------------------------------------------------------------------------
  # Synthetic unit cases for branches not easily exercised by real data
  # ---------------------------------------------------------------------------
  describe 'classifier branches (synthetic)' do
    Member = Struct.new(
      :id, :oab_id, :full_name, :suplementary, :principal_lawyer_id,
      :profession, :situation, :state, :profile_picture, :cna_picture,
      keyword_init: true
    )

    def m(opts)
      Member.new({
        id: opts[:id], oab_id: opts[:oab_id], full_name: 'X', state: 'XX',
        suplementary: false, principal_lawyer_id: nil,
        profession: 'ADVOGADO', situation: 'REGULAR'
      }.merge(opts))
    end

    it '11a) SAFE_INFERRED_PRINCIPAL: cluster has no principal but linked supps unanimously point to one id OUTSIDE the cluster' do
      members = [
        m(id: 1, oab_id: 'PR_X', suplementary: true, profession: 'SUPLEMENTAR'),
        m(id: 2, oab_id: 'SP_X', suplementary: true, principal_lawyer_id: 999, profession: 'SUPLEMENTAR'),
        m(id: 3, oab_id: 'RJ_X', suplementary: true, principal_lawyer_id: 999, profession: 'SUPLEMENTAR')
      ]
      result = C.classify(members)
      expect(result[:type]).to eq(C::SAFE_INFERRED_PRINCIPAL)
      expect(result[:principal_id]).to eq(999)
    end

    it '11b) ORPHAN: inferred principal id IS itself a supp inside the cluster — must NOT be auto-linked (would create a self-reference)' do
      members = [
        # id=100 is itself a supp; the other supps point to it (face-matcher bad anchor with no real ADVOGADO)
        m(id: 100, oab_id: 'CE_BAD', suplementary: true, profession: 'SUPLEMENTAR'),
        m(id: 1,   oab_id: 'PR_X',   suplementary: true, principal_lawyer_id: 100, profession: 'SUPLEMENTAR'),
        m(id: 2,   oab_id: 'SP_X',   suplementary: true, principal_lawyer_id: 100, profession: 'SUPLEMENTAR')
      ]
      result = C.classify(members)
      expect(result[:type]).to eq(C::ORPHAN_NO_PRINCIPAL)
      expect(result[:reason]).to eq(:inferred_principal_is_a_supp)
      expect(C.proposed_links(result)).to eq([])
    end

    it '11c) proposed_links never proposes a self-reference (defensive guard)' do
      # Even if a synthetic SAFE_INFERRED somehow targets a member id, proposed_links must filter it out.
      result = {
        type:           C::SAFE_INFERRED_PRINCIPAL,
        principal_id:   100,
        unlinked_supps: [m(id: 100, oab_id: 'X', suplementary: true)]
      }
      expect(C.proposed_links(result)).to eq([])
    end

    it '12) ORPHAN_NO_PRINCIPAL: only supps, no principal, no linked supps either' do
      members = [
        m(id: 1, oab_id: 'PR_X', suplementary: true, profession: 'SUPLEMENTAR'),
        m(id: 2, oab_id: 'SP_X', suplementary: true, profession: 'SUPLEMENTAR')
      ]
      result = C.classify(members)
      expect(result[:type]).to eq(C::ORPHAN_NO_PRINCIPAL)
    end

    it '13a) AMBIGUOUS_DISAGREEMENT_OUTSIDE: bad anchor id is NOT in cluster (could be a homonym)' do
      members = [
        m(id: 100, oab_id: 'BA_P', profession: 'ADVOGADA', situation: 'situação regular'),
        m(id: 1,   oab_id: 'PR_X', suplementary: true, profession: 'SUPLEMENTAR'),
        m(id: 2,   oab_id: 'SP_X', suplementary: true, principal_lawyer_id: 999, profession: 'SUPLEMENTAR') # 999 not in cluster
      ]
      result = C.classify(members)
      expect(result[:type]).to eq(C::AMBIGUOUS_DISAGREEMENT_OUTSIDE)
      expect(result[:reason]).to eq(:linked_supps_point_outside_cluster)
    end

    it '13b) SAFE_REANCHOR: bad anchor IS in cluster and is itself a supp (PAULO MULLER pattern)' do
      members = [
        m(id: 100, oab_id: 'BA_P',   profession: 'ADVOGADA', situation: 'REGULAR'),
        m(id: 5,   oab_id: 'AC_BAD', suplementary: true, profession: 'SUPLEMENTAR'),
        m(id: 1,   oab_id: 'PR_X',   suplementary: true, principal_lawyer_id: 5, profession: 'SUPLEMENTAR'),
        m(id: 2,   oab_id: 'SP_X',   suplementary: true, principal_lawyer_id: 5, profession: 'SUPLEMENTAR')
      ]
      result = C.classify(members)
      expect(result[:type]).to eq(C::SAFE_SINGLE_PRINCIPAL_WITH_REANCHOR)
      expect(result[:bad_anchor_ids]).to eq([5])
      expect(result[:misanchored_supps].map(&:oab_id)).to contain_exactly('PR_X', 'SP_X')
    end

    it '14) NO_ACTION short-circuits when cluster is already fully and correctly linked' do
      members = [
        m(id: 100, oab_id: 'BA_P', profession: 'ADVOGADA', situation: 'REGULAR'),
        m(id: 2,   oab_id: 'SP_X', suplementary: true, principal_lawyer_id: 100, profession: 'SUPLEMENTAR')
      ]
      result = C.classify(members)
      expect(result[:type]).to eq(C::NO_ACTION)
      expect(C.proposed_links(result)).to eq([])
    end
  end

  # ---------------------------------------------------------------------------
  # Normalization
  # ---------------------------------------------------------------------------
  describe '.normalize' do
    it 'transliterates accented characters (É→E, Ã→A, Ç→C)' do
      expect(C.normalize('VALÉRIA NUNES GUIMARÃES'))
        .to eq(C.normalize('VALERIA NUNES GUIMARAES'))
    end

    it "collapses apostrophes and grave accents — SANT'ANA == SANT´ANA == SANT ANA" do
      a = C.normalize("ODAIR NOSSA SANT'ANA")
      b = C.normalize("ODAIR NOSSA SANT´ANA")
      c = C.normalize("ODAIR NOSSA SANT ANA")
      expect([a, b, c].uniq.size).to eq(1)
    end

    it 'collapses multi-space and trims edges' do
      expect(C.normalize("  JOSE   DA  SILVA  ")).to eq('JOSE DA SILVA')
    end
  end
end
