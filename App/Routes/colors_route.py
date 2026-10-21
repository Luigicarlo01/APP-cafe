from flask import Blueprint, jsonify
from pathlib import Path
import json

colors_bp = Blueprint("colors", __name__)

COLORS_FILE = Path(__file__).resolve().parents[2] / "Data" / "plantios" / "Cafe" / "MG" / "colors_2026.json"

@colors_bp.route("/api/colors", methods=["GET"])
def get_colors():
    if not COLORS_FILE.exists():
        return jsonify({"error": "Arquivo de cores não encontrado"}), 404

    with open(COLORS_FILE) as f:
        colors = json.load(f)

    return jsonify(colors)