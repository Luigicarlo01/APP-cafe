import config
from flask import Flask
from Routes.geojson_map_route import geojson_bp
from Routes.analysis_route import analysis_bp
from Routes.colors_route import colors_bp
from waitress import serve

app = Flask(__name__)

app.register_blueprint(geojson_bp)
app.register_blueprint(analysis_bp)
app.register_blueprint(colors_bp)

if __name__ == "__main__":
    serve(app, host="0.0.0.0", port=5000)