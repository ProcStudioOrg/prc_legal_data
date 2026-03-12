---
id: task-20
title: Add Society deletion route with cascade logic
status: Done
assignee: ['@claude']
created_date: '2026-01-11 21:30'
labels:
  - api
  - societies
  - business-rules
dependencies: []
priority: high
---

## Description

Implement proper deletion route for Societies with business rules: 1) If a Society has only one member and that association is removed, the Society cannot persist (auto-delete). 2) When a Society is destroyed directly, all LawyerSociety associations must be removed first. Ensure data integrity and proper cascade behavior.

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Create DELETE /api/v1/society/:inscricao route
- [x] #2 Implement cascade deletion of LawyerSociety records when Society is destroyed
- [x] #3 Add business rule: auto-delete Society when last member association is removed
- [x] #4 Add validation to prevent orphan Society records (societies with 0 members)
- [x] #5 Update Society model with dependent destroy or custom callback
- [x] #6 Write specs for deletion scenarios
- [x] #7 Update Bruno collection with delete endpoint
<!-- AC:END -->

## Implementation Plan

1. Add DELETE route to config/routes.rb
2. Add destroy action to SocietiesController
3. Add after_destroy callback to LawyerSociety for auto-delete orphan societies
4. Add helper methods and scopes to Society model
5. Create Bruno collection file for delete endpoint
6. Write comprehensive specs

## Implementation Notes

### Files Created:
- `spec/requests/api/v1/society_destroy_spec.rb` - Request specs for delete endpoint
- `collection/LegalDataAPI/Societies/Excluir Sociedade.bru` - Bruno collection

### Files Updated:
- `config/routes.rb` - Added `delete 'society/:inscricao'`
- `app/controllers/api/v1/societies_controller.rb` - Added destroy action with cascade logic
- `app/models/lawyer_society.rb` - Added `after_destroy :destroy_orphan_society` callback
- `app/models/society.rb` - Added scopes (`:with_members`, `:orphans`) and helper methods (`has_members?`, `orphan?`, `destroy_orphans!`)
- `spec/models/society_spec.rb` - Added comprehensive model specs
- `spec/models/lawyer_society_spec.rb` - Added specs for auto-delete callback
- `spec/rails_helper.rb` - Fixed RSpec configuration
- `spec/spec_helper.rb` - Fixed RSpec configuration
- `spec/factories/*.rb` - Updated factories for proper test data

### Key Features:
1. **DELETE /api/v1/society/:inscricao** - Deletes society and cascades to lawyer_societies
2. **Auto-delete orphan societies** - When last LawyerSociety is removed, Society is automatically deleted
3. **Scopes** - `Society.orphans` and `Society.with_members` for querying
4. **Cleanup method** - `Society.destroy_orphans!` for batch cleanup

### Test Coverage:
- 39 specs passing
- Model specs for Society and LawyerSociety
- Request specs for API endpoint
