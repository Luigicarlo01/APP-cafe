library(plumber)
library(jsonlite)

source("loader_predlist.R")
source("genotypes_ranking.R")
source("genotypes_region.R")

#* @post /load_predlist
function(req, res) {

  body <- fromJSON(req$postBody)
  caminho <- body$caminho

  resultado <- load_predlist(caminho)

  return(resultado)
}

#* @post /genotypes_ranking
function(req, res) {

    body <- fromJSON(req$postBody)

    caminho <- body$caminho
    lat <- body$lat
    lon <- body$lon
    top_n <- body$top_n

    pred_list <- load_predlist(caminho)
    
    resultado <- get_top_genotypes(pred_list, lat, lon, top_n)
    
    return (resultado)
}