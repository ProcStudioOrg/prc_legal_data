# Create this file: lib/tasks/society.rake
namespace :society do
  desc "Process society data for lawyers with societies (with updates)"
  task process: :environment do
    puts "🚀 Processing society data from multiple files with updates..."
    
    # Load all JSON files from data_input directory
    data_input_path = Rails.root.join('data_input')
    
    unless Dir.exist?(data_input_path)
      puts "❌ Directory not found: #{data_input_path}"
      exit
    end
    
    json_files = Dir.glob(File.join(data_input_path, '*.json'))
    
    if json_files.empty?
      puts "❌ No JSON files found in #{data_input_path}"
      exit
    end
    
    puts "📁 Found #{json_files.length} JSON files to process"
    
    # Create a single log file for all processing
    log_file_path = Rails.root.join('society_processing.log')
    log_file = File.open(log_file_path, 'w')
    log_file.write("Society Processing Log - #{Time.current}\n")
    log_file.write("="*60 + "\n")
    
    total_processed = 0
    total_skipped = 0
    total_errors = 0
    total_records = 0
    total_updated = 0
    
    json_files.each_with_index do |file_path, file_index|
      puts "\n" + "="*60
      puts "📄 Processing file #{file_index + 1}/#{json_files.length}: #{File.basename(file_path)}"
      puts "="*60
      
      log_file.write("\nProcessing file: #{File.basename(file_path)}\n")
      log_file.write("-" * 40 + "\n")
      
      begin
        json_data = JSON.parse(File.read(file_path))
        puts "📁 Loaded #{json_data.length} records from #{File.basename(file_path)}"
        total_records += json_data.length
        
        log_file.write("Loaded #{json_data.length} records from #{File.basename(file_path)}\n")
      rescue JSON::ParserError => e
        puts "❌ Error parsing JSON in #{File.basename(file_path)}: #{e.message}"
        log_file.write("ERROR: Failed to parse #{File.basename(file_path)}: #{e.message}\n")
        next
      end
      
      file_processed = 0
      file_skipped = 0
      file_errors = 0
      file_updated = 0
      
      # Process each JSON object
      json_data.each_with_index do |lawyer_data, index|
        json_id = lawyer_data["id"]
        json_name = lawyer_data["full_name"]
        has_society = lawyer_data["has_society"]
        
        # Find lawyer in database
        lawyer = Lawyer.find_by(id: json_id)
        
        unless lawyer
          puts "#{index + 1}. ❌ ID #{json_id} - #{json_name} - NOT FOUND in database"
          log_file.write("ERROR: Lawyer ID #{json_id} not found in database\n")
          file_errors += 1
          next
        end
        
        # Skip if no society
        unless has_society && lawyer_data["society_complete_details"]&.any?
          puts "#{index + 1}. ⏭️  ID #{json_id} - #{json_name} - No society data"
          file_skipped += 1
          next
        end
        
        # Check if lawyer already has societies
        existing_societies = lawyer.societies.count
        puts "  📊 Lawyer currently has #{existing_societies} societies"
        
        begin
          # Process the society
          puts "  🔧 Starting society processing for #{json_name}..."
          
          result = create_or_update_society_for_lawyer(lawyer, lawyer_data, log_file)
          
          if result[:success]
            if result[:updated]
              puts "#{index + 1}. 🔄 ID #{json_id} - #{lawyer.full_name} - Society updated!"
              file_updated += 1
            else
              puts "#{index + 1}. ✅ ID #{json_id} - #{lawyer.full_name} - Society processed!"
              file_processed += 1
            end
          else
            puts "#{index + 1}. ❌ ID #{json_id} - #{lawyer.full_name} - #{result[:error]}"
            file_errors += 1
          end
          
        rescue => e
          puts "#{index + 1}. 💥 ID #{json_id} - #{json_name} - Error: #{e.message}"
          puts "  📍 Backtrace: #{e.backtrace.first(3).join(' | ')}"
          log_file.write("EXCEPTION: Processing lawyer ID #{json_id}: #{e.message}\n")
          log_file.write("BACKTRACE: #{e.backtrace.first(5).join(' | ')}\n")
          file_errors += 1
        end
      end
      
      puts "\n📊 File Summary for #{File.basename(file_path)}:"
      puts "✅ Created: #{file_processed}"
      puts "🔄 Updated: #{file_updated}"
      puts "⏭️  Skipped: #{file_skipped}"
      puts "❌ Errors: #{file_errors}"
      
      log_file.write("\nFile Summary for #{File.basename(file_path)}:\n")
      log_file.write("Created: #{file_processed}, Updated: #{file_updated}, Skipped: #{file_skipped}, Errors: #{file_errors}\n")
      
      total_processed += file_processed
      total_updated += file_updated
      total_skipped += file_skipped
      total_errors += file_errors
    end
    
    puts "\n" + "="*60
    puts "📊 TOTAL SUMMARY:"
    puts "📁 Files processed: #{json_files.length}"
    puts "📋 Total records: #{total_records}"
    puts "✅ Total created: #{total_processed}"
    puts "🔄 Total updated: #{total_updated}"
    puts "⏭️  Total skipped: #{total_skipped}"
    puts "❌ Total errors: #{total_errors}"
    puts "📄 Log file created: #{log_file_path}"
    puts "✨ Process complete!"
    
    log_file.write("\n" + "="*60 + "\n")
    log_file.write("FINAL SUMMARY:\n")
    log_file.write("Files processed: #{json_files.length}\n")
    log_file.write("Total records: #{total_records}\n")
    log_file.write("Total created: #{total_processed}\n")
    log_file.write("Total updated: #{total_updated}\n")
    log_file.write("Total skipped: #{total_skipped}\n")
    log_file.write("Total errors: #{total_errors}\n")
    log_file.write("Process completed at: #{Time.current}\n")
    
    log_file.close
  end

  private

  def create_or_update_society_for_lawyer(lawyer, lawyer_data, log_file)
    puts "    🔍 Getting society details..."
    puts "    👤 Lawyer: #{lawyer.full_name} (ID: #{lawyer.id})"
    
    # Get society details from JSON
    society_details = lawyer_data["society_complete_details"].first
    modal_data = society_details.dig("modal_data", "modal_data")
    basic_info = lawyer_data["society_basic_details"].first
    
    unless modal_data
      error_msg = "No modal_data found for lawyer ID #{lawyer.id}"
      log_file.write("ERROR: #{error_msg}\n")
      return { success: false, error: error_msg }
    end
    
    puts "    🏢 Society name: #{modal_data['firm_name']}"
    
    # Use IdtSoci as inscricao (number) and Insc for OAB_ID (string)
    inscricao_number = basic_info["IdtSoci"]
    oab_id_string = basic_info["Insc"]
    
    puts "    📝 Inscricao (IdtSoci): #{inscricao_number}"
    puts "    📝 OAB_ID (Insc): #{oab_id_string}"
    
    log_file.write("INFO: Processing society '#{modal_data['firm_name']}' with inscricao '#{inscricao_number}' and oab_id '#{oab_id_string}' for lawyer #{lawyer.full_name} (ID: #{lawyer.id})\n")
    
    # Check if this combination of inscricao AND oab_id already exists
    existing_society = Society.find_by(inscricao: inscricao_number, oab_id: oab_id_string)
    society_updated = false
    
    if existing_society
      puts "    🔄 Society with this inscricao+oab_id combination already exists: #{existing_society.name} (ID: #{existing_society.id})"
      puts "    🔧 Updating existing society..."
      
      state = extract_state(modal_data["estado"])
      
      # Try to get URL from different possible locations
      society_url = modal_data["url"] || 
                   modal_data["Url"] || 
                   society_details.dig("basic_info", "source_url") ||
                   basic_info["Url"]
      
      puts "    🔗 Society URL: #{society_url}"
      
      # Update society attributes (including city: nil)
      update_attributes = {
        name: modal_data["firm_name"],
        state: state,
        situacao: modal_data["situacao"],
        address: modal_data["endereco"] == "Não informado" ? nil : modal_data["endereco"],
        oab_id: oab_id_string,
        number_of_partners: modal_data["socios"]&.length || 1,
        city: nil,  # Always set city to nil as per original logic
        society_link: society_url
      }
      
      puts "    🔍 Checking for changes in society data..."
      
      # Check if any attributes changed
      changes_detected = false
      update_attributes.each do |attr, new_value|
        current_value = existing_society.send(attr)
        puts "    🔍 #{attr}: current='#{current_value}' -> new='#{new_value}'"
        
        if current_value != new_value
          changes_detected = true
          puts "    📝 CHANGE DETECTED - #{attr}: '#{current_value}' -> '#{new_value}'"
          log_file.write("CHANGE: #{attr} from '#{current_value}' to '#{new_value}'\n")
        else
          puts "    ✅ #{attr}: no change"
        end
      end
      
      if changes_detected
        begin
          puts "    🔄 Applying updates to society..."
          existing_society.update!(update_attributes)
          puts "    ✅ Society updated successfully!"
          puts "    📋 Final values after update:"
          update_attributes.each do |attr, value|
            puts "      #{attr}: '#{existing_society.reload.send(attr)}'"
          end
          log_file.write("SUCCESS: Updated society ID #{existing_society.id} - '#{existing_society.name}'\n")
          society_updated = true
        rescue ActiveRecord::RecordInvalid => e
          error_msg = "Society update failed for ID #{existing_society.id}: #{e.message}"
          puts "    💥 #{error_msg}"
          puts "    🔍 Validation errors: #{e.record.errors.full_messages}"
          log_file.write("ERROR: #{error_msg}\n")
          log_file.write("VALIDATION_ERRORS: #{e.record.errors.full_messages.join(', ')}\n")
          return { success: false, error: error_msg }
        end
      else
        puts "    ✅ No changes detected in society data - skipping update"
        log_file.write("INFO: No changes needed for society ID #{existing_society.id}\n")
      end
      
      society = existing_society
    else
      puts "    ✅ No existing society found with this inscricao+oab_id combination"
      puts "    🏗️  Creating new society..."
      
      state = extract_state(modal_data["estado"])
      
      # Debug: Check all possible URL locations
      puts "    🔍 Checking URL locations:"
      puts "      modal_data['url']: #{modal_data["url"]}"
      puts "      modal_data['Url']: #{modal_data["Url"]}"
      puts "      basic_info source_url: #{society_details.dig("basic_info", "source_url")}"
      puts "      basic_info Url: #{basic_info["Url"]}"
      
      # Try to get URL from different possible locations  
      society_url = modal_data["url"] || 
                   modal_data["Url"] || 
                   society_details.dig("basic_info", "source_url") ||
                   basic_info["Url"]
      
      puts "    🔗 Final Society URL: #{society_url}"
      
      begin
        society = Society.create!(
          inscricao: inscricao_number,
          name: modal_data["firm_name"],
          state: state,
          situacao: modal_data["situacao"],
          address: modal_data["endereco"] == "Não informado" ? nil : modal_data["endereco"],
          oab_id: oab_id_string,
          number_of_partners: modal_data["socios"]&.length || 1,
          city: nil,
          society_link: society_url
        )
        puts "    ✅ Society created with ID: #{society.id}"
        log_file.write("SUCCESS: Created society ID #{society.id} - '#{society.name}'\n")
        
      rescue ActiveRecord::RecordInvalid => e
        error_msg = "Society creation failed for lawyer #{lawyer.id}: #{e.message}"
        puts "    💥 #{error_msg}"
        log_file.write("ERROR: #{error_msg}\n")
        return { success: false, error: error_msg }
      end
    end
    
    puts "    👥 Looking for lawyer in society members..."
    
    # Find lawyer info in society members
    lawyer_info = modal_data["socios"].find do |socio|
      normalize_name(socio["nome"]) == normalize_name(lawyer.full_name)
    end
    
    unless lawyer_info
      error_msg = "Lawyer '#{lawyer.full_name}' (ID: #{lawyer.id}) not found in society members list"
      puts "    ⚠️  #{error_msg}"
      log_file.write("ERROR: #{error_msg}\n")
      return { success: false, error: error_msg }
    end
    
    puts "    👤 Found lawyer as: #{lawyer_info['tipo']}"
    
    # Check for existing relationship
    puts "    🔗 Checking for existing relationship..."
    existing_relationship = LawyerSociety.find_by(lawyer_id: lawyer.id, society_id: society.id)
    relationship_updated = false
    
    # Map partnership type
    partnership_type = case lawyer_info["tipo"]
                      when 'Sócio' then 'Sócio'
                      when 'Associado' then 'Associado'
                      when 'Sócio de Serviço' then 'Sócio de Serviço'
                      else 'Associado'
                      end
    
    if existing_relationship
      puts "    🔄 Relationship already exists with type: #{existing_relationship.partnership_type}"
      puts "    🔧 Updating existing relationship..."
      
      # Update relationship attributes
      update_attributes = {
        partnership_type: partnership_type,
        cna_link: lawyer_info["cna_link"]
      }
      
      puts "    🔍 Checking for changes in relationship data..."
      
      # Check if any attributes changed
      changes_detected = false
      update_attributes.each do |attr, new_value|
        current_value = existing_relationship.send(attr)
        puts "    🔍 #{attr}: current='#{current_value}' -> new='#{new_value}'"
        
        if current_value != new_value
          changes_detected = true
          puts "    📝 CHANGE DETECTED - #{attr}: '#{current_value}' -> '#{new_value}'"
          log_file.write("CHANGE: #{attr} from '#{current_value}' to '#{new_value}'\n")
        else
          puts "    ✅ #{attr}: no change"
        end
      end
      
      if changes_detected
        begin
          puts "    🔄 Applying updates to relationship..."
          existing_relationship.update!(update_attributes)
          puts "    ✅ Relationship updated successfully!"
          puts "    📋 Final values after update:"
          update_attributes.each do |attr, value|
            puts "      #{attr}: '#{existing_relationship.reload.send(attr)}'"
          end
          log_file.write("SUCCESS: Updated relationship ID #{existing_relationship.id}\n")
          relationship_updated = true
        rescue ActiveRecord::RecordInvalid => e
          error_msg = "Relationship update failed for ID #{existing_relationship.id}: #{e.message}"
          puts "    💥 #{error_msg}"
          puts "    🔍 Validation errors: #{e.record.errors.full_messages}"
          log_file.write("ERROR: #{error_msg}\n")
          log_file.write("VALIDATION_ERRORS: #{e.record.errors.full_messages.join(', ')}\n")
          return { success: false, error: error_msg }
        end
      else
        puts "    ✅ No changes detected in relationship data - skipping update"
        log_file.write("INFO: No changes needed for relationship ID #{existing_relationship.id}\n")
      end
      
    else
      puts "    🤝 Creating new relationship..."
      
      begin
        relationship = LawyerSociety.create!(
          lawyer_id: lawyer.id,
          society_id: society.id,
          partnership_type: partnership_type,
          cna_link: lawyer_info["cna_link"]
        )
        puts "    ✅ Relationship created with ID: #{relationship.id}!"
        log_file.write("SUCCESS: Created relationship ID #{relationship.id}\n")
        
      rescue ActiveRecord::RecordInvalid => e
        error_msg = "Relationship creation failed for lawyer #{lawyer.id} and society #{society.id}: #{e.message}"
        puts "    💥 #{error_msg}"
        log_file.write("ERROR: #{error_msg}\n")
        return { success: false, error: error_msg }
      end
    end
    
    # Return success with update flag
    updated = society_updated || relationship_updated
    { success: true, updated: updated }
    
  rescue => e
    error_msg = "Unexpected error in create_or_update_society_for_lawyer for lawyer #{lawyer&.id}: #{e.message}"
    puts "    💥 #{error_msg}"
    log_file.write("EXCEPTION: #{error_msg}\n")
    { success: false, error: error_msg }
  end
  
  def extract_state(estado_string)
    estado_string&.split(' - ')&.last&.strip || 'MS'
  end
  
  def normalize_name(name)
    name&.strip&.upcase&.gsub(/\s+/, ' ')
  end
end
