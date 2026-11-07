# Caravela PDV

Aplicativo Flutter Android para operações de Bilheteria, Mesas, Bar e Garçom nos terminais Stone. O login usa os mesmos usuários da gestão e consulta a sessão Auth.js antes de liberar qualquer operação.

## Fluxo implementado

- Login por e-mail e senha, com CSRF e cookie jar para a sessão Auth.js.
- Consulta de eventos disponíveis; seleção do evento carrega sessão de caixa, perfil e catálogo via bootstrap.
- Perfis `POS_TICKETS`, `POS_TABLES`, `POS_BAR` e `POS_WAITER`; Garçom escolhe mesa e colaborador antes de abrir a comanda.
- Entrada de comanda por digitação ou leitura de QR Code/códigos de barras pela câmera. Leitor integrado configurado como teclado também pode preencher o campo.
- Reaproveitamento de comanda aberta, inclusão idempotente de produtos e imagens retornadas pela gestão.
- Conferência/impressão da conta e pagamento pelo app Stone. O pagamento só é registrado na gestão depois do retorno de sucesso da Stone.
- Perfis `MANAGER` e `ADMIN` autenticam com a mesma conta e podem abrir o sistema de gestão no navegador; não acessam as rotas POS. O navegador mantém sua própria sessão.

## Executar

Requisitos: Flutter 3.47.0, Android SDK e JDK 17.

```sh
flutter pub get
flutter run \
  --dart-define=API_BASE_URL=https://novo-caravela.vercel.app \
  --dart-define=SUPPORT_CONTACT=suporte@exemplo.com
```

O endereço de produção já é o padrão. `API_BASE_URL` pode ser sobrescrito para ambientes de desenvolvimento e preview. O app não armazena a senha; os cookies da sessão permanecem no cookie jar em memória durante o processo do aplicativo.

Confira rotas e payloads em [docs/API_CONTRACT.md](docs/API_CONTRACT.md). A API do sistema de gestão precisa estar implantada e o usuário POS deve estar ativo, associado a um caixa compatível e a uma sessão aberta.

## Android e Stone

O `minSdk` é 24, compatível com Android 7 ou superior. Scanner, pagamentos e impressão usam código Android nativo e deeplinks Stone. A disponibilidade varia por terminal, versões dos apps POS e configuração do estabelecimento. Confira [docs/STONE_INTEGRATION.md](docs/STONE_INTEGRATION.md) e valide fisicamente cada modelo.

O package name `br.com.novocaravela.pdv.campolivre` é provisório. Defina o package aprovado pelo programa Stone antes de publicar. Configure assinatura de release com keystore e senhas guardados em secrets; não versione keystore nem `key.properties`.
