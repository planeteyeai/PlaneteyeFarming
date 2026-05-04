# CropEye — Play Store CI/CD Setup Guide

## 1. Generate the release keystore (one-time, local)

```bash
keytool -genkey -v \
  -keystore upload-keystore.jks \
  -keyalg RSA -keysize 2048 \
  -validity 10000 \
  -alias upload
```

Store `upload-keystore.jks` somewhere safe (password manager / private storage).  
**Never commit it to git.**

---

## 2. Create android/key.properties (local dev only)

```
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=upload
storeFile=../../upload-keystore.jks
```

---

## 3. Encode keystore for GitHub Secrets

```bash
base64 -w 0 upload-keystore.jks
```

Copy the output — this is your `KEYSTORE_BASE64` secret.

---

## 4. Add GitHub Secrets

Go to: **Repo → Settings → Secrets and variables → Actions → New repository secret**

| Secret name                | Value                                      |
|----------------------------|--------------------------------------------|
| `KEYSTORE_BASE64`          | base64 output from step 3                  |
| `STORE_PASSWORD`           | your keystore store password               |
| `KEY_PASSWORD`             | your key password                          |
| `PLAYSTORE_SERVICE_ACCOUNT`| full JSON content of service account file  |

---

## 5. Google Play Service Account

1. Open [Google Play Console](https://play.google.com/console) → Setup → API access
2. Link to a Google Cloud project (or create one)
3. Create a Service Account → download the JSON key
4. In Play Console, grant the service account **Release Manager** permission
5. Paste the entire JSON content as the `PLAYSTORE_SERVICE_ACCOUNT` secret

---

## 6. Trigger a deploy

Push to `main` — GitHub Actions will:
- Build a signed AAB
- Upload to **Internal Testing** track automatically

To promote: Internal → Closed Testing → Production via Play Console.

---

## 7. Bump version for each release

In `pubspec.yaml`:
```yaml
version: 1.0.1+2   # name+versionCode
```

The `versionCode` (+2) must increase with every Play Store upload.
