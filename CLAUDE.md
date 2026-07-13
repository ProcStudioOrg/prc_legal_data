# prc_legal_data

Rails 8, API-only. Registro de advogados (OAB), sociedades e monitoramento DJEN.

## Regras de negócio

- **Principal x suplementar**: um advogado pode ter várias inscrições OAB, todas apontando para um único `principal_lawyer`. Qualquer OAB do cluster resolve para o principal — nunca trate uma suplementar como pessoa separada.
- **Auth**: toda rota exige `X-API-KEY`, exceto `/api/v1/version` e `/up`. Key `admin` escreve; `read` só GET.
- **DJEN**: um monitoramento por pessoa, sempre no principal. `POST /djen/monitorings` é idempotente e é a **exceção à regra de auth** — qualquer key ativa pode ativar (o ProcStudio só tem key `read`); pausar (`DELETE`) continua `admin`, pois pausar em silêncio significa intimação perdida.
- Mensagens de erro voltam em pt-BR.

## Versionamento (obrigatório)

Toda PR que muda o comportamento público da API adiciona uma entrada no topo de `config/changelog.yml` (`version`, `date` dd/mm/yyyy, `note` em pt-BR, `pr`). Minor para endpoint/campo novo, major para quebra. O commit SHA vem do deploy — não mexer.

## Arquivos centrais

- `config/routes.rb` — superfície da API
- `app/controllers/concerns/api_authentication.rb` — auth, roles, ApiLog
- `app/models/lawyer.rb` — cluster principal/suplementar
- `app/services/djen/` — client, sweep, push para o ProcStudio
- `infra/deploy.sh` — deploy + stamp do REVISION
