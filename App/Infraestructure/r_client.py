import requests

R_API_URL = "http://localhost:8000/load_predlist"

def carregar_dados_r(caminho):
    response = requests.post(
        R_API_URL,
        json={"caminho": caminho}
    )

    return response.json()
