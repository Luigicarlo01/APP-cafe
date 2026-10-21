get_utm_crs <- function(sf_obj) {
  centroid <- st_centroid(st_union(sf_obj))
  coords   <- st_coordinates(centroid)
  zone     <- floor((coords[1] + 180) / 6) + 1
  epsg     <- if (coords[2] < 0) 32700 + zone else 32600 + zone
  st_crs(epsg)
}


top_map_genotypes <- function(pred.list, n_top = 5) {
  # n_top controla quantos genótipos exportar (winner + alternatives).
  # Para mudar de top5 para top3: top_map_genotypes(pred.list, n_top = 3)
  # O Flutter lê o array "alternatives" sem precisar de nenhuma alteração.

  mun_path    <- "Data/shapefiles/municipality/BR_Municipios_2021.shp"
  municipios  <- suppressMessages(st_read(mun_path, quiet = TRUE))
  municipios  <- municipios[municipios$SIGLA == "MG", ]

  ano         <- format(Sys.time(), "%Y")
  geojson_dir <- file.path(getwd(), "Data", "geoJson", ano)
  dir.create(geojson_dir, showWarnings = FALSE, recursive = TRUE)

  df_base    <- pred.list[[1]][, c("x", "y")]
  layers_mat <- do.call(cbind, lapply(pred.list, `[[`, "layer"))

  if (is.null(colnames(layers_mat))) {
    colnames(layers_mat) <- names(pred.list)
  }

  # Requer jsonlite para serializar arrays nativamente
  if (!requireNamespace("jsonlite", quietly = TRUE)) stop("Instale o pacote jsonlite")

  winner     <- character(nrow(layers_mat))
  alts_list  <- vector("list", nrow(layers_mat))  # lista de vetores → array JSON nativo

  for (i in seq_len(nrow(layers_mat))) {
    v <- layers_mat[i, ]
    if (all(is.na(v))) {
      winner[i]    <- NA_character_
      alts_list[[i]] <- character(0)
      next
    }

    ord  <- order(v, decreasing = TRUE, na.last = NA)
    gen  <- colnames(layers_mat)[ord]

    winner[i]      <- gen[1]
    alts_list[[i]] <- gen[seq(2, min(n_top, length(gen)))]
  }

  # Serializa alternatives como JSON array por linha
  alts_json <- sapply(alts_list, function(x) {
    if (length(x) == 0) return("[]")
    jsonlite::toJSON(x, auto_unbox = FALSE)
  })

  df <- data.frame(df_base, winner, alternatives = alts_json)

  # Remove linhas sem genótipo vencedor e sem coordenadas — igual ao original,
  # mais o filtro de coordenadas que resolve o erro de NAs no st_as_sf
  df <- df[!is.na(df$winner), ]
  df <- df[!is.na(df$x) & !is.na(df$y), ]

  for (i in seq_len(nrow(municipios))) {

    municipio_sf <- municipios[i, ]
    bb           <- st_bbox(municipio_sf)

    # Filtro rápido pelo bounding box — igual ao original
    df_sub <- df[
      df$x >= bb$xmin & df$x <= bb$xmax &
      df$y >= bb$ymin & df$y <= bb$ymax,
    ]

    if (nrow(df_sub) == 0) next

    df_sf_sub <- st_as_sf(
      df_sub,
      coords = c("x", "y"),
      crs    = st_crs(municipios)
    )

    df_sf_sub <- df_sf_sub[
      st_intersects(df_sf_sub, municipio_sf, sparse = FALSE),
    ]

    if (nrow(df_sf_sub) == 0) next

    crs_proj <- get_utm_crs(municipio_sf)
    area_utm <- st_transform(municipio_sf, crs_proj)
    df_utm   <- st_transform(df_sf_sub, crs_proj)

    grid_1ha <- st_make_grid(area_utm, cellsize = c(1000, 1000), square = TRUE)
    grid_1ha <- st_sf(geometry = grid_1ha)
    grid_1ha <- st_intersection(grid_1ha, area_utm)

    idx <- st_nearest_feature(grid_1ha, df_utm)

    grid_1ha$winner       <- df_utm$winner[idx]
    grid_1ha$alternatives <- df_utm$alternatives[idx]

    municipio_plot <- st_transform(municipio_sf, 4326)
    grid_plot      <- st_transform(grid_1ha, 4326)

    municipio_clean <- st_sf(
      type         = "municipio",
      winner       = NA_character_,
      alternatives = "[]",
      geometry     = st_geometry(municipio_plot),
      crs          = 4326
    )

    grid_clean <- st_sf(
      type         = "grid",
      winner       = grid_plot$winner,
      alternatives = grid_plot$alternatives,
      geometry     = st_geometry(grid_plot),
      crs          = 4326
    )

    export_sf <- rbind(municipio_clean, grid_clean)

    mun_name     <- toupper(municipio_sf$NM_MUN)
    mun_name     <- iconv(mun_name, to = "ASCII//TRANSLIT")
    mun_name     <- gsub("[^A-Z0-9]", "_", mun_name)

    fname        <- sprintf("%s_%s.geojson", mun_name, ano)  # ex: OLHOS_D_AGUA_2026.geojson
    geojson_path <- file.path(geojson_dir, fname)

    st_write(
      export_sf,
      geojson_path,
      driver        = "GeoJSON",
      delete_dsn    = TRUE,
      quiet         = TRUE,
      layer_options = "ENCODING=UTF-8"
    )

    cat("✔", mun_name, "\n")
  }

  cat("\n✅ Finalizado!\n")
}