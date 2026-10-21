import os
import sys 
from dotenv import load_dotenv
from pathlib import Path

load_dotenv()

R_SERVICE_URL = os.getenv("R_SERVICE_URL", "http://localhost:8000")

PROJECT_ROOT = Path(__file__).resolve().parent
DATA_DIR = PROJECT_ROOT / "Data" / "plantios"
R_SCRIPTS_DIR = PROJECT_ROOT / "r_scripts"

if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))