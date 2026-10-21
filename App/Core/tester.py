import requests
from App.config import DATA_DIR

R_API_URL = "http://localhost:8000/genotypes_ranking"

input_lat = -19.78738
input_lon = -44.31399
top_n = 10

path_trigo = DATA_DIR / "Trigo" / "MG" / "trigoBlups.RData"

response = requests.post(
    R_API_URL,
    json={
        "caminho": str(path_trigo),
        "lat": input_lat,
        "lon": input_lon,
        "top_n": top_n
    }
)

response.raise_for_status()

resultado = response.json()

print("Top genotypes:")
print(resultado)
