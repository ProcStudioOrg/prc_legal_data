# lib/tasks/db_check.rake
namespace :db do
  namespace :check do
    desc "Check if the WhatsApp fields have been properly added to the lawyers table"
    task whatsapp_fields: :environment do
      require 'active_record/connection_adapters/postgresql_adapter'

      puts "Checking for WhatsApp fields in lawyers table..."

      # Get column information from the DB
      columns = ActiveRecord::Base.connection.columns('lawyers')
      column_names = columns.map(&:name)

      # Check if WhatsApp fields exist
      has_phone_1_whatsapp = column_names.include?('phone_1_has_whatsapp')
      has_phone_2_whatsapp = column_names.include?('phone_2_has_whatsapp')

      if has_phone_1_whatsapp && has_phone_2_whatsapp
        puts "✅ SUCCESS: Both WhatsApp fields are present in the lawyers table:"
        puts "  - phone_1_has_whatsapp (#{columns.find { |c| c.name == 'phone_1_has_whatsapp' }.type})"
        puts "  - phone_2_has_whatsapp (#{columns.find { |c| c.name == 'phone_2_has_whatsapp' }.type})"

        # Check if they're properly accessible in the model
        begin
          lawyer = Lawyer.first
          if lawyer
            lawyer.phone_1_has_whatsapp = true
            lawyer.phone_2_has_whatsapp = false
            if lawyer.save
              puts "✅ SUCCESS: Model attributes are working correctly"

              # Reset the values
              lawyer.phone_1_has_whatsapp = nil
              lawyer.phone_2_has_whatsapp = nil
              lawyer.save
            else
              puts "❌ ERROR: Could not save lawyer with WhatsApp fields"
              puts "Errors: #{lawyer.errors.full_messages.join(', ')}"
            end
          else
            puts "⚠️ WARNING: Could not test model attributes (no lawyers in database)"
          end
        rescue => e
          puts "❌ ERROR: Exception while testing model attributes: #{e.message}"
        end
      else
        puts "❌ ERROR: WhatsApp fields are missing in the lawyers table:"
        puts "  - phone_1_has_whatsapp: #{has_phone_1_whatsapp ? 'Present' : 'Missing'}"
        puts "  - phone_2_has_whatsapp: #{has_phone_2_whatsapp ? 'Present' : 'Missing'}"
        puts "\nPlease run the migration with: bin/rails db:migrate"
      end

      puts "\nMigration Details:"
      migration = ActiveRecord::Base.connection.migration_context.migrations.find { |m| m.name == 'AddWhatsappToLawyers' }
      if migration
        puts "- Migration exists: #{migration.filename}"
        puts "- Version: #{migration.version}"

        # Check if migration has been applied
        if ActiveRecord::Base.connection.migration_context.get_all_versions.include?(migration.version)
          puts "- Status: Applied ✅"
        else
          puts "- Status: Pending ❌"
        end
      else
        puts "- Migration file not found ❌"
      end
    end
  end
end
