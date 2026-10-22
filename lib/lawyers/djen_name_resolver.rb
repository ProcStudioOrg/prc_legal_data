# frozen_string_literal: true

module Lawyers
  # Resolve nome -> inscrições OAB pelo DJEN: busca comunicações por
  # nomeAdvogado e conta, entre os destinatarioadvogados, as inscrições cujo
  # nome normalizado é exatamente o procurado. Sufixo de letra e pontos no
  # número são normalizados ("132153N" e "13.488" viram "132153" e "13488").
  class DjenNameResolver
    Resolution = Struct.new(:name, :total, :registrations, keyword_init: true) do
      # Única inscrição encontrada, ou nil quando há zero ou mais de uma.
      def unique
        registrations.size == 1 ? registrations.keys.first : nil
      end
    end

    def initialize(client: Djen::Client.new, window_days: 365, max_pages: 3)
      @client = client
      @window_days = window_days
      @max_pages = max_pages
    end

    def call(name)
      wanted = Receita::NameNormalizer.call(name)
      counts = Hash.new(0)
      total = 0
      data_fim = Date.current
      @client.each_comunicacao_por_nome(nome_advogado: name, data_inicio: data_fim - @window_days,
                                        data_fim: data_fim, max_pages: @max_pages) do |item|
        total += 1
        Array(item["destinatarioadvogados"]).each do |d|
          adv = d["advogado"] || {}
          next unless Receita::NameNormalizer.call(adv["nome"]) == wanted

          uf = adv["uf_oab"].to_s.upcase
          num = DiscoveryRegistrar.normalize_number(adv["numero_oab"])
          next if uf.blank? || num.blank?

          counts[[ uf, num ]] += 1
        end
      end
      Resolution.new(name: name, total: total, registrations: counts)
    end
  end
end
