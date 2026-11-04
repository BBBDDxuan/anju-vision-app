"""Read-only, redacted readiness report. No camera, SDK install or push calls."""
from importlib.util import find_spec
import json
from pathlib import Path
import shutil
import sys

from dotenv import dotenv_values

ROOT = Path(__file__).resolve().parents[1]


def main():
    values = dotenv_values(ROOT.parent / "safety/.env")
    credentials = values.get("SAFETY_FIREBASE_CREDENTIALS") or ""
    credential_file = Path(credentials) if credentials else None
    if credential_file and not credential_file.is_absolute():
        credential_file = ROOT.parent / credential_file
    checks = {
        "phone_platform_confirmed": False,
        "flutter_on_path": bool(shutil.which("flutter") or shutil.which("flutter.bat")),
        "adb_on_path": bool(shutil.which("adb")),
        "firebase_admin_installed_in_this_python": find_spec("firebase_admin") is not None,
        "server_push_mode": values.get("SAFETY_PUSH_MODE") or "mock",
        "server_firebase_credentials_file_exists": bool(credential_file and credential_file.is_file()),
        "android_platform_generated": (ROOT.parent.parent / "anju-vision-app/mobile-app/android").is_dir(),
        "ios_platform_generated": (ROOT.parent.parent / "anju-vision-app/mobile-app/ios").is_dir(),
        "native_firebase_config_exists": any((ROOT.parent.parent / "anju-vision-app" / p).is_file() for p in (
            "mobile-app/android/app/google-services.json", "mobile-app/ios/Runner/GoogleService-Info.plist")),
        "phone_notification_delivery_tested": False,
    }
    print(json.dumps({"status": "needs_user_setup", "checks": checks,
        "scope": "local file/tool discovery only; no notification sent"}, ensure_ascii=False, indent=2))
    return 2  # Explicit incomplete readiness, never a false ready signal.


if __name__ == "__main__":
    sys.exit(main())
