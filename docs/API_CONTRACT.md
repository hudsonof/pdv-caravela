# Contrato da API do PDV

O app usa a base `API_BASE_URL` seguida de `/api/pos/v1`. Todas as rotas protegidas usam `Authorization: Bearer <accessToken>` e JSON UTF-8. Valores monetários são inteiros em centavos.

## Autenticação e perfis

### `POST /auth/login`

Request:

```json
{
  "username": "operador",
  "password": "senha",
  "terminalId": "bar-caixa-01"
}
```

Response:

```json
{
  "accessToken": "token-de-sessao",
  "user": {
    "id": "user-123",
    "displayName": "Nome do atendente",
    "profile": {
      "code": "atendimento",
      "name": "Atendimento"
    },
    "permissions": ["pos.orders.create"]
  }
}
```

O perfil Caixa pode usar `profile.code` igual a `caixa`/`cashier` ou a permissão `pos.cashier`. O backend deve validar autorização em cada chamada; a ocultação de telas não é uma barreira de segurança.

## Comandas e pedidos

### `GET /commands/{code}`

Response:

```json
{
  "id": "command-123",
  "code": "1234",
  "status": "open",
  "tableNumber": null
}
```

### `PATCH /commands/{commandId}/table`

Request: `{"tableNumber":"12"}`. O app omite essa chamada quando a mesa é pulada.

### `GET /catalog?profileCode={profileCode}`

Response:

```json
{
  "products": [
    {
      "id": "product-1",
      "name": "Água",
      "description": "Garrafa 500 ml",
      "categoryName": "Bebidas",
      "priceCents": 500,
      "imageUrl": "https://cdn.exemplo.com/produtos/agua.webp",
      "available": true
    }
  ]
}
```

O servidor filtra itens pelo perfil e retorna miniaturas dimensionadas para a grade.

### `POST /commands/{commandId}/items`

Request; o app envia um `Idempotency-Key` único e reutiliza a mesma chave quando uma requisição falha sem confirmação:

```json
{
  "items": [
    {"productId": "product-1", "quantity": 2}
  ]
}
```

O servidor deve deduplicar a chave e rejeitar preço/perfil inválidos. Resposta 2xx indica que os itens foram incluídos.

## Conta e pagamento do perfil Caixa

### `GET /commands/{commandId}/bill`

Response:

```json
{
  "commandId": "command-123",
  "commandCode": "1234",
  "tableNumber": "12",
  "status": "open",
  "paymentStatus": "unpaid",
  "items": [
    {
      "name": "Água",
      "quantity": 2,
      "unitPriceCents": 500,
      "totalCents": 1000
    }
  ],
  "subtotalCents": 1000,
  "discountCents": 0,
  "surchargeCents": 0,
  "totalCents": 1000
}
```

`paymentStatus` deve informar ao menos `unpaid`, `pending`, `processing`, `authorized`, `paid` ou `failed`. O backend calcula os valores; o app não recalcula descontos ou taxas.

### `POST /commands/{commandId}/payments/attempts`

Request com `Idempotency-Key`: `{"amountCents":1000}`.

Response: `{"paymentOrderId":"123456"}`.

O servidor valida que o total ainda é o atual, registra uma tentativa pendente e reserva um identificador numérico aceito pelo app Stone. Repetir a mesma chave retorna a mesma tentativa e o mesmo identificador. Uma nova tentativa só deve ser criada quando a anterior estiver concluída ou marcada como falha/cancelada.

### `POST /commands/{commandId}/payments/reconcile`

Request:

```json
{
  "returnCode": "0",
  "orderId": "123456",
  "amountCents": 1000,
  "transactionKey": "itk-retornado-pela-stone",
  "authorizationCode": "codigo-de-autorizacao"
}
```

O app envia essa rota para qualquer retorno do app Stone; `returnCode` diferente de `0` não representa pagamento aprovado. O servidor deve associar a resposta à tentativa existente, validar pedido, valor e transação, garantir idempotência e atualizar a comanda. Em seguida, o app consulta novamente `GET /bill`; somente `status`/`paymentStatus` confirmados pelo servidor liberam o fechamento.

Se o retorno não chegar, o app consulta a conta. O servidor precisa manter tentativas em estado pendente até poder reconciliá-las, para que o caixa não inicie uma cobrança duplicada.

## Erros

Respostas não-2xx devem trazer JSON opcional como `{"message":"Comanda não encontrada."}`. O app apresenta a mensagem do servidor ou uma mensagem genérica com o código HTTP.
