namespace :lawyers do
  desc "Find all duplicate names and show summary"
  task find_duplicates: :environment do
    min_count = ENV.fetch('MIN', '2').to_i
    limit = ENV.fetch('LIMIT', '50').to_i

    puts "Finding duplicate names (min #{min_count} occurrences)..."
    puts ""

    groups = Lawyer
      .where.not(full_name: [nil, ''])
      .group(:full_name)
      .having("COUNT(*) >= ?", min_count)
      .order(Arel.sql("COUNT(*) DESC"))
      .limit(limit)
      .pluck(:full_name, Arel.sql("COUNT(*)"))

    puts "%-50s | %s" % ["FULL NAME", "COUNT"]
    puts "-" * 60

    groups.each do |name, count|
      puts "%-50s | %d" % [name, count]
    end

    total_groups = Lawyer
      .where.not(full_name: [nil, ''])
      .group(:full_name)
      .having("COUNT(*) >= ?", min_count)
      .count.length

    puts ""
    puts "Showing #{groups.length} of #{total_groups} total groups"
    puts "Use LIMIT=100 MIN=3 to adjust"
  end

  desc "Show details for a specific duplicate name group"
  task duplicate_details: :environment do
    name = ENV['NAME']
    unless name
      puts "Usage: rake lawyers:duplicate_details NAME='ANA PAULA DA SILVA'"
      exit 1
    end

    bucket = Rails.application.config.s3[:profile_pictures_bucket]
    lawyers = Lawyer.where(full_name: name).order(:state, :oab_id)

    if lawyers.empty?
      puts "No lawyers found with name: #{name}"
      exit 1
    end

    puts "Found #{lawyers.count} lawyers with name: #{name}"
    puts "=" * 80

    lawyers.each_with_index do |l, i|
      profile_url = l.profile_picture.present? ? "https://#{bucket}.s3.amazonaws.com/#{l.profile_picture}" : "N/A"
      cna_url = l.cna_picture.present? ? "https://#{bucket}.s3.amazonaws.com/#{l.cna_picture}" : "N/A"

      puts ""
      puts "--- ##{i + 1} ---"
      puts "  ID:          #{l.id}"
      puts "  OAB:         #{l.oab_id}"
      puts "  State:       #{l.state}"
      puts "  City:        #{l.city}"
      puts "  Profession:  #{l.profession}"
      puts "  Situation:   #{l.situation}"
      puts "  Suplementary: #{l.suplementary}"
      puts "  Principal ID: #{l.principal_lawyer_id || 'N/A'}"
      puts "  Profile Pic: #{profile_url}"
      puts "  CNA Pic:     #{cna_url}"
    end
  end

  desc "Export all duplicate name groups to JSON for processing"
  task export_duplicates: :environment do
    min_count = ENV.fetch('MIN', '2').to_i
    output_file = ENV.fetch('OUTPUT', Rails.root.join('tmp', 'duplicate_names.json').to_s)
    bucket = Rails.application.config.s3[:profile_pictures_bucket]

    puts "Querying duplicate name groups (min #{min_count})..."

    duplicate_names = Lawyer
      .where.not(full_name: [nil, ''])
      .group(:full_name)
      .having("COUNT(*) >= ?", min_count)
      .order(Arel.sql("COUNT(*) DESC"))
      .pluck(:full_name)

    puts "Found #{duplicate_names.length} groups. Loading lawyer details..."

    results = []
    total = duplicate_names.length

    duplicate_names.each_with_index do |name, idx|
      print "\rProcessing #{idx + 1}/#{total}..." if (idx + 1) % 500 == 0 || idx == 0

      lawyers = Lawyer.where(full_name: name).order(:state, :oab_id).select(
        :id, :full_name, :oab_id, :state, :city, :profession, :situation,
        :suplementary, :principal_lawyer_id, :profile_picture, :cna_picture
      )

      group = {
        full_name: name,
        count: lawyers.length,
        lawyers: lawyers.map do |l|
          {
            id: l.id,
            oab_id: l.oab_id,
            state: l.state,
            city: l.city,
            profession: l.profession,
            situation: l.situation,
            suplementary: l.suplementary,
            principal_lawyer_id: l.principal_lawyer_id,
            profile_picture_url: l.profile_picture.present? ? "https://#{bucket}.s3.amazonaws.com/#{l.profile_picture}" : nil,
            cna_picture_url: l.cna_picture.present? ? "https://#{bucket}.s3.amazonaws.com/#{l.cna_picture}" : nil
          }
        end
      }

      results << group
    end

    puts "\rWriting #{results.length} groups to #{output_file}..."
    File.write(output_file, JSON.pretty_generate(results))
    puts "Done! File: #{output_file}"
  end

  desc "Export duplicate groups with image URLs for face comparison"
  task export_for_comparison: :environment do
    min_count = ENV.fetch('MIN', '2').to_i
    max_count = ENV.fetch('MAX', '50').to_i
    output_file = ENV.fetch('OUTPUT', Rails.root.join('tmp', 'duplicates_for_comparison.json').to_s)
    bucket = Rails.application.config.s3[:profile_pictures_bucket]

    puts "Querying duplicate groups (#{min_count}-#{max_count} occurrences)..."

    # Focus on groups where NOT all are already linked as supplementary
    duplicate_names = Lawyer
      .where.not(full_name: [nil, ''])
      .group(:full_name)
      .having("COUNT(*) >= ? AND COUNT(*) <= ?", min_count, max_count)
      .order(Arel.sql("COUNT(*) DESC"))
      .pluck(:full_name)

    puts "Found #{duplicate_names.length} groups. Filtering unlinked..."

    results = []
    skipped = 0

    duplicate_names.each_with_index do |name, idx|
      print "\rProcessing #{idx + 1}/#{duplicate_names.length}..." if (idx + 1) % 500 == 0 || idx == 0

      lawyers = Lawyer.where(full_name: name).order(:state, :oab_id)

      # Skip if all are already linked (have principal_lawyer_id)
      unlinked = lawyers.where(principal_lawyer_id: nil)
      if unlinked.count <= 1
        skipped += 1
        next
      end

      # Only include lawyers that have at least one image
      with_images = lawyers.select { |l| l.profile_picture.present? || l.cna_picture.present? }
      next if with_images.length < 2

      group = {
        full_name: name,
        count: lawyers.length,
        unlinked_count: unlinked.count,
        lawyers: lawyers.map do |l|
          {
            id: l.id,
            oab_id: l.oab_id,
            state: l.state,
            city: l.city,
            profession: l.profession,
            situation: l.situation,
            suplementary: l.suplementary,
            principal_lawyer_id: l.principal_lawyer_id,
            profile_picture_url: l.profile_picture.present? ? "https://#{bucket}.s3.amazonaws.com/#{l.profile_picture}" : nil,
            cna_picture_url: l.cna_picture.present? ? "https://#{bucket}.s3.amazonaws.com/#{l.cna_picture}" : nil
          }
        end
      }

      results << group
    end

    puts "\rSkipped #{skipped} already-linked groups"
    puts "Writing #{results.length} groups to #{output_file}..."
    File.write(output_file, JSON.pretty_generate(results))
    puts "Done! File: #{output_file}"
    puts ""
    puts "Next step: run face comparison with:"
    puts "  python3 scripts/compare_faces.py #{output_file}"
  end

  desc "Find duplicate-name clusters with actionable supplementaries (unlinked or misanchored)"
  task find_unlinked_clusters: :environment do
    output_file = ENV.fetch('OUTPUT', Rails.root.join('tmp', 'unlinked_clusters.json').to_s)
    only_safe   = ENV['ONLY_SAFE'] == 'true'
    bucket      = Rails.application.config.s3[:profile_pictures_bucket]

    total = Lawyer.count
    puts "Building normalized name index of #{total} lawyer records..."

    name_index = Hash.new { |h, k| h[k] = [] }
    processed = 0
    Lawyer.find_each(batch_size: 5000) do |l|
      processed += 1
      print "\r  #{processed}/#{total}" if processed % 50_000 == 0
      next if l.full_name.to_s.strip.empty?
      name_index[Lawyers::ClusterClassifier.normalize(l.full_name)] << l
    end
    puts "\n  index size: #{name_index.size}"

    puts "Classifying clusters..."
    counts  = Hash.new(0)
    results = []

    name_index.each do |norm_name, members|
      next if members.size < 2
      result = Lawyers::ClusterClassifier.classify(members)
      counts[result[:type]] += 1

      proposed = Lawyers::ClusterClassifier.proposed_links(result)

      # Skip clusters where there's nothing to do (NO_ACTION, ambiguous/orphan with no proposals).
      # When ONLY_SAFE: keep only types in SAFE_TYPES with non-empty proposals.
      next if proposed.empty? && !ambiguous_for_review?(result[:type])
      next if only_safe && !Lawyers::ClusterClassifier::SAFE_TYPES.include?(result[:type])

      img_url = ->(path) { path.present? ? "https://#{bucket}.s3.amazonaws.com/#{path}" : nil }

      results << {
        normalized_name: norm_name,
        type:            result[:type],
        reason:          result[:reason],
        principal: result[:principal] && {
          oab_id:              result[:principal].oab_id,
          id:                  result[:principal].id,
          full_name:           result[:principal].full_name,
          state:               result[:principal].state,
          profile_picture_url: img_url.call(result[:principal].profile_picture)
        },
        principal_id_inferred: result[:principal_id],
        all_principals: (result[:all_principals] || []).map do |p|
          { oab_id: p.oab_id, id: p.id, full_name: p.full_name, state: p.state }
        end,
        unlinked_supps: result[:unlinked_supps].map do |l|
          {
            oab_id:              l.oab_id, id: l.id, full_name: l.full_name, state: l.state,
            profile_picture_url: img_url.call(l.profile_picture),
            cna_picture_url:     img_url.call(l.cna_picture)
          }
        end,
        linked_supps: (result[:linked_supps] || []).map do |l|
          { oab_id: l.oab_id, id: l.id, principal_lawyer_id: l.principal_lawyer_id }
        end,
        misanchored_supps: (result[:misanchored_supps] || []).map do |l|
          { oab_id: l.oab_id, id: l.id, principal_lawyer_id: l.principal_lawyer_id }
        end,
        bad_anchor_ids:       result[:bad_anchor_ids],
        linked_principal_ids: result[:linked_principal_ids],
        proposed_updates:     proposed
      }
    end

    puts "\n=== Counts by type ==="
    counts.each { |k, v| puts "  #{k}: #{v}" }
    puts "\nWriting #{results.size} clusters to #{output_file}..."
    File.write(output_file, JSON.pretty_generate(results))
    puts "Done."
    puts ""
    puts "Next steps:"
    puts "  - Review #{output_file}"
    puts "  - Apply SAFE clusters:  rake lawyers:apply_name_links INPUT=#{output_file} DRY_RUN=true"
    puts "  - AMBIGUOUS clusters need face comparison to disambiguate"
  end

  desc "Apply principal links from find_unlinked_clusters output (SAFE clusters only)"
  task apply_name_links: :environment do
    input_file = ENV.fetch('INPUT', Rails.root.join('tmp', 'unlinked_clusters.json').to_s)
    dry_run    = ENV.fetch('DRY_RUN', 'true') == 'true'
    verbose    = ENV['VERBOSE'] == 'true'

    unless File.exist?(input_file)
      puts "ERROR: #{input_file} not found. Run lawyers:find_unlinked_clusters first."
      exit 1
    end

    puts dry_run ? "=== DRY RUN (set DRY_RUN=false to apply) ===" : "=== APPLYING CHANGES ==="
    puts "Reading #{input_file}..."

    data = JSON.parse(File.read(input_file))

    safe_types = Lawyers::ClusterClassifier::SAFE_TYPES.map(&:to_s)
    safe_clusters = data.select { |c| safe_types.include?(c['type']) && c['proposed_updates'].present? }

    puts "Safe clusters: #{safe_clusters.size} / #{data.size}"

    totals = { planned: 0, linked: 0, reanchored: 0, skipped: 0, errors: 0, clusters: 0 }

    safe_clusters.each do |cluster|
      puts "\n--- #{cluster['normalized_name']} (#{cluster['type']}, #{cluster['proposed_updates'].size} updates) ---" if verbose
      r = Lawyers::Linker.apply(cluster['proposed_updates'], dry_run: dry_run) do |msg|
        puts msg if verbose
      end
      totals[:planned]    += r.planned
      totals[:linked]     += r.linked
      totals[:reanchored] += r.reanchored
      totals[:skipped]    += r.skipped
      totals[:errors]     += r.errors
      totals[:clusters]   += 1
    end

    puts "\n=== Summary ==="
    puts "  Clusters touched:         #{totals[:clusters]}"
    puts "  Updates #{dry_run ? 'planned' : 'applied'}:         #{totals[:linked] + totals[:reanchored]}"
    puts "    new links:              #{totals[:linked]}"
    puts "    re-anchors:             #{totals[:reanchored]}"
    puts "  Already-correct (skipped): #{totals[:skipped]}"
    puts "  Errors:                   #{totals[:errors]}"
    puts dry_run ? "\nRun with DRY_RUN=false to apply." : "\nDone!"
  end

  # Whether to keep an ambiguous/orphan cluster in the output even with no proposed updates,
  # so reviewers can see it. Currently we keep them out — they're recoverable by re-running.
  def ambiguous_for_review?(_type)
    false
  end
end
