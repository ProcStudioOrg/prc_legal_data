module Lawyers
  # Classifies a cluster of lawyer records sharing a normalized full_name.
  # The classifier is the brain — it owns all safety rules. The linker
  # (Lawyers::Linker) just applies what the classifier proposes.
  #
  # Five actionable categories:
  # - :safe_single_principal               → 1 ADVOGADO/A in cluster, only unlinked supps to link.
  # - :safe_single_principal_with_reanchor → 1 ADVOGADO/A, but some supps are misanchored on a SUPP inside this cluster.
  #                                          Safe to re-anchor because the bad anchor is itself a supp of the same person.
  # - :safe_inferred_principal             → 0 ADVOGADO/A in cluster, but linked supps unanimously point to one principal_id.
  # - :ambiguous_multi_principal           → 2+ ADVOGADO/As (different people, same name) — face match required.
  # - :ambiguous_disagreement_outside      → 1 ADVOGADO/A but linked supps point to a record outside the cluster (could be a homonym).
  # - :orphan_no_principal                 → only supps, no anchor at all.
  # - :no_action                           → nothing to do.
  module ClusterClassifier
    extend self

    SAFE_SINGLE_PRINCIPAL                = :safe_single_principal
    SAFE_SINGLE_PRINCIPAL_WITH_REANCHOR  = :safe_single_principal_with_reanchor
    SAFE_INFERRED_PRINCIPAL              = :safe_inferred_principal
    AMBIGUOUS_MULTI_PRINCIPAL            = :ambiguous_multi_principal
    AMBIGUOUS_DISAGREEMENT_OUTSIDE       = :ambiguous_disagreement_outside_cluster
    ORPHAN_NO_PRINCIPAL                  = :orphan_no_principal
    NO_ACTION                            = :no_action

    SAFE_TYPES = [
      SAFE_SINGLE_PRINCIPAL,
      SAFE_SINGLE_PRINCIPAL_WITH_REANCHOR,
      SAFE_INFERRED_PRINCIPAL
    ].freeze

    # Transliterates accents, uppercases, strips non-letter chars (keeps spaces),
    # collapses whitespace. SANT'ANA, SANT´ANA and SANT ANA all collapse to "SANT ANA".
    def normalize(name)
      ActiveSupport::Inflector
        .transliterate(name.to_s)
        .upcase
        .gsub(/[^A-Z\s]/, ' ')
        .gsub(/\s+/, ' ')
        .strip
    end

    # @param members [Array] all lawyers sharing one normalized full_name
    # @return [Hash] { type:, ... }
    def classify(members)
      supps         = members.select(&:suplementary)
      principals    = members.select do |l|
        !l.suplementary &&
          l.profession.to_s.match?(/ADVOGAD/i) &&
          l.situation.to_s.match?(/regular/i)
      end
      unlinked      = supps.select { |l| l.principal_lawyer_id.nil? }
      linked        = supps - unlinked
      linked_pids   = linked.map(&:principal_lawyer_id).uniq

      base = {
        all_principals:       principals,
        unlinked_supps:       unlinked,
        linked_supps:         linked,
        linked_principal_ids: linked_pids
      }

      case principals.size
      when 1
        principal   = principals.first
        disagreeing = linked.reject { |l| l.principal_lawyer_id == principal.id }

        if disagreeing.empty?
          if unlinked.empty?
            base.merge(type: NO_ACTION, principal: principal)
          else
            base.merge(type: SAFE_SINGLE_PRINCIPAL, principal: principal)
          end
        else
          # Some linked supps disagree. Re-anchor is safe iff every wrong anchor
          # is itself a supp inside this cluster (i.e. a sibling of the same person).
          member_by_id   = members.index_by(&:id)
          bad_anchor_ids = disagreeing.map(&:principal_lawyer_id).uniq
          all_inside     = bad_anchor_ids.all? { |aid| member_by_id[aid]&.suplementary }

          if all_inside
            base.merge(
              type:              SAFE_SINGLE_PRINCIPAL_WITH_REANCHOR,
              principal:         principal,
              misanchored_supps: disagreeing,
              bad_anchor_ids:    bad_anchor_ids
            )
          else
            base.merge(
              type:      AMBIGUOUS_DISAGREEMENT_OUTSIDE,
              principal: principal,
              reason:    :linked_supps_point_outside_cluster
            )
          end
        end

      when 0
        if unlinked.empty?
          base.merge(type: NO_ACTION)
        elsif linked_pids.size == 1
          target_id     = linked_pids.first
          target_member = members.find { |m| m.id == target_id }
          # Guard against the same bad-anchor pattern at the cluster level: if the inferred
          # principal id IS itself a supp inside this cluster, there is no real ADVOGADO/A
          # to anchor on, so face-match disambiguation is required — not a name-based fix.
          if target_member && target_member.suplementary
            base.merge(type: ORPHAN_NO_PRINCIPAL, reason: :inferred_principal_is_a_supp)
          else
            base.merge(type: SAFE_INFERRED_PRINCIPAL, principal_id: target_id)
          end
        else
          base.merge(type: ORPHAN_NO_PRINCIPAL)
        end

      else
        base.merge(type: AMBIGUOUS_MULTI_PRINCIPAL, reason: :multiple_principals)
      end
    end

    # Returns the concrete updates the linker should apply for a SAFE classification.
    # Returns [] for ambiguous/orphan clusters.
    #
    # @return [Array<Hash>] each: { id:, oab_id:, current_principal_id:, new_principal_id: }
    def proposed_links(result)
      target_id =
        case result[:type]
        when SAFE_SINGLE_PRINCIPAL, SAFE_SINGLE_PRINCIPAL_WITH_REANCHOR
          result[:principal].id
        when SAFE_INFERRED_PRINCIPAL
          result[:principal_id]
        else
          return []
        end

      candidates = (result[:unlinked_supps] || []) + (result[:misanchored_supps] || [])
      candidates
        .uniq(&:id)
        .reject { |l| l.principal_lawyer_id == target_id }
        .reject { |l| l.id == target_id } # belt-and-suspenders: never propose a self-reference
        .map do |l|
          {
            id:                   l.id,
            oab_id:               l.oab_id,
            current_principal_id: l.principal_lawyer_id,
            new_principal_id:     target_id
          }
        end
    end
  end
end
