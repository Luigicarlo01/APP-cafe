# APK 0.1.0+4 com banco SQL offline

Os bancos, pacotes, GeoJSONs e APKs citados neste guia são arquivos locais
excluídos do Git. Para preparar um clone, consulte os
[dados necessários](../README.md#preparar-o-aplicativo).

Esta versão usa SQLite no celular, com os dados da exportação
`exports/sql/cultivar_2026_mysql.sql.gz`. O MySQL do computador continua
independente do aplicativo. Não há credenciais MySQL no APK nem conexão
direta do Android ao banco do computador.

## Dados incluídos

| Conteúdo | Quantidade |
|---|---:|
| Municípios | 853 |
| Pixels de recomendação | 658.632 |
| Limites municipais | 853 |
| Rankings distintos de pixels | 51 |
| Cultivares por ranking completo | 12 |

As cinco tabelas da exportação SQL são preservadas. As geometrias são
armazenadas como WKB 2D, com precisão double, longitude/latitude, partes e
buracos. A cópia acrescenta metadados de versão, bboxes e pontos interiores
para a pesquisa offline. Nenhum ranking é recalculado.

`LocalMunicipalityService` consulta nomes e limites no SQLite.
`AnalysisService` busca os pixels do município no banco e mantém a vencedora
e as alternativas em sua ordem original. Os filtros de ciclo e resistência
continuam aplicados antes do limite de cinco cultivares da tela.

O contorno estadual `mg.geojson`, as fichas `cultivares.json`, as cores e os
logotipos continuam como assets auxiliares. Os 853 GeoJSONs anuais permanecem
no computador e não são a fonte das recomendações desse APK.

## Arquivos

- `exports/sqlite/cultivar_2026.sqlite`: banco SQLite completo para inspeção
  no computador, com aproximadamente 198 MB.
- `exports/sqlite/cultivar_2026.sqlite.manifest.json`: origem, contagens e hashes.
- `front_end/assets/data/cultivar_2026.sqlite.gz`: pacote incluído no APK,
  aproximadamente 95 MB.
- `front_end/assets/data/manifest.json`: versão e SHA-256 conferidos pelo app.
- `exports/apk/cultivar_0.1.0_3_geojson.apk`: APK anterior preservado.
- `exports/apk/cultivar_0.1.0_4_sqlite.apk`: novo APK após o build.

Na primeira abertura, o aplicativo descompacta o banco em blocos, confere
tamanho e SHA-256 e publica a cópia por renomeação. Depois consulta o arquivo
em um isolate, com `PRAGMA query_only=ON`. O banco fica nos dados privados,
fora do cache regional com prazo de expiração. Uma nova versão de dados
recebe outro nome de arquivo, preservando a anterior.

A primeira abertura precisa de espaço para preparar os aproximadamente
198 MB do banco, além do espaço de instalação do Android. Se a preparação
falhar, a tela de abertura informa o problema e permite tentar novamente.

## Gerar e compilar

Os arquivos de dados já foram gerados. Para recompilar esse APK:

```bash
cd front_end
flutter pub get
flutter test
flutter build apk --release
```

O conversor da origem SQL, na raiz do projeto, é:

```bash
python3 tools/gerar_sqlite_app.py
```

Ele lê o formato gerado por `tools/exportar_geojson_sql.py`; não é um
importador genérico para qualquer dump MySQL. Não lê os GeoJSONs nesta etapa
nem conecta ao servidor. Ele recusa sobrescrever saídas existentes.
Para outro conjunto de dados, gere novos caminhos com `--input`, `--output`
e `--asset-output` e ajuste a referência do manifesto e os assets antes de
compilar. A cópia atual corresponde aos arquivos SQL já gerados, conforme
confirmado pelo usuário; alterações posteriores feitas no MySQL não entram
automaticamente nesse APK.

## Validação

- 12 testes Python passaram, incluindo conversão dos dois dialetos SQL.
- 27 testes Flutter passaram: instalação/reutilização do banco, pesquisa,
  resolução municipal, GPS/cliques, ranking por pixel e filtros.
- Todas as 659.485 feições foram comparadas com os GeoJSONs originais:
  geometrias, propriedades e atributos idênticos.
- Os hashes dos 853 GeoJSONs originais foram conferidos; os arquivos
  permanecem intactos.
- APK release instalado e aberto em Android 16 / API 36 virtual. Com Wi-Fi
  e dados móveis desligados, a primeira abertura preparou o banco, a pesquisa
  encontrou Viçosa e a tela de recomendações exibiu as cultivares locais.
- A assinatura foi conferida e coincide com a do APK `0.1.0+3`. O novo
  `versionCode` é 4; o identificador `com.example.front_end` foi mantido.
- O APK final tem 158.650.184 bytes. O ZIP foi inspecionado: contém o pacote
  SQLite correto e nenhum dos 853 GeoJSONs anuais.

O relatório está em `exports/apk/verificacao_apk_sqlite.json` e a captura do
teste offline em `exports/apk/teste_sqlite_offline.png`.

O mapa de fundo continua dependendo de internet. A consulta dos resultados
e a pesquisa municipal funcionam offline; o download de mapa base e a
sincronização automática com servidor não foram acrescentados nesta versão.

Referência de empacotamento:
[Drift: banco pré-carregado no app](https://drift.simonbinder.eu/examples/existing_databases/).
