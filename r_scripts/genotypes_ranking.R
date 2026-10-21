get_top_genotypes <- function(pred.list, input_lat, input_lon, top_n = 10) {

  # Para cada genótipo, calcula a produtividade
  # no ponto mais próximo da coordenada
  results_list <- lapply(names(pred.list), function(genotype) {

    df <- pred.list[[genotype]]

    # Índice do ponto mais próximo (distância euclidiana ao quadrado)
    idx <- which.min(
      (df$y - input_lat)^2 + (df$x - input_lon)^2
    )

    # Retorna um data.frame com o resultado desse genótipo
    data.frame(
      genotype = genotype,
      produtividade = df$layer[idx]
    )
  })

  # Junta todos os resultados em um único data.frame
  results <- do.call(rbind, results_list)

  # Ordena da maior para a menor produtividade
  results <- results[order(-results$produtividade), ]

  # Retorna apenas os top N
  return(head(results, top_n))
}
