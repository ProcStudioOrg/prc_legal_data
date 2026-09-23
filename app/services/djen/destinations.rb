module Djen
  # Um ProcStudio que recebe intimações. Identificado pela base_url normalizada
  # (é a chave do ledger em DjenDelivery), então trocar a URL de um destino
  # equivale a criar um destino novo: o ledger inteiro é reenviado para ele.
  Destination = Data.define(:base_url, :token) do
    def initialize(base_url:, token:)
      super(base_url: Destinations.normalize(base_url), token: token.to_s)
    end

    def key
      base_url
    end

    # Nunca vazar o token em log/inspect.
    def inspect
      "#<Djen::Destination #{base_url}>"
    end
    alias_method :to_s, :inspect
  end

  # Lê os destinos do ambiente.
  #
  #   PROCSTUDIO_DESTINATIONS="https://api-hml.procstudio.com.br|<token hml>,https://api.procstudio.com.br|<token prod>"
  #
  # Sem ela, cai no par legado PROCSTUDIO_BASE_URL + INTEGRATION_DJEN_TOKEN
  # (um destino só). Entrada malformada é erro, não omissão silenciosa: um
  # destino "esquecido" é um ambiente inteiro sem intimação.
  module Destinations
    ConfigurationError = Class.new(StandardError)

    ENV_VAR = "PROCSTUDIO_DESTINATIONS".freeze

    module_function

    def configured(env = ENV)
      raw = env[ENV_VAR].to_s.strip
      return parse(raw) if raw.present?

      base_url = env["PROCSTUDIO_BASE_URL"].to_s.strip
      token = env["INTEGRATION_DJEN_TOKEN"].to_s.strip
      return [] if base_url.blank? || token.blank?

      [ Destination.new(base_url: base_url, token: token) ]
    end

    def parse(raw)
      entries = raw.split(",").map(&:strip).reject(&:blank?)
      destinations = entries.map { |entry| parse_entry(entry) }

      duplicated = destinations.map(&:key).tally.select { |_, n| n > 1 }.keys
      if duplicated.any?
        raise ConfigurationError, "#{ENV_VAR}: destino duplicado (#{duplicated.join(', ')})"
      end

      destinations
    end

    def parse_entry(entry)
      base_url, token = entry.split("|", 2).map { |part| part.to_s.strip }
      if base_url.blank? || token.blank?
        raise ConfigurationError, "#{ENV_VAR}: cada destino é base_url|token, separado por vírgula (recebido: #{entry.inspect})"
      end
      unless base_url.match?(%r{\Ahttps?://}i)
        raise ConfigurationError, "#{ENV_VAR}: base_url precisa começar com http:// ou https:// (recebido: #{base_url.inspect})"
      end

      Destination.new(base_url: base_url, token: token)
    end

    # Sem barra final; esquema e host em minúsculas; caminho intacto.
    def normalize(url)
      url = url.to_s.strip.sub(%r{/+\z}, "")
      url.sub(%r{\A(https?://[^/]+)}i) { |origin| origin.downcase }
    end
  end
end
