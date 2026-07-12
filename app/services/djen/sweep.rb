module Djen
  # Sweeps DJEN for one monitoring: queries every OAB of the lawyer (principal
  # + supplementary inscriptions) over a date window, upserts the ledger,
  # computes labels and detects cancellations.
  class Sweep
    Result = Struct.new(:created, :cancelled, keyword_init: true)

    def initialize(monitoring, window_days:, client: Client.new)
      @monitoring = monitoring
      @window_days = window_days
      @client = client
    end

    def call
      result = Result.new(created: 0, cancelled: 0)
      data_fim = Date.current
      data_inicio = data_fim - @window_days

      @monitoring.monitored_lawyers.each do |lawyer|
        next if lawyer.oab_number.blank? || lawyer.state.blank?

        learner = AdvogadoIdLearner.new(lawyer, numero_oab: lawyer.oab_number, uf_oab: lawyer.state)

        @client.each_comunicacao(numero_oab: lawyer.oab_number, uf_oab: lawyer.state,
                                 data_inicio: data_inicio, data_fim: data_fim) do |item|
          learn_status = learner.call(item)
          upsert(item, learn_status, result)
        end
      end

      @monitoring.update!(last_swept_at: Time.current)
      result
    end

    private

    def upsert(item, learn_status, result)
      record = DjenComunicacao.find_by(djen_id: item["id"])

      if record.nil?
        create_record(item, learn_status)
        result.created += 1
      elsif record.ativo && item["ativo"] == false
        record.update!(ativo: false, raw: item)
        result.cancelled += 1
      end
    end

    def create_record(item, learn_status)
      @monitoring.djen_comunicacoes.create!(
        djen_id: item["id"],
        djen_hash: item["hash"],
        numero_processo: item["numero_processo"],
        sigla_tribunal: item["siglaTribunal"],
        data_disponibilizacao: item["data_disponibilizacao"],
        ativo: item["ativo"] != false,
        labels: labels_for(item, learn_status),
        raw: item
      )
    end

    def labels_for(item, learn_status)
      labels = []
      labels << (known_processo?(item["numero_processo"]) ? "processo_conhecido" : "novo_processo")
      labels << "ambiguo" if learn_status == :mismatch
      labels
    end

    def known_processo?(numero_processo)
      return false if numero_processo.blank?

      @monitoring.djen_comunicacoes.exists?(numero_processo: numero_processo)
    end
  end
end
