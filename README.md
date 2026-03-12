# Backlog

-> Use backlogmd

# Testing & Setup Commands

Generate User with API Key:
```bash
bundle exec rake db:seed_user
```

# Legal Data API Documentation
- Check API File ---> TODO

## Authentication

All API endpoints require authentication using an API key. The API key should be included in the request headers:

```
X-API-KEY: your_api_key_here
```

## Endpoints

### Lawyer Endpoints

```
GET /api/v1/lawyer/:oab
GET /api/v1/lawyer/:oab/debug
GET /api/v1/lawyer/state/:state/last
POST /api/v1/lawyer/create
POST /api/v1/lawyer/update
```

- oab => Consultar um advogado, use o parâmetro: SIGLADOESTADO_NUMEROS (PR_54159)
- oab/debug => Irá retornar alguns campos extras sobre o advogado
- state/:state/last => Consulta o último advogado cadastrado por estado. Essa operação geralmente é um pouco demorada. O objetivo deste endpoint é automatização do scraping (todo mês novos advogados se formam e novas oab são criadas). Use o parâmetro: PR por exemplo
- create => Criar advogado
- update => Atualizar advogado


### Society Endpoints

```
GET    /api/v1/lawyer_societies/:id
GET    /api/v1/lawyer/state/:state/last
POST   /api/v1/society/create
POST   /api/v1/society/:inscricao/update
DELETE *
```

- society :id => Retorna uma sociedade com base na sua id
- state/:state/last => Consulta a última sociedade cadastrado por estado. Essa operação geralmente é um pouco demorada. O objetivo deste endpoint é automatização do scraping (todo mês novas sociedades são criadas e alteradas). Use o parâmetro: PR por exemplo
- create => Criar sociedade
- update => Atualizar sociedade
- delete => Falta rota para deletar uma sociedade. Diferente do advogado que quando é cancelado, removido ou morto terá um tratamento próprio, sociedades podem deixar de existir e serem removidas do banco de dados.
- oab/debug => Não temos essa rota de debug porque todas as informações da sociedade já vem no request principal

### Lawyer & Society Endpoints
```
POST   /api/v1/lawyer_societies
PATCH  /api/v1/lawyer_societies/:id
DELETE /api/v1/lawyer_societies/:id
```

- lawyer_societies => São os métodos para atualizar o relacionamento entre sociedade e advogados

#### Atualizar Relacionamento
{
  "lawyer_id": 456,
  "society_id": 123,
  "partnership_type": "Sócio",
  "cna_link": "https://example.com/cna/doc123"
}
```

**Example Response:**
```json
{
  "message": "Relação entre advogado e sociedade criada com sucesso",
  "lawyer_society": {
    "id": 789,
    "lawyer_id": 456,
    "society_id": 123,
    "partnership_type": "Sócio",
    "cna_link": "https://example.com/cna/doc123",
    "created_at": "2023-06-01T14:23:45.678Z",
    "updated_at": "2023-06-01T14:23:45.678Z"
  },
  "society": {
    "id": 123,
    "name": "Smith & Associates",
    "inscricao": "12345"
  },
  "lawyer": {
    "id": 456,
    "oab_id": "SP_654321",
    "full_name": "John Doe"
  }
}
```
