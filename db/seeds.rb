# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

require 'faker'

# Brazilian states for OAB
BRAZILIAN_STATES = %w[AC AL AP AM BA CE DF ES GO MA MT MS MG PA PB PR PE PI RJ RN RS RO RR SC SP SE TO].freeze

# Partnership types matching the enum in LawyerSociety model
PARTNERSHIP_TYPES = %w[socio associado socio_de_servico].freeze

# Lawyer situations
LAWYER_SITUATIONS = ['Regular', 'Licenciado', 'Suspenso', 'Cancelado'].freeze

# Society situations
SOCIETY_SITUATIONS = ['Ativa', 'Suspensa', 'Cancelada'].freeze

puts "Starting seed process..."

# Clear existing data in development/test (optional, comment out for production)
if Rails.env.development? || Rails.env.test?
  puts "Cleaning existing data..."
  LawyerSociety.delete_all
  Lawyer.delete_all
  Society.delete_all
end

# ========================================
# Create 50 Societies
# ========================================
puts "Creating 50 societies..."

societies = []
50.times do |i|
  state = BRAZILIAN_STATES.sample
  number_of_partners = rand(2..15) # Society can have 2 to 15 partners

  society = Society.create!(
    inscricao: 100_000 + i,
    name: "#{Faker::Company.name} Advogados Associados",
    state: state,
    oab_id: "#{state}_SOC_#{100_000 + i}",
    address: Faker::Address.street_address,
    zip_code: Faker::Number.number(digits: 8).to_s.insert(5, '-'),
    city: Faker::Address.city,
    phone: Faker::PhoneNumber.phone_number,
    phone_number_2: rand > 0.7 ? Faker::PhoneNumber.phone_number : nil,
    society_link: "https://cna.oab.org.br/sociedade/#{100_000 + i}",
    number_of_partners: number_of_partners,
    situacao: SOCIETY_SITUATIONS.sample
  )

  societies << society
  print "." if (i + 1) % 10 == 0
end
puts "\n50 societies created successfully!"

# ========================================
# Create 200 Lawyers
# ========================================
puts "Creating 200 lawyers..."

lawyers = []
200.times do |i|
  state = BRAZILIAN_STATES.sample
  oab_number = (10_000 + i).to_s

  lawyer = Lawyer.create!(
    full_name: Faker::Name.name,
    social_name: rand > 0.9 ? Faker::Name.name : nil, # 10% have social names
    oab_number: oab_number,
    oab_id: "#{state}_#{oab_number}",
    state: state,
    city: Faker::Address.city,
    address: Faker::Address.full_address,
    original_address: Faker::Address.full_address,
    zip_code: Faker::Number.number(digits: 8).to_s.insert(5, '-'),
    zip_address: Faker::Address.street_address,
    phone_number_1: Faker::PhoneNumber.phone_number,
    phone_number_2: rand > 0.6 ? Faker::PhoneNumber.phone_number : nil,
    phone_1_has_whatsapp: rand > 0.4,
    phone_2_has_whatsapp: rand > 0.6,
    email: Faker::Internet.email,
    profile_picture: "https://example.com/lawyers/#{i + 1}/profile.jpg",
    cna_picture: "https://cna.oab.org.br/lawyer/#{i + 1}/cna.jpg",
    cna_link: "https://cna.oab.org.br/lawyer/#{i + 1}",
    detail_url: "https://oab.org.br/advogado/#{state.downcase}/#{oab_number}",
    situation: LAWYER_SITUATIONS.sample,
    suplementary: rand > 0.9, # 10% are supplementary
    is_procstudio: rand > 0.95, # 5% are from procstudio
    specialty: ['Direito Civil', 'Direito Trabalhista', 'Direito Penal', 'Direito Empresarial', 'Direito Tributário', 'Direito de Família', nil].sample,
    bio: rand > 0.7 ? Faker::Lorem.paragraph(sentence_count: 3) : nil,
    instagram: rand > 0.7 ? "@#{Faker::Internet.username}" : nil,
    website: rand > 0.8 ? Faker::Internet.url : nil,
    profession: 'Advogado',
    folder_id: rand > 0.9 ? Faker::Alphanumeric.alphanumeric(number: 10) : nil,
    has_society: false # Will be updated when associations are created
  )

  lawyers << lawyer
  print "." if (i + 1) % 20 == 0
end
puts "\n200 lawyers created successfully!"

# ========================================
# Create relationships between Lawyers and Societies
# ========================================
puts "Creating lawyer-society relationships..."

relationship_count = 0

societies.each do |society|
  # Assign random number of lawyers to each society (respecting capacity)
  num_lawyers_to_assign = rand(1..[society.number_of_partners, 5].min)

  # Get random lawyers that aren't already in this society
  available_lawyers = lawyers.sample(num_lawyers_to_assign * 2) # Get more than needed to handle conflicts

  assigned_count = 0
  available_lawyers.each do |lawyer|
    break if assigned_count >= num_lawyers_to_assign
    break unless society.can_add_lawyer?

    # Skip if relationship already exists
    next if LawyerSociety.exists?(lawyer_id: lawyer.id, society_id: society.id)

    LawyerSociety.create!(
      lawyer: lawyer,
      society: society,
      partnership_type: PARTNERSHIP_TYPES.sample,
      cna_link: "https://cna.oab.org.br/relacao/#{lawyer.id}/#{society.id}"
    )

    # Update lawyer's has_society flag
    lawyer.update!(has_society: true)

    assigned_count += 1
    relationship_count += 1
  end

  print "." if (societies.index(society) + 1) % 10 == 0
end

puts "\n#{relationship_count} lawyer-society relationships created successfully!"

# ========================================
# Create some supplementary lawyers (linked to principal lawyers)
# ========================================
puts "Creating supplementary lawyer relationships..."

# Get 10 random lawyers to be supplementary (linked to principals)
supplementary_candidates = lawyers.select { |l| l.suplementary }
principal_candidates = lawyers.reject { |l| l.suplementary }

supplementary_count = 0
supplementary_candidates.each do |supplementary|
  principal = principal_candidates.sample
  next if principal.nil?

  supplementary.update!(principal_lawyer_id: principal.id)
  supplementary_count += 1
end

puts "#{supplementary_count} supplementary relationships created!"

# ========================================
# Summary
# ========================================
puts "\n" + "=" * 50
puts "SEED COMPLETED SUCCESSFULLY!"
puts "=" * 50
puts "Total Societies: #{Society.count}"
puts "Total Lawyers: #{Lawyer.count}"
puts "Total Lawyer-Society Relationships: #{LawyerSociety.count}"
puts "Lawyers with Societies: #{Lawyer.where(has_society: true).count}"
puts "Supplementary Lawyers: #{Lawyer.where.not(principal_lawyer_id: nil).count}"
puts "=" * 50
