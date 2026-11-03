# Desenvolvimento

## Configuração

1. Instale Flutter 3.47.0, Android SDK e JDK 17.
2. Execute `flutter pub get`.
3. Configure `API_BASE_URL`, `TERMINAL_ID` e `SUPPORT_CONTACT` por `--dart-define`.
4. Implemente a API descrita em [API_CONTRACT.md](API_CONTRACT.md).
5. Rode o app em emulador Android e depois nos terminais Stone físicos.

## Estrutura

- `lib/screens`: telas de login, comanda, mesa, catálogo e caixa.
- `lib/services/management_api.dart`: autenticação, catálogo, pedidos, conta e reconciliação.
- `lib/services/stone_pos_bridge.dart`: interface Flutter para os recursos nativos.
- `android/app/src/main/kotlin`: leitor CameraX/ML Kit e Intents de impressão/pagamento Stone.

O token de sessão permanece em memória e é descartado ao sair/encerrar o app. Nenhum dado de pagamento ou senha é gravado localmente.

## Integração e distribuição

O deeplink precisa voltar para `caravelapdv://pay-response` ou `caravelapdv://print`; mantenha os hosts e o scheme consistentes no Android Manifest, `AppConfig` e chamadas nativas. Confirme o nome de pacote definitivo e as versões de apps/bundle com a Stone antes da homologação.

Configure assinatura de release fora do controle de versão. Não adicione `local.properties`, chaves ou tokens do repositório privado Stone ao Git.
