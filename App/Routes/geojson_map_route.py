from flask import Blueprint, send_file
from pathlib import Path
from datetime import datetime

geojson_bp = Blueprint("geojson", __name__)
GEOJSON_DIR = Path(__file__).resolve().parents[2] / "Data" / "geoJson" / str(datetime.now().year)


def _get_geojson_path(mun_name: str) -> Path | None:
    """
    Busca o arquivo GeoJSON pelo nome do município.
    Formato esperado: MUNICIPIO_ANO.geojson (ex: OLHOS_D_AGUA_2026.geojson)
    Fallback: qualquer arquivo que comece com o nome, pelo mais recente.
    """
    exact = GEOJSON_DIR / f"{mun_name.upper()}.geojson"
    if exact.exists():
        return exact

    # Fallback para arquivos com sufixo legados ou variações
    files = list(GEOJSON_DIR.glob(f"{mun_name.upper()}*.geojson"))
    return max(files, key=lambda f: f.stat().st_mtime) if files else None


@geojson_bp.route("/api/grid/<mun_name>")
def get_grid(mun_name):
    path = _get_geojson_path(mun_name)
    if not path or not path.exists():
        return {"error": "GeoJSON não encontrado"}, 404

    try:
        # Lê e recodifica para UTF-8
        with open(path, "rb") as f:
            raw = f.read()

        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError:
            text = raw.decode("latin-1")  # fallback

        from flask import Response
        print(f">>> Servindo: {path.name} ({len(raw)/1024:.1f} KB)")
        return Response(text, mimetype="application/json; charset=utf-8")

    except Exception as e:
        print(f">>> ERRO ao servir GeoJSON: {e}")
        return {"error": "Falha interna ao servir GeoJSON"}, 500