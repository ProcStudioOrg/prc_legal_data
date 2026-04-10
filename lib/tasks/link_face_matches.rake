require 'json'

namespace :lawyers do
  desc "Link supplementary lawyers based on face match results (single-person clusters only)"
  task link_face_matches: :environment do
    input_file = ENV.fetch('INPUT', Rails.root.join('tmp', 'face_match_results.json').to_s)
    dry_run = ENV.fetch('DRY_RUN', 'true') == 'true'

    unless File.exist?(input_file)
      puts "ERROR: File not found: #{input_file}"
      exit 1
    end

    puts dry_run ? "=== DRY RUN (set DRY_RUN=false to apply) ===" : "=== APPLYING CHANGES ==="
    puts "Reading #{input_file}..."

    results = JSON.parse(File.read(input_file))

    total_groups = 0
    skipped_multi = 0
    skipped_no_match = 0
    linked = 0
    already_linked = 0
    errors = 0

    results.each do |group|
      clusters = group['clusters'] || []
      full_name = group['full_name']

      # Skip multi-person groups — those need manual review
      if clusters.length > 1
        skipped_multi += 1
        next
      end

      # Skip groups with no matches
      if clusters.empty? || (group['matches'] || 0) == 0
        skipped_no_match += 1
        next
      end

      total_groups += 1
      cluster = clusters[0]
      anchor_oab = cluster['anchor_oab']
      members = cluster['members'] || []

      # Find the anchor (principal) in DB
      principal = Lawyer.find_by(oab_id: anchor_oab)
      unless principal
        puts "  WARN: Principal #{anchor_oab} not found in DB, skipping group #{full_name}"
        errors += 1
        next
      end

      # Link each member (except anchor itself) to the principal
      members.each do |member_oab|
        next if member_oab == anchor_oab

        lawyer = Lawyer.find_by(oab_id: member_oab)
        unless lawyer
          puts "  WARN: Member #{member_oab} not found in DB"
          errors += 1
          next
        end

        if lawyer.principal_lawyer_id == principal.id
          already_linked += 1
          next
        end

        if dry_run
          puts "  [DRY] #{member_oab} -> principal #{anchor_oab} (id: #{principal.id})"
        else
          lawyer.update_columns(principal_lawyer_id: principal.id, suplementary: true)
        end
        linked += 1
      end
    end

    puts ""
    puts "=== Summary ==="
    puts "  Single-person groups processed: #{total_groups}"
    puts "  Skipped (multi-person):         #{skipped_multi}"
    puts "  Skipped (no match):             #{skipped_no_match}"
    puts "  Links #{dry_run ? 'to apply' : 'applied'}:          #{linked}"
    puts "  Already linked:                 #{already_linked}"
    puts "  Errors:                         #{errors}"
    puts dry_run ? "\nRun with DRY_RUN=false to apply changes." : "\nDone!"
  end

  desc "Link supplementary lawyers for specific multi-person edge cases (manual input)"
  task link_edge_cases: :environment do
    # Usage: rake lawyers:link_edge_cases EDGES='anchor1:member1,member2;anchor2:member3,member4'
    # Example: rake lawyers:link_edge_cases EDGES='PE_35607:AC_6640,CE_53302;DF_31537:GO_36503'
    edges_input = ENV['EDGES']
    dry_run = ENV.fetch('DRY_RUN', 'true') == 'true'

    unless edges_input
      puts "Usage: rake lawyers:link_edge_cases EDGES='anchor_oab:member1,member2;anchor_oab2:member3'"
      puts "  DRY_RUN=false to apply"
      exit 1
    end

    puts dry_run ? "=== DRY RUN ===" : "=== APPLYING ==="

    linked = 0
    errors = 0

    edges_input.split(';').each do |group_str|
      anchor_oab, members_str = group_str.strip.split(':')
      next unless anchor_oab && members_str

      principal = Lawyer.find_by(oab_id: anchor_oab.strip)
      unless principal
        puts "  ERROR: Principal #{anchor_oab} not found"
        errors += 1
        next
      end

      members_str.split(',').each do |member_oab|
        member_oab = member_oab.strip
        lawyer = Lawyer.find_by(oab_id: member_oab)
        unless lawyer
          puts "  ERROR: Member #{member_oab} not found"
          errors += 1
          next
        end

        if dry_run
          puts "  [DRY] #{member_oab} -> principal #{anchor_oab} (id: #{principal.id})"
        else
          lawyer.update_columns(principal_lawyer_id: principal.id, suplementary: true)
          puts "  OK: #{member_oab} -> #{anchor_oab}"
        end
        linked += 1
      end
    end

    puts "\n  Links #{dry_run ? 'to apply' : 'applied'}: #{linked} | Errors: #{errors}"
    puts dry_run ? "Run with DRY_RUN=false to apply." : "Done!"
  end
end
