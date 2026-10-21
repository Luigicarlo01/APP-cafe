# Carrega um .RData e devolve o objeto `pred.list`.
load_predlist <- function(caminho) {
  env <- new.env()
  load(caminho, envir = env)
  return(env$pred.list)
}
