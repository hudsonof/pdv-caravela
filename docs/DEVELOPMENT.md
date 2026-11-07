# Desenvolvimento

## Configuração local

1. Instale Flutter 3.47.0, Android SDK e JDK 17.
2. Execute `flutter pub get`.
3. Inicie com `flutter run --dart-define=API_BASE_URL=https://novo-caravela.vercel.app`.
4. Crie na gestão um usuário POS ativo, atribua o caixa compatível e abra uma sessão de caixa para um evento.

O app usa o ambiente de produção por padrão. Para testes locais, use `--dart-define=API_BASE_URL=http://10.0.2.2:PORTA` no emulador ou o endereço acessível pelo terminal. O manifesto de debug permite HTTP; o manifesto de release exige HTTPS.

## Fluxo de dados

O cliente executa CSRF, callback Credentials e consulta de sessão Auth.js. O cookie jar em memória é aplicado às chamadas `/api/v1/pos/*`. Depois consulta eventos e bootstrap; preços, perfil, caixa e autorização vêm do backend. Os itens são enviados individualmente com chave de idempotência por linha.

## Build e dispositivos

```sh
flutter build apk --release \
  --dart-define=API_BASE_URL=https://novo-caravela.vercel.app
```

Configure a assinatura de release no Gradle/CI usando secrets. Valide instalação, autenticação, leitor, câmera, impressão, pagamento e retorno no Sunmi P2-B, Positivo D400 e em cada modelo adicional antes de anunciá-lo como compatível.
