# Test-build signing key

`smriti-test.jks` is a **public, test-only** key (password `smriti-test`). The APK build uses it
when the real signing secrets (`ANDROID_KEYSTORE_BASE64` and friends) are not set, so that every
test APK has the **same signature** and can be installed over the previous one. Without a fixed
key every build gets a new random debug key and Android refuses the update with "App not
installed".

Never use it for a Play Store release or for real patients' phones: anyone can sign an app with
it. Add the real key as repository secrets (docs/DEPLOYMENT.md) and the build uses that instead.
