import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';

String get kBaseUrl {
  if (Platform.isAndroid) {
    // Emulador usa 10.0.2.2; dispositivo fisico precisa do IP da maquina.
    return 'http://192.168.3.4:5000';
  }
  return 'http://127.0.0.1:5000';
}

/// Chave da Google Maps Platform (Places + Geocoding).
///
/// Lida do arquivo `.env` na raiz do projeto (nao commitado).
/// Copie `.env.example` para `.env` e preencha antes de rodar o app.
String get googleMapsApiKey => dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

@Deprecated('Use googleMapsApiKey')
String get apiKey => googleMapsApiKey;
