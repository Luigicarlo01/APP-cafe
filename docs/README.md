# Documentação do PlantioAPP

Documentação completa do sistema, com foco no aplicativo Flutter.

Escrita a partir da leitura integral do código em `front_end/lib/`
(~10.800 linhas de Dart, 55 arquivos), do backend Flask em `App/` e dos
scripts R em `r_scripts/`.

---

## Como navegar

| # | Documento | O que responde |
|---|-----------|----------------|
| 01 | [Visão geral](01-visao-geral.md) | O que o app faz, para quem, com que stack, e o caminho completo de um dado do R até a tela. |
| 02 | [Arquitetura do Flutter](02-arquitetura-flutter.md) | Como as camadas se organizam, quais padrões o código usa e por quê, convenções que não são óbvias. |
| 03 | [Telas](03-telas.md) | `main.dart` e as 6 telas, uma a uma. |
| 04 | [Controllers](04-controllers.md) | Os 3 controllers: estado de UI e orquestração. |
| 05 | [Services](05-services.md) | Os 9 services fora do cache: análise, busca, localização, ciclo, cultivares, conectividade, boot. |
| 06 | [Cache offline](06-cache-offline.md) | O subsistema inteiro: Drift, quota, TTL, eviction, tiles, mapa base. |
| 07 | [Widgets](07-widgets.md) | Os 11 widgets, incluindo o motor de onboarding. |
| 08 | [Models, utils e assets](08-models-utils-assets.md) | `BoundingBox`, `GenotypePoint`, paleta, assets e o que cada arquivo de `assets/` faz. |
| 09 | [Backend Flask](09-backend-flask.md) | Os 3 endpoints, contratos de request/response e o resolvedor espacial. |
| 10 | [Scripts R](10-r-scripts.md) | O pré-processamento que gera o que o Flask serve. |
| 11 | [Plataformas e build](11-plataformas-build.md) | Android, iOS, permissões, assinatura, versionamento. |
| 12 | [Caminho para produção](12-producao-remover-hardcode.md) | **Os próximos passos**: remover o hardcode de rede e levar o backend para um servidor de verdade. |
| 13 | [Código desativado](13-codigo-desativado.md) | O que está `@Deprecated`, por que continua no repo, e como reativar. |
| 14 | [Importação SQL](14-importar-geojson-sql.md) | Como exportar os GeoJSONs para MySQL/MariaDB e importar o banco. |
| 15 | [APK com SQLite offline](15-apk-com-banco-sqlite.md) | Como a versão atual instala e consulta o banco local e preserva o ranking por pixel. |

Os guias 14 e 15 descrevem a conversão SQL e a versão offline atual. Os guias
anteriores também documentam o fluxo legado de servidor. Os dados citados nos
guias são arquivos locais e não acompanham o clone; consulte o
[README da raiz](../README.md#preparar-o-aplicativo) para preparar os assets.

---

## Relação com os documentos já existentes

Na raiz do repositório há dois arquivos anteriores a esta documentação:

- **`ARCHITECTURE.md`** — guia de arquitetura escrito durante o
  desenvolvimento. Continua válido como visão de alto nível e como
  registro do raciocínio de projeto. Esta pasta `docs/` é mais detalhada
  (desce ao nível de método) e mais atual.
- **`MUDANCAS.md`** — histórico da sessão de simplificação da UI e do
  onboarding. É registro de **decisão**, não de estado. Serve para
  entender *por que* algo foi removido; o estado atual está aqui.

Nenhum dos dois foi alterado.

---

## Cobertura — o que foi lido para escrever isto

| Escopo | Cobertura |
|--------|-----------|
| `front_end/lib/**.dart` | **55 de 55 arquivos lidos por inteiro** |
| `front_end/lib/services/cache/region_database.g.dart` | não lido — 1.219 linhas geradas pelo `build_runner` |
| `App/**.py` | todos lidos por inteiro |
| `tools/gerar_cultivares_json.py` | lido por inteiro |
| `r_scripts/*.R` | todos lidos por inteiro |
| `assets/*` | conteúdo e estrutura inspecionados (geometria, contagens, tamanhos) |
| Android | manifestos `main`/`debug`/`profile`, `build.gradle.kts`, `MainActivity.kt`, `styles.xml`, `launch_background.xml`, e o **manifesto mesclado** gerado pelo Gradle |
| iOS | `Info.plist` e `project.pbxproj` |
| `web/`, `windows/`, `linux/`, `macos/` | verificados apenas quanto a nome e identidade |

Verificações executadas, e não apenas inferidas:

- As duas implementações de normalização de nome de cultivar (Dart e
  Python) foram **rodadas lado a lado** sobre os 40 nomes reais.
- As 47 chaves de município de `cultivares.json` foram **cruzadas** com
  os 853 arquivos de `Data/geoJson/2026/`.
- Cerca de 30 constantes citadas (quotas, TTLs, timeouts, zooms,
  durações de animação, cores) foram conferidas contra o código-fonte.
- Todos os links internos e a citação de cada arquivo `.dart`.

**O que não foi possível fazer**: executar `flutter analyze` ou compilar.
A máquina que tem a pasta montada não tem o Flutter instalado, então as
observações sobre avisos do analisador em
[11](11-plataformas-build.md) são contagem estática sobre o código, e
estão marcadas como tal.

---

## Convenções desta documentação

- Caminhos de arquivo são sempre relativos à raiz do repositório
  (`front_end/lib/...`, `App/Routes/...`).
- Trechos de código são citados, não copiados por inteiro — o código
  fonte é rico em comentários e deve ser lido junto.
- Onde a documentação aponta um problema em aberto, o texto usa o
  marcador **⚠**. O doc 12 consolida todos eles.
