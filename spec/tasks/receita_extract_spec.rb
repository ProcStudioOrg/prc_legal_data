require 'rails_helper'

RSpec.describe 'bin/receita_extract.sh' do
  it 'extrai só linhas do CNAE pedido de todos os shards, em streaming' do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, '001.ndjson'), "#{{ cnpj: '1', cnae_principal: '6911701' }.to_json}\n#{{ cnpj: '2', cnae_principal: '4711301' }.to_json}\n")
      File.write(File.join(dir, '002.ndjson'), "#{{ cnpj: '3', cnae_principal: '6911701' }.to_json}\n")
      File.write(File.join(dir, '003.ndjson'), "#{{ cnpj: '4', cnae_principal: '4711301' }.to_json}\n")
      system('zip', '-q', '-j', File.join(dir, 'data.zip'), File.join(dir, '001.ndjson'), File.join(dir, '002.ndjson'), File.join(dir, '003.ndjson')) || skip('zip indisponível')

      out = File.join(dir, 'advocacia.ndjson')
      stdout = IO.popen([ Rails.root.join('bin/receita_extract.sh').to_s, File.join(dir, 'data.zip'), out, '6911701' ], &:read)
      ok = $?.success?

      expect(ok).to be(true)
      expect(File.readlines(out).map { |l| JSON.parse(l)['cnpj'] }).to eq(%w[1 3])
      expect(stdout).to match(/^FIM shards=3 linhas=2$/)
      expect(File.exist?("#{out}.tmp")).to be(false)
    end
  end

  it 'falha e não gera saída quando o zip não existe' do
    Dir.mktmpdir do |dir|
      out = File.join(dir, 'advocacia.ndjson')
      ok = system(Rails.root.join('bin/receita_extract.sh').to_s, File.join(dir, 'nao_existe.zip'), out, '6911701', out: File::NULL, err: File::NULL)

      expect(ok).to be(false)
      expect(File.exist?(out)).to be(false)
    end
  end
end
