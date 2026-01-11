# DShare Flutter App

Minimal DShare client for Android, iOS, and Windows. It keeps the same dark theme and command-first flow as the web app, plus gesture commands.

## Run

```bash
flutter pub get
flutter run --dart-define=DSHARE_BASE_URL=https://dshare.me
```

## Commands

- Draw: `R` register, `L` login, `P` paste, `S` status, `C` copy, `M` me, `K` passkey (web only), `H` help
- Draw: up arrow upload, down arrow download
- Type: `/register`, `/login`, `/logout`, `/paste`, `/copy`, `/status`, `/me`, `/help`

## Share sheet support

- Android: intent filters are set in `android/app/src/main/AndroidManifest.xml`.
- iOS: add a Share Extension target in Xcode (per `receive_sharing_intent` docs) to appear in the system share sheet.

## Android Play Store release

1. Ensure the package ID is final in `android/app/build.gradle.kts`:
   - `namespace = "com.divyesh.dshare"`
   - `applicationId = "com.divyesh.dshare"`
2. Create a release keystore (one-time):

```bash
keytool -genkeypair -v -keystore upload-keystore.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000
```

3. Create `android/key.properties`:

```
storeFile=upload-keystore.jks
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=upload
```

4. Build the Play Store bundle:

```bash
flutter build appbundle --release
```

The AAB is at `build/app/outputs/bundle/release/app-release.aab`.

## Android CI signing

Add GitHub secrets:

- `ANDROID_KEYSTORE_BASE64` (base64 of `upload-keystore.jks`)
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_KEY_ALIAS`

The workflow will auto-generate `android/key.properties` in CI when these are set.

## Windows Store packaging (MSIX)

1. Create a Microsoft Partner Center account and reserve your app name.
2. In Partner Center, open your app and copy the values from **Product identity**:
   - `Identity Name`
   - `Publisher` (CN=...)
   - `Publisher Display Name`
3. Update `flutter_app/pubspec.yaml` `msix_config` values (replace `CHANGE_ME`).
4. Build and package:

```bash
flutter build windows --release
dart run msix:create --store
```

The `.msix` file will be in `flutter_app/build/windows/runner/Release/`.
