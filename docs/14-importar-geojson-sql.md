# Exportar os GeoJSONs para MySQL/MariaDB

O conversor cria novos arquivos SQL. Não altera nem apaga os GeoJSONs,
não conecta a servidores e não modifica o funcionamento do aplicativo.
Não executa cálculos de recomendação: exporta os resultados existentes.

## Arquivos prontos

Na pasta `exports/sql/`:

- `cultivar_2026_mysql.sql.gz`: destinado a MySQL 8.0+, incluindo Cloud SQL
  para MySQL; preferir MySQL 8.4.
- `cultivar_2026_mariadb.sql.gz`: destinado a MariaDB 10.6+.
- Os arquivos `*.manifest.json` registram contagens, tamanho e SHA-256 da
  exportação e de cada GeoJSON de origem.

Escolha o arquivo correspondente ao servidor. As geometrias usam WGS84
(SRID 4326). A sintaxe difere porque o MySQL precisa da opção
`axis-order=long-lat` para interpretar explicitamente a ordem longitude,
latitude do GeoJSON; a versão MariaDB usa os dois argumentos suportados
por esse banco.

## Gerar novamente

Na raiz do projeto, com Python 3 (sem instalar dependências):

```bash
python3 tools/exportar_geojson_sql.py --dialect mysql
python3 tools/exportar_geojson_sql.py --dialect mariadb
```

O script recusa substituir uma saída existente. Para uma nova exportação,
escolha outro nome, mantendo a anterior:

```bash
python3 tools/exportar_geojson_sql.py --dialect mysql \
  --output exports/sql/cultivar_2026_mysql_v2.sql.gz
```

Para exportar somente alguns municípios, use as chaves dos arquivos:

```bash
python3 tools/exportar_geojson_sql.py --dialect mysql \
  --municipios VICOSA ESMERALDAS \
  --output exports/sql/exemplo_dois_municipios_mysql.sql.gz
```

Para SQL sem compactação, indique uma saída terminada em `.sql`.
Por padrão, o script lê `front_end/assets/*_2026.geojson` e o catálogo
`municipalities_2026.json`. `--year` e `--assets-dir` permitem outra origem.
Os arquivos auxiliares `mg.geojson`, `esmeraldas.geojson` e
`cultivares.json` não fazem parte desta exportação dos resultados anuais.

## Estrutura do banco

| Tabela | Conteúdo |
|---|---|
| `cultivar_municipios` | Código IBGE, nome oficial e UF |
| `cultivar_arquivos` | Município/ano, arquivo de origem, cabeçalho GeoJSON, SHA-256 e contagem |
| `cultivar_rankings` | Propriedades originais e cultivar vencedora de cada ranking distinto |
| `cultivar_ranking_itens` | Cultivares em ordem: posição 1 é a vencedora; seguintes são as alternativas |
| `cultivar_feicoes` | Cada pixel ou limite municipal, geometria nativa, ranking associado e índice original |

Há um índice espacial sobre `geometria`. Rankings iguais são compartilhados
por várias feições; a associação continua sendo por pixel, sem reordenar
pela produtividade municipal. As propriedades originais permanecem no JSON.
Polígonos, multipolígonos e buracos são preservados, sem simplificação,
arredondamento intencional ou correção automática da topologia original.

## Importar em um servidor

Crie um **banco vazio** pelo painel do seu provedor. Por exemplo, use o nome
`cultivar_2026`. O SQL cria as cinco tabelas e carrega os dados; ele não
contém `DROP`, `TRUNCATE`, `CREATE DATABASE` nem `USE`. Se houver tabelas com
esses nomes, a importação falhará em vez de apagá-las. Não use a opção
`--force` do cliente para ignorar erros.

Com o cliente MySQL instalado e acesso ao servidor configurado:

```bash
set -o pipefail
gzip -dc exports/sql/cultivar_2026_mysql.sql.gz | \
  mysql --default-character-set=utf8mb4 --max-allowed-packet=64M \
  -h ENDERECO_DO_SERVIDOR -u SEU_USUARIO -p cultivar_2026
```

Para MariaDB:

```bash
set -o pipefail
gzip -dc exports/sql/cultivar_2026_mariadb.sql.gz | \
  mariadb --default-character-set=utf8mb4 --max-allowed-packet=64M \
  -h ENDERECO_DO_SERVIDOR -u SEU_USUARIO -p cultivar_2026
```

Substitua endereço e usuário. A senha será solicitada pelo cliente. Siga a
configuração TLS ou proxy indicada pelo provedor para conexões remotas.
O usuário de importação precisa de permissão para criar as tabelas, os
índices e as chaves estrangeiras e inserir dados no banco de destino.

O arquivo compactado não corresponde ao espaço ocupado no servidor:
MySQL/MariaDB descompactam os dados e criam índices, logs e outros arquivos.
Reserve espaço com folga e confirme o consumo depois da importação.
A carga confirma uma transação por município. Se for interrompida,
podem permanecer municípios já carregados e tabelas criadas. Use outro
banco vazio para tentar novamente; o conversor não apaga o banco anterior.

### Google Cloud SQL

1. Use uma instância **Cloud SQL para MySQL** e crie um banco vazio.
2. No painel da instância, abra **Importar**, formato **SQL**.
3. Selecione `cultivar_2026_mysql.sql.gz`, enviando-o para um bucket Cloud
   Storage se necessário.
4. Selecione o banco vazio de destino e um usuário com as permissões de
   importação. A conta de serviço da instância precisa poder ler o arquivo
   no bucket.
5. Execute a importação e confira as contagens abaixo.

O Google aceita arquivos `.sql` e `.gz`. **Cloud Storage guarda o arquivo;
Cloud SQL executa o banco e é cobrado separadamente.** A faixa gratuita
de armazenamento de arquivos não torna a instância Cloud SQL gratuita.
Não é preciso tornar o arquivo SQL público para importar.

## Conferir a importação

```sql
SELECT COUNT(*) AS municipios FROM cultivar_municipios;
-- 853

SELECT tipo, COUNT(*) AS total FROM cultivar_feicoes GROUP BY tipo;
-- grid: 658632; municipio: 853

SELECT COUNT(*) AS rankings FROM cultivar_rankings;
-- 52 conjuntos de propriedades: 51 rankings de pixels + 1 limite municipal

SELECT COUNT(*) AS itens FROM cultivar_ranking_itens;
-- 612 = 51 rankings de 12 cultivares
```

Exemplo: consultar o ranking do primeiro pixel de Viçosa, na ordem original:

```sql
SELECT i.posicao, i.cultivar
FROM cultivar_feicoes f
JOIN cultivar_arquivos a ON a.id = f.arquivo_id
JOIN cultivar_ranking_itens i ON i.ranking_id = f.ranking_id
WHERE a.arquivo = 'VICOSA_2026.geojson'
  AND f.indice = 1 AND f.tipo = 'grid'
ORDER BY i.posicao;
```

Para buscar pixels por coordenadas no MySQL:

```sql
SET @ponto = ST_GeomFromText('POINT(-42.88 -20.75)',4326,'axis-order=long-lat');
SELECT a.arquivo, f.indice, r.vencedor
FROM cultivar_feicoes f
JOIN cultivar_arquivos a ON a.id = f.arquivo_id
JOIN cultivar_rankings r ON r.id = f.ranking_id
WHERE f.tipo = 'grid' AND a.ano = 2026
  AND MBRIntersects(f.geometria,@ponto)
  AND ST_Intersects(f.geometria,@ponto)
ORDER BY a.arquivo, f.indice;
```

No MariaDB, crie o ponto sem o terceiro argumento:

```sql
SET @ponto = ST_GeomFromText('POINT(-42.88 -20.75)',4326);
```

Depois use a mesma consulta. Pontos em fronteiras podem encontrar mais
de um pixel; pontos fora da cobertura não retornam resultados.

## Uso pelo aplicativo

A partir do APK `0.1.0+4`, o app usa uma cópia SQLite offline destas tabelas,
gerada pelo script `tools/gerar_sqlite_app.py` a partir da exportação SQL.
O Android não executa o dump MySQL/MariaDB diretamente. O banco MySQL no
servidor e a cópia SQLite no celular continuam independentes: alterações no
servidor exigem gerar e distribuir outro pacote. O fluxo de download e
atualização automática será uma etapa separada.

Veja [APK com SQLite](15-apk-com-banco-sqlite.md).

## Testes do conversor

```bash
python3 -m unittest discover -s tools -p 'test_*.py' -v
```

Validação executada nesta entrega: nove testes automatizados do conversor
e importação completa dos dois arquivos em MySQL 8.4.11 e MariaDB 11.8.6.
As contagens das cinco tabelas foram conferidas, assim como a ordem das
cultivares, uma consulta por coordenadas e a recuperação de nove
geometrias e suas propriedades em Viçosa, Esmeraldas e Olhos-d'Água.
Os SHA-256 dos 853 GeoJSONs de origem foram comparados com os manifestos
para confirmar que os originais permaneceram intactos.

## Referências

- [Importação SQL no Cloud SQL](https://docs.cloud.google.com/sql/docs/mysql/import-export/import-export-sql)
- [Geometrias WKT e ordem dos eixos no MySQL](https://dev.mysql.com/doc/refman/8.4/en/gis-wkt-functions.html)
- [Índices espaciais no MySQL](https://dev.mysql.com/doc/refman/8.4/en/creating-spatial-indexes.html)
- [ST_GeomFromText no MariaDB](https://mariadb.com/docs/server/reference/sql-statements/geometry-constructors/wkt/st_geomfromtext)
