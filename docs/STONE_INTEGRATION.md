# Integração com apps Stone no POS

## Pagamento

O app abre `payment-app://pay` via Intent com valor em centavos, valor não editável, `transaction_type` selecionado e `return_scheme=caravelapdv`. Após retorno `code=0`, o app registra o valor retornado na comanda pela rota `POST /api/v1/pos/orders/{id}/payments`, enviando forma de pagamento e `Idempotency-Key`. O pedido é recarregado e o backend é a fonte de verdade do estado pago.

O app não considera o retorno Stone sozinho como baixa financeira. Antes de abrir a Stone, salva localmente o identificador da comanda, valor, forma e chave idempotente; também preserva o retorno recebido. Se o processo for recriado após a aprovação, tenta registrar novamente a mesma operação com a mesma chave. O retorno só é apagado depois que a gestão confirma a gravação.

Se a Stone não devolver um resultado associado, o valor divergir ou a gestão não confirmar o registro, o app bloqueia novas cobranças para essa tentativa. O atendente deve conferir Stone e gestão; só pode liberar uma nova tentativa após confirmar que não houve aprovação. A API atual não oferece consulta/reconciliação de transações diretamente com a Stone.

O terminal precisa ter o app Stone de pagamento instalado e estar associado ao estabelecimento. A integração deve ser validada com a Stone e com os modelos de POS usados na operação.

## Impressão da conta

O app envia linhas de texto para `printer-app://print`, com `PRINTABLE_CONTENT`, `SHOW_FEEDBACK_SCREEN` e `SCHEME_RETURN=caravelapdv`. A conta impressa é uma prévia para conferência, não o comprovante fiscal ou de pagamento.

A documentação Stone indica que o deeplink customizado de impressão depende do bundle POS 7.7.0 ou superior; confirme a versão em cada terminal. Se não estiver disponível, será necessário adotar o provider/SDK aprovado para o modelo.

## Scanner

O botão de leitura abre uma tela nativa CameraX + ML Kit para QR Code, EAN-13, EAN-8, Code 128, Code 39 e UPC-A. Leitores integrados configurados como teclado preenchem o campo de comanda com foco e enviam Enter para continuar. Um SDK proprietário do fabricante pode ser integrado como adapter Kotlin quando o leitor não oferece modo teclado.

Digitação manual permanece disponível. A leitura por câmera depende de câmera traseira funcional e permissão do usuário.

## Matriz inicial a validar

| Terminal | Android informado | Validação necessária |
| --- | --- | --- |
| Sunmi P2-B | Android 7.1 | Câmera/ML Kit, memória, leitor, impressora e deeplinks |
| Positivo D400 | Android 11 | Câmera, leitor, impressora e deeplinks |

`minSdk=24` dá suporte a Android 7.0 ou superior. Isso não garante que impressora, scanner integrado ou apps Stone estejam disponíveis em todos os terminais.
