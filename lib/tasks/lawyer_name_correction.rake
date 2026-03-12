# Create this file: lib/tasks/lawyer_name_correction.rake
namespace :lawyer do
  desc "Correct lawyer names based on JSON data"
  task correct_names: :environment do
    puts "📝 Starting lawyer name correction process..."
    
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
    
    # Create a log file for name corrections
    log_file_path = Rails.root.join('lawyer_name_corrections.log')
    log_file = File.open(log_file_path, 'w')
    log_file.write("Lawyer Name Corrections Log - #{Time.current}\n")
    log_file.write("="*60 + "\n")
    
    total_records = 0
    total_corrections = 0
    total_no_correction_needed = 0
    total_not_found = 0
    total_errors = 0
    
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
      
      file_corrections = 0
      file_no_correction_needed = 0
      file_not_found = 0
      file_errors = 0
      
      # Process each JSON object
      json_data.each_with_index do |lawyer_data, index|
        json_id = lawyer_data["id"]
        json_name = lawyer_data["full_name"]
        corrected_name = lawyer_data["corrected_full_name"]
        
        # Find lawyer in database
        lawyer = Lawyer.find_by(id: json_id)
        
        unless lawyer
          puts "#{index + 1}. ❌ ID #{json_id} - #{json_name} - NOT FOUND in database"
          log_file.write("ERROR: Lawyer ID #{json_id} not found in database\n")
          file_not_found += 1
          next
        end
        
        # Check if correction is needed
        if corrected_name.present?
          begin
            puts "#{index + 1}. 📝 ID #{json_id} - Correcting name:"
            puts "     From: #{lawyer.full_name}"
            puts "     To: #{corrected_name}"
            
            # Update the lawyer's name
            lawyer.update!(full_name: corrected_name)
            
            puts "     ✅ Name corrected successfully!"
            
            log_file.write("SUCCESS: Corrected lawyer ID #{json_id} name from '#{lawyer.full_name}' to '#{corrected_name}'\n")
            file_corrections += 1
            
          rescue ActiveRecord::RecordInvalid => e
            error_msg = "Failed to update name for lawyer ID #{json_id}: #{e.message}"
            puts "#{index + 1}. 💥 #{error_msg}"
            puts "     🔍 Validation errors: #{e.record.errors.full_messages}"
            
            log_file.write("ERROR: #{error_msg}\n")
            log_file.write("VALIDATION_ERRORS: #{e.record.errors.full_messages.join(', ')}\n")
            file_errors += 1
            
          rescue => e
            error_msg = "Unexpected error updating lawyer ID #{json_id}: #{e.message}"
            puts "#{index + 1}. 💥 #{error_msg}"
            puts "     📍 Backtrace: #{e.backtrace.first(3).join(' | ')}"
            
            log_file.write("EXCEPTION: #{error_msg}\n")
            log_file.write("BACKTRACE: #{e.backtrace.first(5).join(' | ')}\n")
            file_errors += 1
          end
        else
          puts "#{index + 1}. ✅ ID #{json_id} - #{json_name} - No correction needed"
          file_no_correction_needed += 1
        end
      end
      
      puts "\n📊 File Summary for #{File.basename(file_path)}:"
      puts "📝 Corrections made: #{file_corrections}"
      puts "✅ No correction needed: #{file_no_correction_needed}"
      puts "❌ Not found: #{file_not_found}"
      puts "💥 Errors: #{file_errors}"
      
      log_file.write("\nFile Summary for #{File.basename(file_path)}:\n")
      log_file.write("Corrections made: #{file_corrections}\n")
      log_file.write("No correction needed: #{file_no_correction_needed}\n")
      log_file.write("Not found: #{file_not_found}\n")
      log_file.write("Errors: #{file_errors}\n")
      
      total_corrections += file_corrections
      total_no_correction_needed += file_no_correction_needed
      total_not_found += file_not_found
      total_errors += file_errors
    end
    
    puts "\n" + "="*60
    puts "📊 TOTAL SUMMARY:"
    puts "📁 Files processed: #{json_files.length}"
    puts "📋 Total records: #{total_records}"
    puts "📝 Total corrections made: #{total_corrections}"
    puts "✅ Total no correction needed: #{total_no_correction_needed}"
    puts "❌ Total not found: #{total_not_found}"
    puts "💥 Total errors: #{total_errors}"
    puts "📄 Log file created: #{log_file_path}"
    puts "✨ Name correction process complete!"
    
    log_file.write("\n" + "="*60 + "\n")
    log_file.write("FINAL SUMMARY:\n")
    log_file.write("Files processed: #{json_files.length}\n")
    log_file.write("Total records: #{total_records}\n")
    log_file.write("Total corrections made: #{total_corrections}\n")
    log_file.write("Total no correction needed: #{total_no_correction_needed}\n")
    log_file.write("Total not found: #{total_not_found}\n")
    log_file.write("Total errors: #{total_errors}\n")
    log_file.write("Name correction process completed at: #{Time.current}\n")
    
    log_file.close
  end

  desc "Preview lawyer name corrections without making changes"
  task preview_name_corrections: :environment do
    puts "👀 Previewing lawyer name corrections (no changes will be made)..."
    
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
    
    puts "📁 Found #{json_files.length} JSON files to preview"
    
    total_records = 0
    total_corrections_needed = 0
    total_no_correction_needed = 0
    total_not_found = 0
    
    json_files.each_with_index do |file_path, file_index|
      puts "\n" + "="*60
      puts "📄 Previewing file #{file_index + 1}/#{json_files.length}: #{File.basename(file_path)}"
      puts "="*60
      
      begin
        json_data = JSON.parse(File.read(file_path))
        puts "📁 Loaded #{json_data.length} records from #{File.basename(file_path)}"
        total_records += json_data.length
      rescue JSON::ParserError => e
        puts "❌ Error parsing JSON in #{File.basename(file_path)}: #{e.message}"
        next
      end
      
      file_corrections_needed = 0
      file_no_correction_needed = 0
      file_not_found = 0
      
      # Preview each JSON object
      json_data.each_with_index do |lawyer_data, index|
        json_id = lawyer_data["id"]
        json_name = lawyer_data["full_name"]
        corrected_name = lawyer_data["corrected_full_name"]
        
        # Find lawyer in database
        lawyer = Lawyer.find_by(id: json_id)
        
        unless lawyer
          puts "#{index + 1}. ❌ ID #{json_id} - #{json_name} - NOT FOUND in database"
          file_not_found += 1
          next
        end
        
        # Check if correction would be needed
        if corrected_name.present?
          puts "#{index + 1}. 📝 ID #{json_id} - WOULD CORRECT:"
          puts "     From: #{lawyer.full_name}"
          puts "     To: #{corrected_name}"
          file_corrections_needed += 1
        else
          puts "#{index + 1}. ✅ ID #{json_id} - #{json_name} - No correction needed"
          file_no_correction_needed += 1
        end
      end
      
      puts "\n📊 Preview Summary for #{File.basename(file_path)}:"
      puts "📝 Corrections needed: #{file_corrections_needed}"
      puts "✅ No correction needed: #{file_no_correction_needed}"
      puts "❌ Not found: #{file_not_found}"
      
      total_corrections_needed += file_corrections_needed
      total_no_correction_needed += file_no_correction_needed
      total_not_found += file_not_found
    end
    
    puts "\n" + "="*60
    puts "📊 TOTAL PREVIEW SUMMARY:"
    puts "📁 Files previewed: #{json_files.length}"
    puts "📋 Total records: #{total_records}"
    puts "📝 Total corrections needed: #{total_corrections_needed}"
    puts "✅ Total no correction needed: #{total_no_correction_needed}"
    puts "❌ Total not found: #{total_not_found}"
    puts "✨ Preview complete!"
    puts ""
    puts "💡 To apply these corrections, run: rails lawyer:correct_names"
  end
end
