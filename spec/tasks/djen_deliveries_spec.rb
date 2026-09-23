require 'rails_helper'
require 'rake'

RSpec.describe 'djen:deliveries', type: :task do
  before(:all) { Rails.application.load_tasks }

  let(:prod) { Djen::Destination.new(base_url: "https://api.example.com", token: "t") }
  let(:hml) { Djen::Destination.new(base_url: "https://api-hml.example.com", token: "t") }
  let(:lawyer) { create(:lawyer, oab_id: "PR_54159", oab_number: "54159", state: "PR") }
  let(:monitoring) { create(:djen_monitoring, lawyer: lawyer) }

  def run_task(name, *args)
    Rake::Task[name].reenable
    Rake::Task[name].invoke(*args)
  end

  describe 'mark_delivered' do
    it "stamps every existing comunicação as already delivered to the destination" do
      active = create(:djen_comunicacao, djen_monitoring: monitoring)
      cancelled = create(:djen_comunicacao, :cancelled, djen_monitoring: monitoring)
      already = create(:djen_comunicacao, :pushed, djen_monitoring: monitoring, to: prod)
      stamp = already.djen_deliveries.to(prod).first.pushed_at

      expect { run_task('djen:deliveries:mark_delivered', 'https://api.example.com/') }
        .to output(/2 comunicaç/).to_stdout

      expect(DjenComunicacao.pending_push_to(prod)).to be_empty
      expect(DjenComunicacao.pending_cancellation_push_to(prod)).to be_empty
      expect(active.djen_deliveries.to(prod).first.cancellation_pushed_at).to be_nil
      expect(cancelled.djen_deliveries.to(prod).first.cancellation_pushed_at).to be_present
      expect(already.djen_deliveries.to(prod).first.pushed_at).to be_within(1.second).of(stamp)
    end
  end

  describe 'reset' do
    it "forgets the deliveries of one lawyer to one destination so the next sweep re-pushes the ledger" do
      mine = create(:djen_comunicacao, :pushed, djen_monitoring: monitoring, to: prod, and_to: hml)
      other = create(:djen_comunicacao, :pushed, to: prod)

      expect { run_task('djen:deliveries:reset', 'https://api.example.com', 'pr_54159') }
        .to output(/1 entrega/).to_stdout

      expect(mine.djen_deliveries.map(&:destination)).to eq([ hml.key ])
      expect(other.djen_deliveries.to(prod)).to exist
    end

    it "resolves a supplementary OAB to the principal's monitoring" do
      supplementary = create(:lawyer, oab_id: "SP_388253", oab_number: "388253", state: "SP",
                                      principal_lawyer: lawyer)
      mine = create(:djen_comunicacao, :pushed, djen_monitoring: monitoring, to: prod)

      run_task('djen:deliveries:reset', 'https://api.example.com', supplementary.oab_id)

      expect(mine.djen_deliveries.to(prod)).not_to exist
    end

    it "fails loudly for an OAB that is not monitored" do
      expect { run_task('djen:deliveries:reset', 'https://api.example.com', 'PR_1') }
        .to raise_error(SystemExit)
    end
  end
end
