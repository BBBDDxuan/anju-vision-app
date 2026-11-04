"""Compatibility entry point for private local token setup."""
from pathlib import Path
import runpy
runpy.run_path(str(Path(__file__).resolve().parents[2] / "scripts/configure_phone.py"), run_name="__main__")
