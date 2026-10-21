# 11 — Plataformas e build

Estado atual da configuração nativa. Praticamente tudo aqui ainda é o
gerado por `flutter create` — o que é normal num protótipo e é
exatamente o que precisa mudar antes de publicar.

O plano de correção está no [doc 12](12-producao-remover-hardcode.md).

---

## Versionamento

`front_end/pubspec.yaml`:

```yaml
version: 0.1.0+1
environment:
  sdk: ^3.10.7
```

`0.1.0` vira `versionName` no Android e `CFBundleShortVersionString` no
iOS; o `+1` vira `versionCode` / `CFBundleVersion`. É o que a tela
"Sobre" exibe via `package_info_plus`.

---

## Android

### `AndroidManifest.xml` (main)

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>

<application
    android:label="front_end"
    android:name="${applicationName}"
    android:icon="@mipmap/ic_launcher">
```

#### ⚠ Falta a permissão de INTERNET

`android.permission.INTERNET` aparece **apenas** em
`android/app/src/debug/AndroidManifest.xml` e
`android/app/src/profile/AndroidManifest.xml` — os manifestos que o
`flutter create` gera para o tooling.

O manifesto `main`, que é o único que vale em release, **não declara**.
O merge de manifestos não a injeta em release.

**Consequência**: um build `--release` sobe, abre, mostra o mapa em
branco e falha em toda chamada de rede. É provavelmente o primeiro
problema que aparecerá ao gerar o APK de distribuição.

#### ⚠ Cleartext HTTP — bloqueado hoje, em todos os build types

Verificado no manifesto mesclado que o Gradle produziu
(`build/app/intermediates/packaged_manifests/debug/.../AndroidManifest.xml`):

```xml
<uses-sdk android:minSdkVersion="24" android:targetSdkVersion="36" />
```

e **nenhuma** ocorrência de `android:usesCleartextTraffic` ou de
`android:networkSecurityConfig` — nem no `main`, nem no `debug`, nem
vinda de alguma biblioteca.

Desde o Android 9 (API 28), tráfego HTTP em texto claro é **bloqueado por
padrão** para apps com `targetSdk >= 28`. Com `targetSdk = 36` e sem
nenhuma configuração que abra exceção, o sistema recusa as conexões para
`http://192.168.3.4:5000` com:

```
CLEARTEXT communication to 192.168.3.4 not permitted by network security policy
```

> **Isso vale também em debug.** Ao contrário do que às vezes se supõe, o
> Flutter **não** injeta uma configuração de rede permissiva nos builds
> de desenvolvimento — o manifesto de debug acrescenta apenas a permissão
> de `INTERNET`.

**Consequência prática**: em qualquer aparelho com Android 9 ou superior,
as chamadas ao Flask falham. Se o app vem funcionando, é porque o teste
está sendo feito num aparelho ou emulador com Android 8 ou anterior.

Duas correções, para dois problemas distintos:

- **Produção** → HTTPS. Resolve sem exceção nenhuma (doc 12, Fase 2.4).
- **Desenvolvimento contra um Flask local** → um
  `networkSecurityConfig` **apenas no build type de debug**, que nunca
  chega ao release. Ver [doc 12, Fase 2.5](12-producao-remover-hardcode.md).

#### `label`, ícone e splash nativa

`android:label="front_end"` — é o nome que aparece sob o ícone na
gaveta de apps. O ícone é o `ic_launcher` padrão do Flutter.

`MainActivity.kt` é o padrão, sem customização, no pacote
`com.example.front_end`:

```kotlin
package com.example.front_end
import io.flutter.embedding.android.FlutterActivity
class MainActivity : FlutterActivity()
```

**⚠ A splash nativa é branca.** `res/drawable/launch_background.xml`
ainda é o template:

```xml
<layer-list>
    <item android:drawable="@android:color/white" />
    <!-- You can insert your own image assets here -->
</layer-list>
```

Ela é o que o Android desenha entre o toque no ícone e o primeiro frame
do Flutter. Como a `SplashScreen` do app tem fundo **bege**
(`AppColors.bege`), o usuário vê **um flash branco antes do bege** em
toda abertura. Trocar o `windowBackground` para `#F5F0E8` elimina a
emenda; o `flutter_native_splash` resolve os dois lados de uma vez.

### `build.gradle.kts`

```kotlin
android {
    namespace = "com.example.front_end"
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17 ... }

    defaultConfig {
        // TODO: Specify your own unique Application ID
        applicationId = "com.example.front_end"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}
```

Três problemas, todos marcados como `TODO` pelo próprio template:

1. **`applicationId = "com.example.front_end"`.** O Google Play recusa
   qualquer `com.example.*`. E o `applicationId` é **imutável** depois da
   primeira publicação — precisa estar certo antes do primeiro upload.
2. **Release assinado com a chave de debug.** Nunca publicável, e a chave
   de debug é comum a todas as máquinas de desenvolvimento.
3. **`minSdk` / `targetSdk` herdados do Flutter**, sem escolha
   explícita. O manifesto mesclado mostra que hoje isso resolve para
   `minSdk 24` / `targetSdk 36`. Valores razoáveis, mas convém fixá-los
   explicitamente: eles mudam sozinhos a cada atualização do SDK do
   Flutter, e `targetSdk` alto é justamente o que ativa o bloqueio de
   cleartext descrito acima.

### ⚠ Inconsistência de identificador

| Lugar | Valor |
|-------|-------|
| `build.gradle.kts` → `applicationId` | `com.example.front_end` |
| `MapWidget` / `GenotypePlot` → `userAgentPackageName` | `com.LuisFelipe.PlantioAPP.dev` |
| `BaseMapService` → header `User-Agent` | `PlantioAPP/1.0 (base-map)` |

Três identidades diferentes. O `userAgentPackageName` é o que o CARTO vê
em cada requisição de tile; o sufixo `.dev` sugere que ficou de uma
configuração de desenvolvimento.

---

## iOS

### `Info.plist`

```xml
<key>CFBundleDisplayName</key> <string>Front End</string>
<key>CFBundleName</key>        <string>front_end</string>
```

#### ⚠ Falta a descrição de uso de localização

**Não há** `NSLocationWhenInUseUsageDescription`.

A partir do iOS 10, pedir localização sem essa chave faz o app **encerrar
imediatamente**. O `geolocator` chama a API nativa no toque do FAB de
GPS — ou seja, o app crashaaria no primeiro toque.

É obrigatória tanto para o funcionamento quanto para a revisão da App
Store, e o texto precisa explicar o uso em português.

#### ⚠ ATS e HTTP

Não há chave `NSAppTransportSecurity`. O App Transport Security bloqueia
HTTP em texto claro por padrão desde o iOS 9 — o backend atual não seria
alcançável no iOS **nem em debug**.

Como no Android, a solução é HTTPS, não uma exceção de ATS (que a Apple
questiona na revisão).

#### Bundle identifier e deployment target

O `CFBundleIdentifier` vem de `$(PRODUCT_BUNDLE_IDENTIFIER)`. Conferido
no `ios/Runner.xcodeproj/project.pbxproj`:

```
PRODUCT_BUNDLE_IDENTIFIER = com.example.frontEnd;
PRODUCT_BUNDLE_IDENTIFIER = com.example.frontEnd.RunnerTests;
IPHONEOS_DEPLOYMENT_TARGET = 13.0;
```

Ou seja: **ainda o `com.example` do template**, como no Android. A App
Store recusa.

#### Orientações

`UISupportedInterfaceOrientations` permite retrato e ambas as paisagens.
O app não foi projetado para paisagem; vale restringir a retrato.

---

## Outras plataformas

As pastas `web/`, `windows/`, `linux/` e `macos/` existem porque o
`flutter create` as gera, mas **nada foi adaptado** — `web/index.html`
ainda tem `<title>front_end</title>` e a descrição `"A new Flutter
project."`, e `web/manifest.json` tem `name` e `short_name` iguais a
`front_end`. Além disso:

- `api_config.dart` só ramifica entre `Platform.isAndroid` e o resto, e
  `dart:io` nem existe no web;
- `sqlite3_flutter_libs` exige configuração específica no web (WASM);
- o `geolocator` tem comportamento diferente em cada plataforma.

Na prática o alvo é Android (com iOS pendente das correções acima).

---

## Build e geração de código

### Drift

Ao mexer em `region_database.dart`:

```bash
cd front_end
dart run build_runner build --delete-conflicting-outputs
```

Isso regenera `region_database.g.dart` (1.219 linhas). O arquivo é
versionado — o que é a prática recomendada — e nunca deve ser editado à
mão.

### Análise estática

```bash
flutter analyze
```

`analysis_options.yaml` inclui `package:flutter_lints/flutter.yaml` sem
customização.

> **Não foi possível executar o analisador** ao produzir esta
> documentação: a máquina que tem a pasta montada não tem o Flutter
> instalado. O que segue é contagem estática sobre o código, não saída do
> `flutter analyze`.

O `.dart_tool/package_config.json` registra que o último build usou
**pub 3.12.0** (Dart SDK 3.12). Nessa versão, `Color.withOpacity` está
deprecado em favor de `withValues(alpha:)`. Contagem no código:

| API | Ocorrências |
|-----|-------------|
| `withOpacity` | **42**, em 9 arquivos |
| `Color.value` | 1 |
| `MaterialStateProperty`, `onPopInvoked`, `textScaleFactor` | 0 |

Concentração de `withOpacity`: `onboarding_overlay.dart` (11),
`genotype_detail_card.dart` (10), `history_screen.dart` (7),
`about_screen.dart` (6), e mais 2 ou menos nos outros cinco.

Some-se a isso os avisos por referência aos símbolos `@Deprecated` do
próprio projeto — poucos, porque quase nenhum código ativo os referencia.

Para ter o número real: `flutter analyze` na sua máquina.

### Backend

```bash
pip install -r requirements.txt
cd App
python app.py                  # waitress em 0.0.0.0:5000
```

O GeoPandas puxa GDAL, PROJ e GEOS. Em Windows costuma ser mais simples
via conda ou wheels pré-compilados.

### R

```r
renv::restore()
source("r_scripts/tester.R")
```

---

## Checklist rápido do estado atual

| Item | Estado |
|------|--------|
| Permissão INTERNET em release (Android) | ❌ ausente |
| Cleartext HTTP (Android) | ❌ bloqueado em **todos** os build types |
| Descrição de localização (iOS) | ❌ ausente — crash |
| Exceção de ATS / HTTPS (iOS) | ❌ ausente |
| `applicationId` próprio | ❌ `com.example.front_end` |
| Chave de assinatura de release | ❌ chave de debug |
| Nome do app e ícone | ❌ `front_end`, ícone padrão |
| Bundle id iOS | ❌ `com.example.frontEnd` |
| Splash nativa | ❌ branca, emenda com a splash bege do app |
| Permissões de localização (Android) | ✅ declaradas |
| Java 17 / Kotlin JVM target | ✅ configurado |
| Geração Drift versionada | ✅ |
