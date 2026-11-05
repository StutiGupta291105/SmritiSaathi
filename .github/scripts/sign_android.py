"""Makes the release APK use your own signing key instead of the debug key.

Reads the key from environment variables at build time (they come from GitHub
secrets), so nothing secret is ever written to the repository:
  SMRITI_KEYSTORE_PATH, SMRITI_KEYSTORE_PASSWORD, SMRITI_KEY_ALIAS, SMRITI_KEY_PASSWORD

Run after patch_android.py. Fails loudly if the template changed."""
import sys
from pathlib import Path

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".") / "android" / "app"
gradle = root / "build.gradle.kts"
text = gradle.read_text()

debug = 'signingConfig = signingConfigs.getByName("debug")'
if debug not in text:
    sys.exit(f"sign patch failed: {debug!r} not found in {gradle}")
if "    buildTypes {" not in text:
    sys.exit(f"sign patch failed: buildTypes block not found in {gradle}")

block = '''    signingConfigs {
        create("release") {
            storeFile = file(System.getenv("SMRITI_KEYSTORE_PATH")!!)
            storePassword = System.getenv("SMRITI_KEYSTORE_PASSWORD")
            keyAlias = System.getenv("SMRITI_KEY_ALIAS")
            keyPassword = System.getenv("SMRITI_KEY_PASSWORD")
        }
    }

'''
text = text.replace("    buildTypes {", block + "    buildTypes {", 1)
text = text.replace(debug, 'signingConfig = signingConfigs.getByName("release")', 1)
gradle.write_text(text)
print("release signing configured")
