# lib/tasks/link_supplementary_from_json.rake
require 'json'

namespace :lawyers do
  desc "Link supplementary lawyer records from JSON file to their principal record"
  task link_from_json: :environment do
    json_file_path = Rails.root.join('lib', 'tasks', 'l_suplementary_correct.json')

    unless File.exist?(json_file_path)
      puts "ERROR: JSON file not found at #{json_file_path}"
      return
    end

    puts "Reading JSON file: #{json_file_path}"
    begin
      json_data = JSON.parse(File.read(json_file_path))
    rescue JSON::ParserError => e
      puts "ERROR: Failed to parse JSON file: #{e.message}"
      return
    end

    records_to_process = json_data.length
    processed_count = 0
    linked_count = 0
    principal_not_found_count = 0
    supplementary_not_found_count = 0

    json_data.each_with_index do |supp_data, index|
      processed_count += 1
      puts "\nProcessing JSON record ##{index + 1}/#{records_to_process}..."

      supplementary_id = supp_data['id']
      supplementary_name = supp_data['full_name']
      supplementary_oab = supp_data['oab_id']

      unless supplementary_id && supplementary_name
        puts "WARNING: Skipping JSON record ##{index + 1} due to missing 'id' or 'full_name'."
        next
      end

      puts "Searching for Supplementary Lawyer in DB with ID: #{supplementary_id} (#{supplementary_oab})"
      supplementary_record = Lawyer.find_by(id: supplementary_id)

      unless supplementary_record
        puts "WARNING: Supplementary Lawyer with ID #{supplementary_id} from JSON not found in the database. Skipping."
        supplementary_not_found_count += 1
        next
      end

      # Double-check if it's marked as supplementary in JSON, though the file name implies it
      unless supp_data['profession']&.match?(/\ASUPLEMENTAR\z/i)
         puts "WARNING: Record ID #{supplementary_id} in JSON is not marked as 'SUPLEMENTAR' in its 'profession' field. Skipping."
         next
      end

      # Check if already linked
      if supplementary_record.principal_lawyer_id.present?
        puts "INFO: Supplementary Lawyer ID #{supplementary_id} is already linked to Principal ID #{supplementary_record.principal_lawyer_id}. Skipping update."
        next
      end

      puts "Searching for Principal Lawyer in DB with Full Name: '#{supplementary_name}'"
      # Find principal based on name, ensuring it's not a supplementary record itself
      principal_record = Lawyer.where(full_name: supplementary_name)
                               .where("profession ILIKE 'ADVOGADO' OR profession ILIKE 'ADVOGADA'")
                               .first
      # Note: Using ILIKE for case-insensitivity if needed (PostgreSQL). Adjust for your DB.
      # If not using PostgreSQL, might need: .where("lower(profession) = 'advogado' OR lower(profession) = 'advogada'")

      if principal_record
        puts "Found Principal Lawyer ID: #{principal_record.id} (#{principal_record.oab_id})"
        begin
          supplementary_record.update_columns(principal_lawyer_id: principal_record.id, suplementary: true)
          puts "SUCCESS: Linked Supplementary ID #{supplementary_id} to Principal ID #{principal_record.id}."
          linked_count += 1
        rescue => e
          puts "ERROR: Failed to update Supplementary Lawyer ID #{supplementary_id}: #{e.message}"
        end
      else
        puts "WARNING: Principal Lawyer with name '#{supplementary_name}' not found in the database for Supplementary ID #{supplementary_id}. Cannot link."
        principal_not_found_count += 1
      end
    end

    puts "\n--- Processing Summary ---"
    puts "Total JSON records processed: #{processed_count}"
    puts "Successfully linked: #{linked_count}"
    puts "Supplementary records not found in DB: #{supplementary_not_found_count}"
    puts "Principal records not found in DB: #{principal_not_found_count}"
    puts "-------------------------"
  end
end
