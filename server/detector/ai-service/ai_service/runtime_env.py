"""Keep model-library state alongside the project, before third-party imports."""
from pathlib import Path
import os


def configure_model_runtime():
    root = Path(__file__).resolve().parents[2]
    mapping = {"YOLO_CONFIG_DIR": root.parent / "runtime/detector" / "ultralytics",
               "TORCH_HOME": root.parent / "runtime/detector" / "torch",
               "HF_HOME": root.parent / "runtime/detector" / "huggingface",
               "MPLCONFIGDIR": root.parent / "runtime/detector" / "matplotlib"}
    for key, directory in mapping.items():
        directory.mkdir(parents=True, exist_ok=True)
        os.environ[key] = str(directory)
    (mapping["YOLO_CONFIG_DIR"] / "Ultralytics").mkdir(exist_ok=True)
    os.environ["YOLO_AUTOINSTALL"] = "false"
    os.environ["YOLO_OFFLINE"] = "true"
    return root
