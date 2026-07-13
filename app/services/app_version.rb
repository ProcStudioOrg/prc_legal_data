# Versão da API.
#
# Número humano e changelog vêm de config/changelog.yml (mantido a cada PR).
# Commit e data do deploy vêm do arquivo REVISION, gravado por infra/deploy.sh.
# Fora do servidor (dev/test) o commit cai para o git local.
class AppVersion
  CHANGELOG_PATH = Rails.root.join("config/changelog.yml")
  REVISION_PATH  = Rails.root.join("REVISION")

  class << self
    def to_h
      {
        version: current[:version],
        released_at: current[:date],
        note: current[:note],
        pr: current[:pr],
        commit: commit,
        branch: revision[:branch],
        deployed_at: revision[:deployed_at],
        environment: Rails.env,
        changelog: changelog
      }
    end

    def changelog
      @changelog ||= begin
        entries = YAML.safe_load_file(CHANGELOG_PATH) || []
        entries.map(&:symbolize_keys)
      rescue Errno::ENOENT, Psych::SyntaxError => e
        Rails.logger.error("changelog.yml ilegível: #{e.message}")
        []
      end
    end

    def current
      changelog.first || {}
    end

    def commit
      revision[:commit] || git_head
    end

    private

    # Gravado pelo deploy. Ausente em dev.
    def revision
      @revision ||= begin
        JSON.parse(File.read(REVISION_PATH)).symbolize_keys
      rescue Errno::ENOENT, JSON::ParserError
        {}
      end
    end

    def git_head
      `git rev-parse --short HEAD 2>/dev/null`.strip.presence
    rescue StandardError
      nil
    end
  end
end
