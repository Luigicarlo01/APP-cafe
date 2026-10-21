#!/usr/bin/env python3
"""Gera front_end/assets/cultivares.json a partir de Data/data_coffee_ciclo.xlsx.

Entrada (duas abas):
    "Informação Cultivares"  Cultivar | Maturação | Ferrugem | Nematóide
    "Dados prod"             municipio | produtor | lat | lon | cultivar |
                             maturacao | ano | bloco | prod

Saída: asset consumido pelo app Flutter (funciona offline, sem endpoint).
Requer rerodar e republicar o app quando a planilha mudar.

As chaves do JSON são normalizadas (minúsculas, sem acento, sem pontuação,
abreviações expandidas). Se essa regra mudar aqui, ajuste também em
`cultivar_info_service.dart`.

A produtividade guarda apenas o ANO MAIS RECENTE em que a cultivar tem
medição naquele escopo (estado ou município), e a média desse ano. O ano
e a contagem de registros vão junto para a UI exibi-los ao lado do número.

Uso:
    python3 tools/gerar_cultivares_json.py
    python3 tools/gerar_cultivares_json.py --entrada outra.xlsx
"""

import argparse
import json
import re
import unicodedata
from datetime import date
from pathlib import Path

import pandas as pd

RAIZ = Path(__file__).resolve().parent.parent
ENTRADA_PADRAO = RAIZ / "Data" / "data_coffee_ciclo.xlsx"
SAIDA_PADRAO = RAIZ / "front_end" / "assets" / "cultivares.json"

# Aplicadas antes de remover a pontuação.
ABREVIACOES = {
    "ama.": "amarelo",
    "verm.": "vermelho",
    "v.": "vermelho",
}


def sem_acento(texto: str) -> str:
    return (
        unicodedata.normalize("NFKD", str(texto))
        .encode("ascii", "ignore")
        .decode("ascii")
    )


def chave_cultivar(nome: str) -> str:
    """'Bourbon Ama. IAC J10' e 'Bourbon Amarelo IAC J10' -> mesma chave."""
    s = sem_acento(nome).lower()
    for abrev, extenso in ABREVIACOES.items():
        s = s.replace(abrev, extenso)
    return re.sub(r"[^a-z0-9]+", " ", s).strip()


def chave_municipio(nome: str) -> str:
    """'Patrocínio' -> 'PATROCINIO'. Bate com o campo `municipio` do backend
    (que vem com sufixo de ano; o app remove antes de consultar)."""
    s = sem_acento(nome).upper().strip()
    return re.sub(r"[^A-Z0-9]+", "_", s).strip("_")


def limpar(texto) -> str | None:
    if texto is None or (isinstance(texto, float) and pd.isna(texto)):
        return None
    return re.sub(r"\s+", " ", str(texto)).strip() or None


def resumo_resistencia(texto: str | None) -> str | None:
    """Rótulo curto para células mistas tipo
    'Suscetível a M. paranaensis, M. incognita. Resistente (M. exigua)'."""
    if not texto:
        return None
    t = sem_acento(texto).lower()
    if t.startswith("moderadamente resistente"):
        return "Moderadamente resistente"
    if t.startswith("resistente"):
        return "Resistente"
    if t.startswith("suscetivel"):
        return "Suscetível"
    return texto.split(".")[0].strip()


def produtividade_recente(df: pd.DataFrame) -> dict | None:
    """Média do ano mais recente presente no recorte."""
    df = df.dropna(subset=["prod", "ano"])
    if df.empty:
        return None
    ano = int(df["ano"].max())
    do_ano = df[df["ano"] == ano]
    return {
        "ano": ano,
        "media": round(float(do_ano["prod"].mean()), 1),
        "registros": int(len(do_ano)),
    }


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--entrada", type=Path, default=ENTRADA_PADRAO)
    ap.add_argument("--saida", type=Path, default=SAIDA_PADRAO)
    args = ap.parse_args()

    xls = pd.ExcelFile(args.entrada)

    info = xls.parse("Informação Cultivares")
    info.columns = [c.strip() for c in info.columns]

    cultivares: dict[str, dict] = {}
    for _, linha in info.iterrows():
        nome = limpar(linha["Cultivar"])
        if not nome:
            continue
        nematoide_txt = limpar(linha.get("Nematóide"))
        resumo = resumo_resistencia(nematoide_txt)
        cultivares[chave_cultivar(nome)] = {
            "nome": nome,
            "maturacao": limpar(linha.get("Maturação")),
            "ferrugem": limpar(linha.get("Ferrugem")),
            "nematoide": resumo,
            "nematoideDetalhe": (
                nematoide_txt if nematoide_txt != resumo else None
            ),
            "produtividade": {"estado": None, "municipios": {}},
        }

    prod = xls.parse("Dados prod")
    prod.columns = [c.strip() for c in prod.columns]
    prod = prod[["municipio", "cultivar", "ano", "prod"]].dropna(
        subset=["cultivar"]
    )

    sem_ficha: set[str] = set()

    for nome_cultivar, grupo in prod.groupby("cultivar"):
        chave = chave_cultivar(nome_cultivar)

        # Cultivar só nos ensaios (sem linha na aba descritiva): entra sem ficha.
        if chave not in cultivares:
            sem_ficha.add(str(nome_cultivar))
            cultivares[chave] = {
                "nome": limpar(nome_cultivar),
                "maturacao": None,
                "ferrugem": None,
                "nematoide": None,
                "nematoideDetalhe": None,
                "produtividade": {"estado": None, "municipios": {}},
            }

        alvo = cultivares[chave]["produtividade"]
        alvo["estado"] = produtividade_recente(grupo)

        for nome_municipio, por_municipio in grupo.groupby("municipio"):
            registro = produtividade_recente(por_municipio)
            if registro:
                alvo["municipios"][chave_municipio(nome_municipio)] = registro

    saida = {
        "_fonte": args.entrada.name,
        "_gerado_em": date.today().isoformat(),
        "_gerado_por": "tools/gerar_cultivares_json.py",
        "cultivares": cultivares,
    }

    args.saida.parent.mkdir(parents=True, exist_ok=True)
    args.saida.write_text(
        json.dumps(saida, ensure_ascii=False, indent=1), encoding="utf-8"
    )

    com_prod = sum(
        1 for c in cultivares.values() if c["produtividade"]["estado"]
    )
    print(f"{len(cultivares)} cultivares → {args.saida}")
    print(f"  {com_prod} com produtividade")
    print(f"  {args.saida.stat().st_size / 1024:.1f} KB")
    if sem_ficha:
        print(f"  sem ficha descritiva: {', '.join(sorted(sem_ficha))}")


if __name__ == "__main__":
    main()
