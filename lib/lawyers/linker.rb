module Lawyers
  # Applies a list of principal-link updates produced by ClusterClassifier#proposed_links.
  # Idempotent — re-running with the same input is a no-op.
  module Linker
    extend self

    Result = Struct.new(:planned, :linked, :reanchored, :skipped, :errors, keyword_init: true) do
      def total = linked + reanchored
    end

    # @param updates [Array<Hash>] each must have :id and :new_principal_id
    # @param dry_run [Boolean] when true, no DB writes
    # @yield [String] optional progress messages
    def apply(updates, dry_run: true)
      result = Result.new(planned: updates.size, linked: 0, reanchored: 0, skipped: 0, errors: 0)

      Lawyer.transaction do
        updates.each do |upd|
          lawyer = Lawyer.find_by(id: upd[:id] || upd['id'])
          unless lawyer
            yield "  WARN: lawyer id #{upd[:id] || upd['id']} not found" if block_given?
            result.errors += 1
            next
          end

          new_pid = upd[:new_principal_id] || upd['new_principal_id']
          old_pid = lawyer.principal_lawyer_id

          if old_pid == new_pid && lawyer.suplementary
            result.skipped += 1
            next
          end

          if dry_run
            yield "  [DRY] #{lawyer.oab_id}: principal_lawyer_id #{old_pid.inspect} -> #{new_pid}" if block_given?
          else
            lawyer.update_columns(principal_lawyer_id: new_pid, suplementary: true)
          end

          old_pid.nil? ? result.linked += 1 : result.reanchored += 1
        end
      end

      result
    end
  end
end
