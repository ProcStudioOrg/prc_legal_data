namespace :lawyers do
  desc "Import lawyers from JSON files in local temp folder"
  task import_local: :environment do
    require 'json'
    require 'fileutils'
    
    # Address parser method
    def parse_lawyer_address(address_str)
      return { address: "Não informado", city: nil, state: nil, zip_code: nil } if address_str.strip == "Não informado" || address_str.strip.start_with?("Não informado")
      
      lines = address_str.strip.split("\n").map(&:strip)
      result = {}
      
      # First line contains the main address (street and number)
      result[:address] = lines[0] if lines[0]
      
      # Second line contains city and state
      if lines[1] && lines[1].include?("-")
        city_state = lines[1].split("-", 2).map(&:strip)
        result[:city] = city_state[0]
        result[:state] = city_state[1]
      end
      
      # Third line is the zip code
      result[:zip_code] = lines[2] if lines[2]
      
      result
    end
    
    # Define the directory where the JSON files are stored
    import_dir = Rails.root.join('tmp')
    
    # Ensure the directory exists
    FileUtils.mkdir_p(import_dir)
    
    # Create or load processing record file
    processing_record_path = File.join(import_dir, 'processing_record.json')
    processing_record = {}
    
    if File.exist?(processing_record_path)
      processing_record = JSON.parse(File.read(processing_record_path))
    end
    
    # Create or load duplicate records file
    duplicate_records_path = File.join(import_dir, 'duplicate_records.json')
    duplicate_records = {}
    
    if File.exist?(duplicate_records_path)
      duplicate_records = JSON.parse(File.read(duplicate_records_path))
    end
    
    # Get all JSON files in the directory
    json_files = Dir.glob(File.join(import_dir, '*.json'))
    
    # Skip processing record and duplicate records files
    json_files.reject! { |f| ['processing_record.json', 'duplicate_records.json'].include?(File.basename(f)) }
    
    puts "Found #{json_files.size} JSON files to process"
    
    # Process each JSON file
    json_files.each do |file_path|
      file_name = File.basename(file_path)
      
      # Skip if already processed
      if processing_record[file_name] && processing_record[file_name]["processed"] == true
        puts "Skipping #{file_name} (already processed)"
        next
      end
      
      puts "Processing #{file_name}..."
      
      begin
        # Read the JSON file
        json_data = JSON.parse(File.read(file_path))
        
        # Track file stats
        file_stats = {
          total: json_data.size,
          created: 0,
          updated: 0,
          errors: 0,
          duplicates: 0
        }
        
        # Use ActiveRecord import for better performance
        lawyers_to_import = []
        
        # First, check for duplicates within the file
        oab_ids_in_file = json_data.map { |record| record["oab_id"] }
        duplicate_oab_ids_in_file = oab_ids_in_file.select { |e| oab_ids_in_file.count(e) > 1 }.uniq
        
        if duplicate_oab_ids_in_file.any?
          puts "Found #{duplicate_oab_ids_in_file.size} duplicate oab_ids within the file"
          duplicate_oab_ids_in_file.each do |dup_id|
            puts "  Duplicate oab_id in file: #{dup_id}"
          end
        end
        
        # Check which oab_ids already exist in the database
        existing_oab_ids = Lawyer.where(oab_id: oab_ids_in_file).pluck(:oab_id)
        
        if existing_oab_ids.any?
          puts "Found #{existing_oab_ids.size} oab_ids that already exist in the database"
        end
        
        # Prepare records for batch import or individual processing
        json_data.each_with_index do |record, index|
          begin
            lawyer_data = record["data"]
            oab_id = record["oab_id"]
            
            # Skip if this is a duplicate within the file (except the first occurrence)
            if duplicate_oab_ids_in_file.include?(oab_id) && oab_ids_in_file[0...index].include?(oab_id)
              puts "Skipping duplicate record within file: #{oab_id} at index #{index}"
              
              # Log duplicate
              duplicate_records[oab_id] ||= []
              duplicate_records[oab_id] << {
                "file" => file_name,
                "index" => index,
                "duplicate_type" => "within_file"
              }
              file_stats[:duplicates] += 1
              next
            end
            
            # Save original unprocessed address
            original_address = lawyer_data["address"]
            
            # Parse address if it's a complex string
            address_info = {}
            if lawyer_data["address"].present? && lawyer_data["address"].include?("\n")
              address_info = parse_lawyer_address(lawyer_data["address"])
            else
              address_info = {
                address: lawyer_data["address"] == "Não informado" ? nil : lawyer_data["address"],
                city: lawyer_data["city"],
                state: lawyer_data["seccional"]&.upcase,
                zip_code: lawyer_data["zipcode"]
              }
            end
            
            # Map JSON fields to your schema
            lawyer_attributes = {
              full_name: lawyer_data["full_name"],
              oab_number: lawyer_data["oab_number"],
              oab_id: oab_id,
              state: address_info[:state] || lawyer_data["seccional"]&.upcase,
              city: address_info[:city] || lawyer_data["city"],
              address: address_info[:address],
              zip_code: address_info[:zip_code] || lawyer_data["zipcode"],
              phone_number_1: lawyer_data["phone"].is_a?(Array) && lawyer_data["phone"].any? ? lawyer_data["phone"][0] : nil,
              phone_number_2: lawyer_data["phone"].is_a?(Array) && lawyer_data["phone"].length > 1 ? lawyer_data["phone"][1] : nil,
              profile_picture: "#{lawyer_data['seccional']&.upcase}_#{lawyer_data['oab_number']}_profile_pic.jpg",
              cna_picture: "#{lawyer_data['seccional']&.upcase}_#{lawyer_data['oab_number']}.jpg",
              situation: lawyer_data["status"],
              suplementary: lawyer_data["supplementary"],
              is_procstudio: lawyer_data["is_procstudio"],
              has_society: lawyer_data["has_society"],
              society_id: lawyer_data["society_id"],
              email: lawyer_data["email"],
              profession: lawyer_data["profession"],
              folder_id: lawyer_data["folder_id"],
              original_address: original_address # Keep unprocessed address
            }
            
            # If oab_id already exists in database, process individually
            if existing_oab_ids.include?(oab_id)
              begin
                existing_lawyer = Lawyer.find_by(oab_id: oab_id)
                existing_lawyer.update!(lawyer_attributes)
                file_stats[:updated] += 1
                
                # Log duplicate
                duplicate_records[oab_id] ||= []
                duplicate_records[oab_id] << {
                  "file" => file_name,
                  "index" => index,
                  "duplicate_type" => "in_database"
                }
                file_stats[:duplicates] += 1
              rescue => e
                puts "Error updating existing lawyer with oab_id #{oab_id}: #{e.message}"
                file_stats[:errors] += 1
              end
            else
              # Add to batch for bulk import
              lawyers_to_import << Lawyer.new(lawyer_attributes)
            end
            
          rescue => e
            puts "Error preparing record at index #{index} in #{file_name}: #{e.message}"
            puts "Record data: #{record.inspect}"
            file_stats[:errors] += 1
          end
        end
        
        # Use batch import for new records
        if lawyers_to_import.any?
          puts "Batch importing #{lawyers_to_import.size} new lawyers..."
          
          begin
            import_result = Lawyer.import lawyers_to_import, validate: true
            
            if import_result.failed_instances.any?
              puts "WARNING: #{import_result.failed_instances.size} records failed to import"
              
              # Process failed records individually
              import_result.failed_instances.each do |instance|
                begin
                  puts "Attempting individual import for failed record: #{instance.oab_id}"
                  
                  # Check if it's a duplicate key error (record already exists)
                  existing = Lawyer.find_by(oab_id: instance.oab_id)
                  
                  if existing
                    # Update instead of create
                    existing.assign_attributes(instance.attributes.except("id"))
                    existing.save!
                    file_stats[:updated] += 1
                    
                    # Log duplicate
                    duplicate_records[instance.oab_id] ||= []
                    duplicate_records[instance.oab_id] << {
                      "file" => file_name,
                      "duplicate_type" => "failed_import"
                    }
                    file_stats[:duplicates] += 1
                  else
                    # Try to create individually
                    instance.save!
                    file_stats[:created] += 1
                  end
                rescue => individual_error
                  puts "Error processing individual record #{instance.oab_id}: #{individual_error.message}"
                  file_stats[:errors] += 1
                end
              end
            end
            
            # Count successful imports
            file_stats[:created] += lawyers_to_import.size - import_result.failed_instances.size
            
          rescue ActiveRecord::RecordNotUnique => e
            puts "Duplicate key error during batch import: #{e.message}"
            
            # Fall back to individual processing for all records
            puts "Falling back to individual processing for all records in batch"
            
            lawyers_to_import.each do |lawyer|
              begin
                # Check if record already exists
                existing = Lawyer.find_by(oab_id: lawyer.oab_id)
                
                if existing
                  # Update existing record
                  existing.assign_attributes(lawyer.attributes.except("id"))
                  existing.save!
                  file_stats[:updated] += 1
                  
                  # Log duplicate
                  duplicate_records[lawyer.oab_id] ||= []
                  duplicate_records[lawyer.oab_id] << {
                    "file" => file_name,
                    "duplicate_type" => "batch_fallback"
                  }
                  file_stats[:duplicates] += 1
                else
                  # Create new record
                  lawyer.save!
                  file_stats[:created] += 1
                end
              rescue => individual_error
                puts "Error processing individual record #{lawyer.oab_id}: #{individual_error.message}"
                file_stats[:errors] += 1
              end
            end
          rescue => e
            puts "Error during batch import: #{e.message}"
            puts e.backtrace.join("\n")
            file_stats[:errors] += lawyers_to_import.size
          end
        end
        
        # Mark as processed in the record
        processing_record[file_name] = { 
          "processed" => true,
          "processed_at" => Time.now.iso8601,
          "stats" => file_stats
        }
        
        # Save the updated processing record after each file
        File.write(processing_record_path, JSON.pretty_generate(processing_record))
        
        # Save the duplicate records after each file
        File.write(duplicate_records_path, JSON.pretty_generate(duplicate_records))
        
        # Print file summary
        puts "File #{file_name} processed:"
        puts "  Total records: #{file_stats[:total]}"
        puts "  Created: #{file_stats[:created]}"
        puts "  Updated: #{file_stats[:updated]}"
        puts "  Duplicates: #{file_stats[:duplicates]}"
        puts "  Errors: #{file_stats[:errors]}"
        
      rescue => e
        puts "Error processing file #{file_name}: #{e.message}"
        puts e.backtrace.join("\n")
        
        # Mark as failed in the record
        processing_record[file_name] = { 
          "processed" => false,
          "error" => e.message,
          "error_at" => Time.now.iso8601
        }
        
        # Save the updated processing record even after failure
        File.write(processing_record_path, JSON.pretty_generate(processing_record))
      end
    end
    
    # Final summary
    puts "\nImport complete!"
    puts "Total duplicate oab_ids: #{duplicate_records.keys.size}"
    puts "Details saved to #{duplicate_records_path}"
  end
end

