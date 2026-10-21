import requests
from Core.build_index import discover_rdata

R_API_URL = "http://localhost:8000/load_predlist"


def carregar_dados_r(cultura, estado):
    """
    Descobre o arquivo RData e envia para a API do R via HTTP.
    """

    dicionario = discover_rdata()
    arquivo = dicionario[cultura][estado][0]

    response = requests.post(
        R_API_URL,
        json={"caminho": str(arquivo)}
    )

    response.raise_for_status()

    return response.json()


# --- BLOCO DE TESTE ---
if __name__ == "__main__":

    print("--- Teste HTTP com R API ---")

    resultado = carregar_dados_r("Feijão", "SP")

    print("Resultado recebido do R:")
    print(resultado)
