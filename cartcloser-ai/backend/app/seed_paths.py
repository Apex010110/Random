"""Location of the shared seed files (repo-root /seed, overridable with SEED_DIR)."""
import os
from pathlib import Path

SEED_DIR = Path(os.environ.get("SEED_DIR", Path(__file__).resolve().parents[2] / "seed"))
DEMO_SEED_PATH = SEED_DIR / "demo_seed.json"
ASSISTANT_COPY_PATH = SEED_DIR / "assistant_copy.json"
