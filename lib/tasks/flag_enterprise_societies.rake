namespace :data do
  desc "Flag lawyers in societies with >6 members as enterprise_society in crm_data"
  task flag_enterprise_societies: :environment do
    threshold = ScraperLawyerSerializer::ENTERPRISE_THRESHOLD

    puts "Finding societies with more than #{threshold} members..."

    large_societies = Society
      .joins(:lawyer_societies)
      .group("societies.id")
      .having("COUNT(lawyer_societies.id) > ?", threshold)

    total_societies = large_societies.count.length
    puts "Found #{total_societies} large societies"

    flagged_count = 0

    large_societies.find_each do |society|
      lawyer_ids = society.lawyer_societies.pluck(:lawyer_id)

      Lawyer.where(id: lawyer_ids).find_each do |lawyer|
        crm = lawyer.crm_data || {}
        next if crm["enterprise_society"] == true

        crm["enterprise_society"] = true
        lawyer.update_column(:crm_data, crm)
        flagged_count += 1
      end

      print "."
    end

    puts "\nDone! Flagged #{flagged_count} lawyers across #{total_societies} societies"
  end
end
