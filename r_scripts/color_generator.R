# color_generator.R
library(jsonlite)
library(grDevices)

save_colors <- function(pred.list, ano = 2026) {
  color_file <- file.path("Data", "plantios", "Cafe", "MG", paste0("colors_", ano, ".json"))
  
  # garante que a pasta exista
  dir.create(dirname(color_file), recursive = TRUE, showWarnings = FALSE)

  all_genotypes <- names(pred.list)
  
  generate_colors_no_blue <- function(n) {
    hues <- seq(0, 360, length.out = n + 1)[-1]
    hues <- hues[!(hues >= 180 & hues <= 260)]
    if(length(hues) < n) {
      hues <- rep(hues, length.out = n)
    }
    hcl(h = hues, c = 70, l = 65, alpha = 0.8)
  }
  
  colors <- generate_colors_no_blue(length(all_genotypes))
  names(colors) <- all_genotypes
  
  write_json(as.list(colors), color_file, pretty = TRUE, auto_unbox = TRUE)
  cat("✅ Cores salvas em:", color_file, "\n")
  
  return(colors)
}