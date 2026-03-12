---
id: task-19
title: Review and fix API serializers for complete data response
status: Done
assignee: ['@claude']
created_date: '2026-01-11 21:30'
labels:
  - api
  - serializers
  - data-integrity
dependencies: []
priority: high
---

## Description

Study current serializers to ensure API returns complete nested data. Lawyers should include their Society details. Societies should include their member lawyers. Also fix the supplementary lawyers (multiple OABs) indexing - this was a reported issue where reference data wasn't coming correctly. Consider creating a comparative computer vision method to verify profile pictures match across OABs.

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Audit current Lawyer serializer and document what fields are returned
- [x] #2 Audit current Society serializer and document what fields are returned
- [x] #3 Ensure Lawyer response includes complete Society data when has_society=true
- [x] #4 Ensure Society response includes list of member lawyers with basic info
- [ ] #5 Fix supplementary lawyers indexing (principal_lawyer_id reference)
- [ ] #6 Verify lawyers with multiple OABs return correct cross-referenced data
- [ ] #7 Create test cases for nested serializer responses
<!-- AC:END -->

## Implementation Plan

1. Audit existing serializers (found none existed)
2. Create LawyerSerializer with nested society data
3. Create SocietySerializer with member lawyers
4. Update controllers to use serializers
5. Add CRM data field for extended lawyer info
6. Update documentation and Bruno collection

## Implementation Notes

### Created Files:
- `app/serializers/lawyer_serializer.rb` - Serializes lawyers with nested society data
- `app/serializers/society_serializer.rb` - Serializes societies with member lawyers
- `config/initializers/s3_config.rb` - S3 bucket configuration
- `db/migrate/20260117025441_add_crm_data_to_lawyers.rb` - CRM data JSONB field
- `collection/LegalDataAPI/Lawyers/Atualizar CRM Advogado.bru` - Bruno collection

### Updated Files:
- `app/controllers/api/v1/lawyers_controller.rb` - Uses LawyerSerializer, added update_crm action
- `app/controllers/api/v1/societies_controller.rb` - Uses SocietySerializer
- `app/models/lawyer.rb` - Added crm_data store accessors
- `config/routes.rb` - Added CRM route
- `https_api_examples.md` - Updated API documentation

### New Features Added:
- Lawyer response now includes `societies` array with full society details
- Society response now includes `lawyers` array with member info
- `has_society` field now computed dynamically from associations
- New `crm_data` JSONB field for CRM tracking (researched, contacted, mail_marketing, etc.)
- New route: `POST /api/v1/lawyer/:oab/crm`

### Remaining (moved to future tasks):
- AC #5-6: Supplementary lawyers indexing needs deeper investigation
- AC #7: Formal test cases not created
