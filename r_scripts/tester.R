library(sf)
source("r_scripts/loader_predlist.R", chdir = TRUE)
source("r_scripts/genotypes_region.R", chdir = TRUE)
source("r_scripts/color_generator.R", chdir = TRUE)

DATA_ROOT <- file.path("Data", "plantios")
caminho <- file.path(DATA_ROOT, "Cafe/MG/dados_cafe.RData")
pred.list <- load_predlist(caminho)

res <- top_map_genotypes(pred.list)  # gera geojsons

colors <- save_colors(pred.list)     # gera JSON de cores