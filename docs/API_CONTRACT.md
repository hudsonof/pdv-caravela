# API de autenticação e operação do PDV

O aplicativo usa a API existente do sistema de gestão em `https://novo-caravela.vercel.app`. O endereço pode ser sobrescrito com `--dart-define=API_BASE_URL=...` para ambientes locais ou de preview.

## Sessão compartilhada

O login é feito com o e-mail e a senha já cadastrados na gestão. Não há credencial nem token de terminal. O cliente HTTP mantém os cookies recebidos do Auth.js e os envia novamente nas chamadas seguintes.

1. `GET /api/auth/csrf` e leitura do campo `csrfToken`.
2. `POST /api/auth/callback/credentials` como formulário `application/x-www-form-urlencoded`, com `csrfToken`, `email`, `password` e `callbackUrl`. O app guarda os cookies `Set-Cookie` da resposta.
3. `GET /api/auth/session` confirma o login e fornece `user.id`, `user.name`, `user.email`, `user.role` e `user.posCashRegisterId`.
4. `POST /api/auth/signout`, também com CSRF, encerra a sessão.

O app não salva a senha. A sessão Auth.js do sistema tem duração de oito horas. Auth.js usa `POST` para o callback Credentials e CSRF por cookie de dupla submissão; consulte a documentação oficial para mudanças de versão.

## Perfis

| `user.role` | Fluxo no app | Canal retornado pelo bootstrap |
| --- | --- | --- |
| `POS_TICKETS` | Bilheteria e produtos de entrada | `TICKETS` |
| `POS_TABLES` | Venda de mesas | `TABLES` |
| `POS_BAR` | Venda direta do Bar | `BAR` |
| `POS_WAITER` | Pedido de salão com mesa e garçom | `WAITER` |
| `MANAGER`, `ADMIN` | Login compartilhado; abre a gestão web, que aplica as permissões atuais | Sem acesso às rotas POS; o navegador pode pedir novo login |

O backend determina perfil e caixa pela sessão autenticada. O app não envia caixa ou perfil nos corpos das operações.

## Inicialização do PDV

### `GET /api/v1/pos/events`

Lista eventos abertos com sessão de caixa disponível para o usuário autenticado. A resposta é um array com `id`, `name`, `startsAt` e `endsAt`.

### `GET /api/v1/pos/bootstrap?eventId={eventId}`

Carrega evento, sessão, caixa, perfil e catálogo autorizado. A resposta inclui `user`, `register`, `event`, `session`, `products`, `tables` e `waiters`. O produto usa `price` decimal e `imageUrl`; o app converte valores para centavos internamente. Mesas e colaboradores ativos são preenchidos para o perfil `POS_WAITER`.

## Comandas e itens

### `GET /api/v1/pos/orders?eventId={eventId}`

Lista até 100 comandas do evento no caixa e perfil da sessão. O app procura o código informado entre as comandas abertas antes de criar uma nova.

### `POST /api/v1/pos/orders`

Abre uma comanda com `eventId`, `commandCode` e, no fluxo Garçom, `tableId` e `waiterEmployeeId`. Envia `Idempotency-Key`. Resposta contém o pedido criado.

### `GET /api/v1/pos/orders/{id}`

Consulta a comanda, seus itens, pagamentos, mesa, garçom e total.

### `POST /api/v1/pos/orders/{id}/items`

Inclui um produto por chamada com `productId` e `quantity`, mais um `Idempotency-Key` único. O backend calcula o preço efetivo do evento. Em cestas com mais de um produto, o app envia uma chave estável por linha e reutiliza essas chaves em retries.

### `PATCH` e `DELETE /api/v1/pos/orders/{id}/items/{itemId}`

Rotas disponíveis para alteração e remoção de itens antes do primeiro pagamento. O app atual ainda usa inclusão de itens; não expõe alteração ou remoção de itens já adicionados.

### `POST /api/v1/pos/orders/{id}/cancel`

Cancela comanda sem pagamento; corpo `{"reason":"..."}`. A API atual exige motivo.

## Pagamento

### `POST /api/v1/pos/orders/{id}/payments`

Registra pagamento confirmado. Corpo: `{"amount":"12.50","method":"DEBIT"}`; `method` aceita `CASH`, `PIX`, `BANK_TRANSFER`, `DEBIT` ou `CREDIT`. O app só chama essa rota após o retorno de sucesso do app Stone e envia `Idempotency-Key` para que a mesma gravação possa ser repetida com segurança. Depois consulta o pedido novamente; o backend marca `PAID` quando o valor acumulado cobre o total.

O backend atual não possui endpoint de tentativa/reconciliação Stone. Se a maquininha aprovar a transação e o app for encerrado antes do registro no sistema, o atendente deve conferir a comanda e o relatório Stone antes de uma nova cobrança.

## Erros e sessão expirada

A API responde erros no formato `{"error":"mensagem"}`. O app mostra a mensagem retornada. `401` indica que o usuário deve autenticar novamente; `403` indica perfil ou caixa sem permissão; `409` indica evento, sessão ou comanda em estado incompatível.
