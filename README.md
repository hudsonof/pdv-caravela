# Caravela PDV

Aplicativo Flutter Android para lançamento de pedidos e fechamento de comandas em terminais POS. O perfil do atendente vem do sistema de gestão:

- **Atendimento:** informa a comanda, pode vincular uma mesa e seleciona produtos do catálogo autorizado.
- **Caixa:** consulta a conta atual, pode imprimi-la no POS e abrir o app de pagamento Stone.

## O que está implementado

- Login conectado à API do sistema de gestão; token mantido apenas em memória.
- Entrada manual de comanda e leitura por câmera de QR Code, EAN-13/EAN-8, Code 128, Code 39 e UPC-A.
- Entrada por leitor externo configurado como teclado (keyboard wedge), com a caixa de texto da comanda em foco.
- Etapa opcional de mesa e catálogo responsivo com pesquisa, categorias, imagens e carrinho.
- Envio idempotente de itens à comanda.
- Fluxo Caixa: conta detalhada, impressão em texto via app Stone, criação de tentativa de pagamento no backend, abertura do app Stone e reconciliação da transação com o backend.
- Canal Android nativo isolado para scanner, pagamento e impressão.
- Min SDK Android 24; a compatibilidade de cada POS precisa ser confirmada fisicamente e homologada.

## Configuração e execução

Requisitos: Flutter 3.47.0, Android SDK e JDK 17.

```sh
flutter pub get
flutter run \
  --dart-define=API_BASE_URL=https://api.exemplo.com \
  --dart-define=TERMINAL_ID=bar-caixa-01 \
  --dart-define=SUPPORT_CONTACT=suporte@exemplo.com
```

`API_BASE_URL` é a origem da API, sem `/api/pos/v1`. `TERMINAL_ID` deve ser único por equipamento. `SUPPORT_CONTACT` é mostrado na seção “Fale Conosco”.

Use HTTPS. Para desenvolvimento no emulador Android, `http://10.0.2.2:8080` pode ser habilitado no manifesto de debug. Em terminal físico, use uma URL acessível pelo POS e protegida por HTTPS.

O repositório não contém URLs de produção, credenciais, certificados ou dados de loja. O aplicativo não entra em modo de demonstração quando a API está ausente.

## Contrato do sistema de gestão

A API precisa implementar as rotas, respostas e regras de idempotência descritas em [docs/API_CONTRACT.md](docs/API_CONTRACT.md). O servidor é a fonte de verdade para perfis, permissões, preços, conta, total, estado do pagamento e fechamento.

## Stone POS

A integração usa os deeplinks Android oficiais de pagamento e impressão. Os apps Stone correspondentes precisam estar instalados no POS. Pagamento só é confirmado após reconciliação do backend; o retorno do app Stone, isoladamente, não fecha a comanda. Detalhes e dependências estão em [docs/STONE_INTEGRATION.md](docs/STONE_INTEGRATION.md).

O nome de pacote atual (`br.com.novocaravela.pdv.campolivre`) é provisório para desenvolvimento. Confirme-o com o programa de parceiros Stone antes de publicar ou homologar.

## Build de distribuição

Configure a assinatura de release no Gradle/CI com keystore e senhas guardados como secrets. Não versione keystore nem `key.properties`.

```sh
flutter build apk --release \
  --dart-define=API_BASE_URL=https://api.exemplo.com \
  --dart-define=TERMINAL_ID=bar-caixa-01 \
  --dart-define=SUPPORT_CONTACT=suporte@exemplo.com
```

Antes de distribuir, valide instalação, scanner, impressora, deeplink de pagamento, retorno e desempenho no Sunmi P2-B, Positivo D400 e em cada modelo adicional que será anunciado como compatível.
