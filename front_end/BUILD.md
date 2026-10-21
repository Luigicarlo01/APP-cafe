# Build

## Setup inicial

1. Copie o arquivo de exemplo:
   ```
   cp .env.example .env
   ```
2. Abra `.env` e cole sua chave da Google Maps Platform em `GOOGLE_MAPS_API_KEY`.
3. `flutter pub get`

O `.env` esta no `.gitignore` — nunca vai pro repo.

## Rodar

```
flutter run
flutter build apk
flutter build appbundle
flutter build ios
```

Sem flags, sem variaveis de ambiente. O app le o `.env` no boot via `flutter_dotenv`.

## Restringir a chave no Google Cloud

O `.env` mantem a chave fora do source, mas ela vai bundlada como asset no APK/IPA
e quem descompilar consegue extrair. A protecao real e restringir no Google Cloud
Console (APIs & Services > Credentials):

- Android: package name + SHA-1 do keystore.
- iOS: bundle identifier.

E ativar apenas as APIs usadas (Places API, Geocoding API).
