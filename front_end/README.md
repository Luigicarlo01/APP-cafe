# Cultivar — aplicativo Android

Os dados não são publicados no GitHub. Antes de compilar ou executar os testes,
recoloque os assets privados listados no [README da raiz](../README.md#preparar-o-aplicativo)
e crie o `.env` a partir de `.env.example`. Nesta máquina os arquivos existentes
continuam preservados; essa preparação é necessária em uma nova cópia do projeto.

Execute os comandos abaixo nesta pasta (`front_end`), com Flutter e Android SDK
instalados:

```bash
flutter pub get
flutter test
flutter build apk --release
```

O APK de teste fica em `build/app/outputs/flutter-apk/app-release.apk`. Copie-o
para o Android, abra pelo gerenciador de arquivos e autorize a instalação.
A configuração atual assina o release com a chave de desenvolvimento.

A versão `0.1.0+4` consulta uma cópia SQLite offline dos dados da exportação
`exports/sql/cultivar_2026_mysql.sql.gz`. Pesquisa, limites municipais e
recomendações são lidos do banco incluído no APK, sem precisar manter o MySQL
do computador funcionando. As coordenadas atuais determinam o município;
uma pesquisa anterior não muda essa identificação.

A lista de cultivares e o relatório preservam o ranking da célula selecionada:
vencedora primeiro, seguida das alternativas na ordem original do banco. Os filtros
de ciclo e resistência são aplicados antes do limite de cinco cultivares.
A produtividade municipal ou estadual é informativa e não altera essa ordem.

O mapa de fundo do OpenStreetMap precisa de internet. A permissão `INTERNET`
está no manifesto principal para funcionar também no release. A pesquisa e as
recomendações locais continuam disponíveis sem conexão; o download de mapa
base permanece desativado.

Os GeoJSONs originais continuam em `assets/`, mas os 853 resultados anuais
não são empacotados nesse APK. O `mg.geojson` permanece apenas para o contorno
estadual. O banco fica compactado em `assets/data/cultivar_2026.sqlite.gz`;
na primeira abertura é conferido por SHA-256 e instalado nos dados privados
do app. As próximas aberturas reutilizam a cópia local, fora do cache com TTL.

O banco e o pacote já estão gerados. Para criar uma nova cópia a partir do SQL,
o gerador está na raiz do projeto:

```bash
python3 tools/gerar_sqlite_app.py
```

Ele recusa substituir saídas existentes para preservar as versões anteriores.
Para apenas recompilar o APK atual, use os comandos Flutter do início desta
página. Os detalhes da conversão e dos arquivos preservados estão em
[`docs/15-apk-com-banco-sqlite.md`](../docs/15-apk-com-banco-sqlite.md).

Para conferir no aparelho, teste uma busca por Viçosa, Esmeraldas ou São João
del Rei, confirme um ponto e abra as recomendações. Repita uma busca após
desativar a internet e verifique que os dados locais continuam acessíveis.
