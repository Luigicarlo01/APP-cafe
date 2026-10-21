# Cultivar — APP-cafe

Código do aplicativo Cultivar para consultar recomendações de cultivares de café
em campo. A versão Android atual (`0.1.0+4`) usa um banco SQLite local, gerado a
partir da exportação MySQL dos resultados previamente calculados.

O ranking segue o pixel selecionado no mapa. O município identifica a região
carregada; a produtividade municipal ou estadual exibida nas fichas é uma
referência informativa e não determina a ordem das cultivares.

## Conteúdo do repositório

- `front_end/`: aplicativo Flutter, configurações das plataformas e testes.
- `App/`: backend Flask do fluxo de consulta por servidor.
- `r_scripts/`: scripts R de preparação dos resultados.
- `tools/`: geradores do catálogo, das fichas e dos bancos MySQL/MariaDB/SQLite.
- `docs/`: documentação técnica, importação SQL e preparação do APK offline.

O repositório contém código, documentação, ícones e logotipos. Bancos,
GeoJSONs, shapefiles, planilhas, resultados de pesquisa, APKs e credenciais
ficam fora do Git. O `.gitignore` permite manter esses arquivos na mesma pasta
do projeto, no computador, sem publicá-los.

## Preparar o aplicativo

Instale Flutter e o Android SDK. Após clonar, obtenha os dados separadamente e
recoloque os arquivos abaixo nos caminhos indicados:

| Caminho local | Conteúdo |
|---|---|
| `front_end/assets/data/cultivar_2026.sqlite.gz` | Banco offline compactado. |
| `front_end/assets/data/manifest.json` | Manifesto correspondente ao banco, com versão e hashes. |
| `front_end/assets/cultivares.json` | Fichas, ciclos, resistências e referências de produtividade. |
| `front_end/assets/colors_2026.json` | Cores das cultivares no mapa. |
| `front_end/assets/mg.geojson` | Contorno estadual usado pelo mapa. |

O banco e o manifesto devem ser do mesmo pacote. A versão atual ainda não
baixa nem atualiza esses dados por servidor. A pesquisa e as recomendações
funcionam offline após a preparação do banco; o mapa de fundo usa internet.

Na pasta `front_end`, crie a configuração local a partir do exemplo:

```bash
cp .env.example .env
flutter pub get
flutter test
flutter build apk --release
```

O `.env` fica fora do Git. Configure as chaves de serviços externos conforme o
[guia de build](front_end/BUILD.md). O APK é gerado em
`front_end/build/app/outputs/flutter-apk/app-release.apk`; a configuração atual
usa a chave de desenvolvimento para a assinatura.

Os testes Flutter que consultam o banco precisam dos dados locais acima. Os
testes que comparam a conversão com a origem também precisam do catálogo
`front_end/assets/municipalities_2026.json` e dos GeoJSONs originais
`front_end/assets/*_2026.geojson`, obtidos separadamente. Os testes dos
conversores Python criam dados temporários e podem ser executados sem os
bancos de pesquisa:

```bash
python3 -m unittest discover -s tools -p 'test_*.py'
```

## Gerar os dados localmente

Os scripts preservam os arquivos de origem. Consulte os parâmetros e os
requisitos em cada guia:

- [GeoJSON para MySQL/MariaDB](docs/14-importar-geojson-sql.md).
- [Exportação SQL para SQLite e APK offline](docs/15-apk-com-banco-sqlite.md).
- [Índice da documentação](docs/README.md).

Essas etapas dependem dos arquivos de entrada obtidos separadamente. Alterações
no MySQL do computador não são sincronizadas automaticamente com o aplicativo.
