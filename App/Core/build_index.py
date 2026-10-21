from pathlib import Path
from App.config import DATA_DIR


def discover_rdata(base=DATA_DIR):
    """Percorre o diretório de dados e devolve {cultura: {estado: [arquivos .RData]}}.

    Os caminhos são relativos a `base`, no formato POSIX.
    """
    estrutura = {}

    for cultura_dir in base.iterdir():
        estados = {}

        for estado_dir in cultura_dir.iterdir():
            arquivos = [
                arquivos.relative_to(base).as_posix()
                for arquivos in estado_dir.glob("*.RData")
            ]

            if arquivos:
                estados[estado_dir.name] = arquivos

        if estados:
            estrutura[cultura_dir.name] = estados

    return estrutura
