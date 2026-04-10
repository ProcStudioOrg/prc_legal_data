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
end
