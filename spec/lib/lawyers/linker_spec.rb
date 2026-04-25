require 'rails_helper'

RSpec.describe Lawyers::Linker do
  describe '.apply' do
    # Synthetic OAB IDs prefixed to avoid collision with real production data when run against the dev DB.
    let(:principal)   { create(:lawyer, oab_id: 'TEST_PRIN_1',  full_name: 'TESTUSER PAULO MULLER', state: 'RS', suplementary: false, profession: 'ADVOGADO') }
    let(:bad_anchor)  { create(:lawyer, oab_id: 'TEST_BAD_1',   full_name: 'TESTUSER PAULO MULLER', state: 'BA', suplementary: true,  profession: 'SUPLEMENTAR', principal_lawyer_id: nil) }
    let(:misanchored) { create(:lawyer, oab_id: 'TEST_MIS_1',   full_name: 'TESTUSER PAULO MULLER', state: 'SP', suplementary: true,  profession: 'SUPLEMENTAR', principal_lawyer_id: bad_anchor.id) }
    let(:unlinked)    { create(:lawyer, oab_id: 'TEST_UNL_1',   full_name: 'TESTUSER PAULO MULLER', state: 'PR', suplementary: true,  profession: 'SUPLEMENTAR', principal_lawyer_id: nil) }

    it 'links unlinked supps to the principal' do
      principal; unlinked
      updates = [{ id: unlinked.id, oab_id: unlinked.oab_id, current_principal_id: nil, new_principal_id: principal.id }]

      result = described_class.apply(updates, dry_run: false)

      expect(result.linked).to eq(1)
      expect(result.reanchored).to eq(0)
      expect(unlinked.reload.principal_lawyer_id).to eq(principal.id)
      expect(unlinked.reload.suplementary).to be true
    end

    it 're-anchors misanchored supps to the principal (the PAULO MULLER fix)' do
      principal; misanchored
      updates = [{ id: misanchored.id, oab_id: misanchored.oab_id, current_principal_id: bad_anchor&.id, new_principal_id: principal.id }]

      result = described_class.apply(updates, dry_run: false)

      expect(result.reanchored).to eq(1)
      expect(result.linked).to eq(0)
      expect(misanchored.reload.principal_lawyer_id).to eq(principal.id)
    end

    it 'is a no-op under DRY_RUN' do
      principal; unlinked
      updates = [{ id: unlinked.id, oab_id: unlinked.oab_id, current_principal_id: nil, new_principal_id: principal.id }]

      described_class.apply(updates, dry_run: true)

      expect(unlinked.reload.principal_lawyer_id).to be_nil
    end

    it 'is idempotent — second run skips already-correct links' do
      principal; unlinked
      updates = [{ id: unlinked.id, oab_id: unlinked.oab_id, current_principal_id: nil, new_principal_id: principal.id }]

      described_class.apply(updates, dry_run: false)
      r2 = described_class.apply(updates, dry_run: false)

      expect(r2.linked + r2.reanchored).to eq(0)
      expect(r2.skipped).to eq(1)
    end

    it 'counts errors when an id is missing' do
      result = described_class.apply([{ id: -1, new_principal_id: 999 }], dry_run: false)
      expect(result.errors).to eq(1)
    end

    it 'classifier→linker end-to-end: PAULO MULLER fixture is fully repaired' do
      principal
      bad_anchor
      misanchored
      unlinked
      cluster = [principal, bad_anchor, misanchored, unlinked]

      result   = Lawyers::ClusterClassifier.classify(cluster)
      proposed = Lawyers::ClusterClassifier.proposed_links(result)

      expect(result[:type]).to eq(Lawyers::ClusterClassifier::SAFE_SINGLE_PRINCIPAL_WITH_REANCHOR)

      apply_result = described_class.apply(proposed, dry_run: false)

      expect(apply_result.errors).to eq(0)
      [bad_anchor, misanchored, unlinked].each do |l|
        expect(l.reload.principal_lawyer_id).to eq(principal.id)
        expect(l.reload.suplementary).to be true
      end
      expect(principal.reload.principal_lawyer_id).to be_nil
    end
  end
end
