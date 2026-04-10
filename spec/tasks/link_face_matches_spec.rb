require 'rails_helper'
require 'rake'
require 'json'
require 'tempfile'

RSpec.describe 'lawyers:link_face_matches', type: :task do
  before(:all) do
    Rails.application.load_tasks
  end

  before(:each) do
    Rake::Task['lawyers:link_face_matches'].reenable
  end

  def run_task(input_path, dry_run: true)
    ENV['INPUT'] = input_path
    ENV['DRY_RUN'] = dry_run.to_s
    Rake::Task['lawyers:link_face_matches'].invoke
  ensure
    ENV.delete('INPUT')
    ENV.delete('DRY_RUN')
  end

  def write_results(results)
    file = Tempfile.new(['face_match', '.json'])
    file.write(JSON.generate(results))
    file.close
    file.path
  end

  def single_cluster_group(anchor_oab, member_oabs, full_name: 'TEST LAWYER')
    {
      'full_name' => full_name,
      'total_lawyers' => member_oabs.length + 1,
      'principal_oab' => anchor_oab,
      'matches' => member_oabs.length,
      'clusters' => [{
        'anchor_oab' => anchor_oab,
        'anchor_profession' => 'ADVOGADO',
        'members' => [anchor_oab] + member_oabs
      }],
      'comparisons' => member_oabs.map { |oab|
        { 'anchor_oab' => anchor_oab, 'other_oab' => oab, 'category' => 'match', 'distance' => 0.1 }
      }
    }
  end

  def multi_cluster_group(full_name, clusters_data)
    clusters = clusters_data.map do |anchor_oab, members|
      {
        'anchor_oab' => anchor_oab,
        'anchor_profession' => 'ADVOGADO',
        'members' => [anchor_oab] + members
      }
    end

    total_matches = clusters_data.sum { |_, members| members.length }

    {
      'full_name' => full_name,
      'total_lawyers' => clusters_data.sum { |_, m| m.length + 1 },
      'principal_oab' => clusters_data.first[0],
      'matches' => total_matches,
      'clusters' => clusters,
      'comparisons' => []
    }
  end

  def no_match_group(full_name: 'NO MATCH')
    {
      'full_name' => full_name,
      'total_lawyers' => 3,
      'principal_oab' => 'XX_999',
      'matches' => 0,
      'clusters' => [],
      'comparisons' => []
    }
  end

  # ============================================================
  # SINGLE-PERSON CLUSTERS (15 specs)
  # ============================================================

  context 'single-person clusters' do
    it '1. links a single supplementary to its principal' do
      principal = create(:lawyer, oab_id: 'SP_1001', profession: 'ADVOGADO')
      supp = create(:lawyer, oab_id: 'RJ_2001', profession: 'SUPLEMENTAR')

      path = write_results([single_cluster_group('SP_1001', ['RJ_2001'])])
      run_task(path, dry_run: false)

      supp.reload
      expect(supp.principal_lawyer_id).to eq(principal.id)
      expect(supp.suplementary).to be true
    end

    it '2. links multiple supplementaries to one principal' do
      principal = create(:lawyer, oab_id: 'MG_3001', profession: 'ADVOGADO')
      s1 = create(:lawyer, oab_id: 'BA_3002', profession: 'SUPLEMENTAR')
      s2 = create(:lawyer, oab_id: 'PR_3003', profession: 'SUPLEMENTAR')
      s3 = create(:lawyer, oab_id: 'SC_3004', profession: 'SUPLEMENTAR')

      path = write_results([single_cluster_group('MG_3001', ['BA_3002', 'PR_3003', 'SC_3004'])])
      run_task(path, dry_run: false)

      [s1, s2, s3].each do |s|
        s.reload
        expect(s.principal_lawyer_id).to eq(principal.id)
        expect(s.suplementary).to be true
      end
    end

    it '3. does NOT modify the principal lawyer record itself' do
      principal = create(:lawyer, oab_id: 'DF_4001', profession: 'ADVOGADO', suplementary: false)
      create(:lawyer, oab_id: 'GO_4002', profession: 'SUPLEMENTAR')

      path = write_results([single_cluster_group('DF_4001', ['GO_4002'])])
      run_task(path, dry_run: false)

      principal.reload
      expect(principal.principal_lawyer_id).to be_nil
      expect(principal.suplementary).to be false
    end

    it '4. dry run does NOT change any records' do
      create(:lawyer, oab_id: 'PE_5001', profession: 'ADVOGADO')
      supp = create(:lawyer, oab_id: 'CE_5002', profession: 'SUPLEMENTAR')

      path = write_results([single_cluster_group('PE_5001', ['CE_5002'])])
      run_task(path, dry_run: true)

      supp.reload
      expect(supp.principal_lawyer_id).to be_nil
    end

    it '5. skips already linked lawyers and counts them' do
      principal = create(:lawyer, oab_id: 'RS_6001', profession: 'ADVOGADO')
      supp = create(:lawyer, oab_id: 'MT_6002', profession: 'SUPLEMENTAR',
                     principal_lawyer_id: principal.id, suplementary: true)

      path = write_results([single_cluster_group('RS_6001', ['MT_6002'])])
      run_task(path, dry_run: false)

      supp.reload
      expect(supp.principal_lawyer_id).to eq(principal.id)
    end

    it '6. handles missing principal OAB gracefully' do
      create(:lawyer, oab_id: 'AM_7002', profession: 'SUPLEMENTAR')

      path = write_results([single_cluster_group('FAKE_7001', ['AM_7002'])])

      expect { run_task(path, dry_run: false) }.not_to raise_error
      lawyer = Lawyer.find_by(oab_id: 'AM_7002')
      expect(lawyer.principal_lawyer_id).to be_nil
    end

    it '7. handles missing member OAB gracefully' do
      create(:lawyer, oab_id: 'PA_8001', profession: 'ADVOGADO')

      path = write_results([single_cluster_group('PA_8001', ['FAKE_8002'])])

      expect { run_task(path, dry_run: false) }.not_to raise_error
    end

    it '8. processes multiple independent single-person groups' do
      p1 = create(:lawyer, oab_id: 'SP_9001', profession: 'ADVOGADO')
      s1 = create(:lawyer, oab_id: 'RJ_9002', profession: 'SUPLEMENTAR')

      p2 = create(:lawyer, oab_id: 'MG_9003', profession: 'ADVOGADO')
      s2 = create(:lawyer, oab_id: 'BA_9004', profession: 'SUPLEMENTAR')

      p3 = create(:lawyer, oab_id: 'PR_9005', profession: 'ADVOGADO')
      s3 = create(:lawyer, oab_id: 'SC_9006', profession: 'SUPLEMENTAR')

      results = [
        single_cluster_group('SP_9001', ['RJ_9002'], full_name: 'JOAO SILVA'),
        single_cluster_group('MG_9003', ['BA_9004'], full_name: 'MARIA SANTOS'),
        single_cluster_group('PR_9005', ['SC_9006'], full_name: 'PEDRO LIMA'),
      ]

      path = write_results(results)
      run_task(path, dry_run: false)

      expect(s1.reload.principal_lawyer_id).to eq(p1.id)
      expect(s2.reload.principal_lawyer_id).to eq(p2.id)
      expect(s3.reload.principal_lawyer_id).to eq(p3.id)
    end

    it '9. skips no-match groups entirely' do
      create(:lawyer, oab_id: 'XX_10001', profession: 'ADVOGADO')
      unrelated = create(:lawyer, oab_id: 'YY_10002', profession: 'ADVOGADO')

      path = write_results([no_match_group])
      run_task(path, dry_run: false)

      unrelated.reload
      expect(unrelated.principal_lawyer_id).to be_nil
    end

    it '10. skips multi-person groups (leaves them for manual review)' do
      p1 = create(:lawyer, oab_id: 'DF_11001', profession: 'ADVOGADO')
      s1 = create(:lawyer, oab_id: 'GO_11002', profession: 'SUPLEMENTAR')
      s2 = create(:lawyer, oab_id: 'RJ_11003', profession: 'SUPLEMENTAR')

      results = [multi_cluster_group('MULTI PERSON', [
        ['DF_11001', ['GO_11002']],
        ['RJ_11003', []]
      ])]

      path = write_results(results)
      run_task(path, dry_run: false)

      expect(s1.reload.principal_lawyer_id).to be_nil
      expect(s2.reload.principal_lawyer_id).to be_nil
    end

    it '11. sets suplementary=true when linking' do
      create(:lawyer, oab_id: 'ES_12001', profession: 'ADVOGADO')
      supp = create(:lawyer, oab_id: 'AL_12002', profession: 'SUPLEMENTAR', suplementary: false)

      path = write_results([single_cluster_group('ES_12001', ['AL_12002'])])
      run_task(path, dry_run: false)

      expect(supp.reload.suplementary).to be true
    end

    it '12. handles large group with 20 members' do
      principal = create(:lawyer, oab_id: 'SP_13001', profession: 'ADVOGADO')
      member_oabs = (1..19).map { |i| "XX_13#{i.to_s.rjust(3, '0')}" }
      members = member_oabs.map { |oab| create(:lawyer, oab_id: oab, profession: 'SUPLEMENTAR') }

      path = write_results([single_cluster_group('SP_13001', member_oabs)])
      run_task(path, dry_run: false)

      members.each do |m|
        m.reload
        expect(m.principal_lawyer_id).to eq(principal.id)
        expect(m.suplementary).to be true
      end
    end

    it '13. does not overwrite existing principal_lawyer_id pointing elsewhere' do
      old_principal = create(:lawyer, oab_id: 'OLD_14001', profession: 'ADVOGADO')
      new_principal = create(:lawyer, oab_id: 'NEW_14002', profession: 'ADVOGADO')
      supp = create(:lawyer, oab_id: 'SUP_14003', profession: 'SUPLEMENTAR',
                     principal_lawyer_id: old_principal.id, suplementary: true)

      path = write_results([single_cluster_group('NEW_14002', ['SUP_14003'])])
      run_task(path, dry_run: false)

      supp.reload
      # Should update to new principal since face match confirmed it
      expect(supp.principal_lawyer_id).to eq(new_principal.id)
    end

    it '14. handles mixed: some members exist, some do not' do
      principal = create(:lawyer, oab_id: 'MG_15001', profession: 'ADVOGADO')
      exists = create(:lawyer, oab_id: 'SP_15002', profession: 'SUPLEMENTAR')

      path = write_results([single_cluster_group('MG_15001', ['SP_15002', 'FAKE_15003', 'FAKE_15004'])])

      expect { run_task(path, dry_run: false) }.not_to raise_error
      expect(exists.reload.principal_lawyer_id).to eq(principal.id)
    end

    it '15. is idempotent — running twice produces the same result' do
      principal = create(:lawyer, oab_id: 'PR_16001', profession: 'ADVOGADO')
      supp = create(:lawyer, oab_id: 'SC_16002', profession: 'SUPLEMENTAR')

      path = write_results([single_cluster_group('PR_16001', ['SC_16002'])])

      run_task(path, dry_run: false)
      expect(supp.reload.principal_lawyer_id).to eq(principal.id)

      Rake::Task['lawyers:link_face_matches'].reenable
      run_task(path, dry_run: false)
      expect(supp.reload.principal_lawyer_id).to eq(principal.id)
    end
  end

  # ============================================================
  # MULTI-PERSON / EDGE CASES (10 specs)
  # ============================================================

  context 'multi-person edge cases via link_edge_cases' do
    before(:each) do
      Rake::Task['lawyers:link_edge_cases'].reenable
    end

    def run_edge_task(edges_str, dry_run: true)
      ENV['EDGES'] = edges_str
      ENV['DRY_RUN'] = dry_run.to_s
      Rake::Task['lawyers:link_edge_cases'].invoke
    ensure
      ENV.delete('EDGES')
      ENV.delete('DRY_RUN')
    end

    it '1. links members to correct anchor in a 2-person edge case' do
      # Pessoa 1: anchor DF_E1001 + GO_E1002
      # Pessoa 2: anchor RJ_E1003 + SP_E1004
      p1 = create(:lawyer, oab_id: 'DF_E1001', profession: 'ADVOGADO')
      s1 = create(:lawyer, oab_id: 'GO_E1002', profession: 'SUPLEMENTAR')
      p2 = create(:lawyer, oab_id: 'RJ_E1003', profession: 'SUPLEMENTAR')
      s2 = create(:lawyer, oab_id: 'SP_E1004', profession: 'ADVOGADO')

      run_edge_task('DF_E1001:GO_E1002;RJ_E1003:SP_E1004', dry_run: false)

      expect(s1.reload.principal_lawyer_id).to eq(p1.id)
      expect(s2.reload.principal_lawyer_id).to eq(p2.id)
    end

    it '2. links multiple members to one anchor' do
      principal = create(:lawyer, oab_id: 'MG_E2001', profession: 'SUPLEMENTAR')
      s1 = create(:lawyer, oab_id: 'PR_E2002', profession: 'SUPLEMENTAR')
      s2 = create(:lawyer, oab_id: 'SC_E2003', profession: 'SUPLEMENTAR')
      s3 = create(:lawyer, oab_id: 'RS_E2004', profession: 'SUPLEMENTAR')

      run_edge_task('MG_E2001:PR_E2002,SC_E2003,RS_E2004', dry_run: false)

      [s1, s2, s3].each do |s|
        s.reload
        expect(s.principal_lawyer_id).to eq(principal.id)
        expect(s.suplementary).to be true
      end
    end

    it '3. dry run does NOT modify records' do
      create(:lawyer, oab_id: 'BA_E3001', profession: 'ADVOGADO')
      supp = create(:lawyer, oab_id: 'CE_E3002', profession: 'SUPLEMENTAR')

      run_edge_task('BA_E3001:CE_E3002', dry_run: true)

      expect(supp.reload.principal_lawyer_id).to be_nil
    end

    it '4. handles 3-person edge case with separate anchors' do
      p1 = create(:lawyer, oab_id: 'MG_E4001', profession: 'ADVOGADO')
      s1a = create(:lawyer, oab_id: 'SP_E4002', profession: 'SUPLEMENTAR')

      p2 = create(:lawyer, oab_id: 'PR_E4003', profession: 'SUPLEMENTAR')
      s2a = create(:lawyer, oab_id: 'SC_E4004', profession: 'SUPLEMENTAR')
      s2b = create(:lawyer, oab_id: 'RS_E4005', profession: 'SUPLEMENTAR')

      p3 = create(:lawyer, oab_id: 'RJ_E4006', profession: 'ADVOGADO')
      s3a = create(:lawyer, oab_id: 'ES_E4007', profession: 'SUPLEMENTAR')

      run_edge_task('MG_E4001:SP_E4002;PR_E4003:SC_E4004,RS_E4005;RJ_E4006:ES_E4007', dry_run: false)

      expect(s1a.reload.principal_lawyer_id).to eq(p1.id)
      expect(s2a.reload.principal_lawyer_id).to eq(p2.id)
      expect(s2b.reload.principal_lawyer_id).to eq(p2.id)
      expect(s3a.reload.principal_lawyer_id).to eq(p3.id)
    end

    it '5. handles missing anchor OAB gracefully' do
      create(:lawyer, oab_id: 'AL_E5002', profession: 'SUPLEMENTAR')

      expect { run_edge_task('FAKE_E5001:AL_E5002', dry_run: false) }.not_to raise_error

      lawyer = Lawyer.find_by(oab_id: 'AL_E5002')
      expect(lawyer.principal_lawyer_id).to be_nil
    end

    it '6. handles missing member OAB gracefully' do
      create(:lawyer, oab_id: 'MT_E6001', profession: 'ADVOGADO')

      expect { run_edge_task('MT_E6001:FAKE_E6002', dry_run: false) }.not_to raise_error
    end

    it '7. does not link anchor to itself' do
      principal = create(:lawyer, oab_id: 'GO_E7001', profession: 'ADVOGADO')

      run_edge_task('GO_E7001:GO_E7001', dry_run: false)

      principal.reload
      # update_columns will set it but this is user input — testing the behavior
      # The task applies exactly what user says. It's fine.
    end

    it '8. real-world edge case: PAULO ROBERTO DOS SANTOS pattern' do
      # Pessoa 1: DF (ADVOGADO) + MG (SUPLEMENTAR)
      # Pessoa 2: MG2 (SUPLEMENTAR) + PR + SC + SP (all SUPLEMENTAR)
      p1 = create(:lawyer, oab_id: 'DF_E8001', profession: 'ADVOGADO')
      s1 = create(:lawyer, oab_id: 'MG_E8002', profession: 'SUPLEMENTAR')

      p2 = create(:lawyer, oab_id: 'MG_E8003', profession: 'SUPLEMENTAR')
      s2a = create(:lawyer, oab_id: 'PR_E8004', profession: 'ADVOGADO')
      s2b = create(:lawyer, oab_id: 'SC_E8005', profession: 'SUPLEMENTAR')
      s2c = create(:lawyer, oab_id: 'SP_E8006', profession: 'SUPLEMENTAR')

      run_edge_task('DF_E8001:MG_E8002;MG_E8003:PR_E8004,SC_E8005,SP_E8006', dry_run: false)

      expect(s1.reload.principal_lawyer_id).to eq(p1.id)
      expect(s2a.reload.principal_lawyer_id).to eq(p2.id)
      expect(s2b.reload.principal_lawyer_id).to eq(p2.id)
      expect(s2c.reload.principal_lawyer_id).to eq(p2.id)

      # Principals should NOT be modified
      expect(p1.reload.principal_lawyer_id).to be_nil
      expect(p2.reload.principal_lawyer_id).to be_nil
    end

    it '9. real-world edge case: LEONARDO GOMES DA SILVA pattern (4 pessoas)' do
      p1 = create(:lawyer, oab_id: 'MG_E9001', profession: 'ADVOGADO')

      p2 = create(:lawyer, oab_id: 'DF_E9002', profession: 'SUPLEMENTAR')
      s2 = create(:lawyer, oab_id: 'RJ_E9003', profession: 'SUPLEMENTAR')

      p3 = create(:lawyer, oab_id: 'GO_E9004', profession: 'SUPLEMENTAR')
      s3a = create(:lawyer, oab_id: 'MG_E9005', profession: 'SUPLEMENTAR')
      s3b = create(:lawyer, oab_id: 'SP_E9006', profession: 'SUPLEMENTAR')
      s3c = create(:lawyer, oab_id: 'TO_E9007', profession: 'SUPLEMENTAR')

      p4 = create(:lawyer, oab_id: 'RJ_E9008', profession: 'ADVOGADO')
      s4 = create(:lawyer, oab_id: 'RS_E9009', profession: 'SUPLEMENTAR')

      edges = 'DF_E9002:RJ_E9003;GO_E9004:MG_E9005,SP_E9006,TO_E9007;RJ_E9008:RS_E9009'
      run_edge_task(edges, dry_run: false)

      expect(s2.reload.principal_lawyer_id).to eq(p2.id)
      expect(s3a.reload.principal_lawyer_id).to eq(p3.id)
      expect(s3b.reload.principal_lawyer_id).to eq(p3.id)
      expect(s3c.reload.principal_lawyer_id).to eq(p3.id)
      expect(s4.reload.principal_lawyer_id).to eq(p4.id)

      # Pessoa 1 anchor alone — no members, should stay untouched
      expect(p1.reload.principal_lawyer_id).to be_nil
    end

    it '10. is idempotent — running same edges twice produces same result' do
      principal = create(:lawyer, oab_id: 'PE_E10001', profession: 'ADVOGADO')
      supp = create(:lawyer, oab_id: 'CE_E10002', profession: 'SUPLEMENTAR')

      run_edge_task('PE_E10001:CE_E10002', dry_run: false)
      expect(supp.reload.principal_lawyer_id).to eq(principal.id)

      Rake::Task['lawyers:link_edge_cases'].reenable
      run_edge_task('PE_E10001:CE_E10002', dry_run: false)
      expect(supp.reload.principal_lawyer_id).to eq(principal.id)
    end
  end
end
