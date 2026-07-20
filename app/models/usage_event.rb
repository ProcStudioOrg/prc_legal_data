# Uma linha por consulta ao banco de advogados. Só guarda o hash do IP
# (SHA-256 com salt) — nunca o IP em claro (LGPD). Agregado diariamente
# pelo UsageReportJob.
class UsageEvent < ApplicationRecord
  validates :event_type, presence: true
  validates :ip_hash, presence: true
end
