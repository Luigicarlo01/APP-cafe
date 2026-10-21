from flask import Blueprint, jsonify, request, Response
from Services.municipios_resolver import MunicipioResolver
from pathlib import Path
import json

analysis_bp = Blueprint("analysis", __name__)

GEOJSON_DIR = Path(__file__).resolve().parents[2] / "Data" / "geoJson" / "2026"

# Carregado uma vez no boot: o shapefile IBGE é grande e caro de reler.
resolver = MunicipioResolver()


@analysis_bp.route("/api/analysis/municipio", methods=["POST"])
def get_municipio():
    """Recebe {lat, lng} e devolve {municipio, display_name, winners, bbox}.

    Retorna 400 se lat/lng ausentes, 404 se fora de cobertura ou sem dados.
    """
    body = request.get_json()
    lat = body.get("lat")
    lng = body.get("lng")

    # `is None` porque 0 é lat válido (equador) mas seria falsy.
    if lat is None or lng is None:
        return {"error": "lat e lng são obrigatórios"}, 400

    result = resolver.find_with_bbox(lat, lng)
    if not result:
        return {"error": "Coordenada fora da área de cobertura."}, 404
    stem, bbox, display_name = result

    path = GEOJSON_DIR / f"{stem}.geojson"
    if not path.exists():
        return {"error": f"Sem dados para '{stem}'."}, 404

    with open(path, encoding="utf-8") as f:
        geojson = json.load(f)

    winners = list({
        feat["properties"]["winner"]
        for feat in geojson["features"]
        if feat.get("properties", {}).get("type") == "grid"
        and feat["properties"].get("winner")
    })

    print(winners[:5])

    # Response cru para preservar UTF-8 (jsonify escapa ASCII por padrão).
    return Response(
        json.dumps(
            {
                "municipio":    stem,
                "display_name": display_name,
                "winners":      winners,
                "bbox":         bbox,
            },
            ensure_ascii=False,
        ),
        mimetype="application/json; charset=utf-8",
        status=200,
    )
