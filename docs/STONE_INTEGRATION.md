# Integração com apps Stone no POS

## Pagamento

O app Android abre `payment-app://pay` via Intent com:

- `amount`: total em centavos;
- `editable_amount=0`: impede alteração do total no app de pagamento;
- `order_id`: identificador numérico reservado pela API;
- `return_scheme=caravelapdv`: scheme registrado no manifesto para receber o host `pay-response`.

O app aceita como sucesso de deeplink apenas `code=0`, mas ainda pede ao backend para reconciliar a transação e só fecha a comanda quando a API retorna o estado pago. Valores recebidos são filtrados; PAN e nome do portador não são enviados à API nem registrados em logs.

Se o app de pagamento não estiver instalado, o terminal retorna uma mensagem de integração indisponível. O POS precisa ter os aplicativos Stone necessários e estar associado ao estabelecimento. A integração e o fluxo final devem passar pelo programa de parceiros/homologação da Stone.

## Impressão da conta

O app cria uma lista de linhas de texto e abre `printer-app://print` com `PRINTABLE_CONTENT`, `SHOW_FEEDBACK_SCREEN` e `SCHEME_RETURN=caravelapdv`. O retorno é interpretado como confirmação de impressão ou erro da impressora. A conta impressa é uma prévia para conferência, não o comprovante da transação.

A documentação da Stone informa que o deeplink customizado de impressão depende do bundle de apps POS 7.7.0 ou superior; confirme o bundle presente em cada terminal. Modelos sem esse recurso precisam da alternativa de impressão aprovada para aquele POS, como o provider nativo do SDK.

O payload atual contém texto e não imagens. Isso evita exceder o limite Android de dados entre aplicativos. Para imagens/QR Codes, envie pequenas chamadas sequenciais e aguarde cada retorno.

## Scanner

O botão “Ler código” abre uma tela nativa CameraX + ML Kit com QR Code, EAN-13, EAN-8, Code 128, Code 39 e UPC-A. Leitores integrados configurados como teclado (keyboard wedge) preenchem o campo de comanda com foco e enviam Enter para continuar. Uma API de leitura proprietária do fabricante deve ser adicionada como adapter Kotlin quando o POS não oferece modo teclado.

Digitação manual continua disponível em todos os terminais. A leitura por câmera depende de câmera traseira utilizável e permissão; sem ela, mantenha a alternativa manual ou conecte leitor compatível.

## Matriz inicial a validar

| Terminal | Android informado | Validação necessária |
| --- | --- | --- |
| Sunmi P2-B | Android 7.1 na documentação Stone | Câmera/ML Kit, memória, leitor, impressora e deeplinks |
| Positivo D400 | Android 11 informado pelo projeto | Câmera, leitor, impressora e deeplinks |

O código comum não garante que uma função de hardware exista em todos os terminais. Atualize a matriz apenas após teste físico e homologação.
