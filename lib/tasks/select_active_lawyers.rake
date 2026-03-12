# Rake Task to Export Filtered Lawyers to JSON
# File: lib/tasks/export_lawyers.rake

namespace :lawyers do
  desc "Export lawyers with 'situação regular' status and ADVOGADA/ADVOGADO profession to JSON"
  task export_filtered: :environment do
    puts "Starting lawyer export process..."
    
    # Get filtered records
    lawyers = Lawyer.where(
      situation: "situação regular",
      profession: ["ADVOGADA", "ADVOGADO"]
    )
    
    # Check how many records we found
    puts "Found #{lawyers.count} lawyers matching criteria"
    
    if lawyers.any?
      # Convert to JSON
      lawyers_json = lawyers.as_json
      
      # Create exports directory if it doesn't exist
      exports_dir = Rails.root.join('exports')
      FileUtils.mkdir_p(exports_dir) unless Dir.exist?(exports_dir)
      
      # Generate filename with timestamp
      timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
      filename = "lawyers_filtered_#{timestamp}.json"
      filepath = exports_dir.join(filename)
      
      # Save to file
      File.write(filepath, JSON.pretty_generate(lawyers_json))
      
      puts "✅ Export completed successfully!"
      puts "📁 File saved to: #{filepath}"
      puts "📊 Total records exported: #{lawyers.count}"
    else
      puts "❌ No lawyers found matching the criteria"
    end
    
    puts "Export process finished."
  end
end
