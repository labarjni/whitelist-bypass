# Whitelist Bypass iOS App

Аналог Android-приложения для подключения обхода whitelist-цензуры через видеозвонки (VK Call, Yandex Telemost).

## Структура проекта

```
ios-app/WhitelistBypass/
├── WhitelistBypass.xcodeproj/    # Xcode проект
└── WhitelistBypass/
    ├── AppDelegate.swift         # Точка входа приложения
    ├── Info.plist                # Конфигурация приложения
    ├── Controllers/
    │   ├── MainViewController.swift  # Главный экран
    │   └── WebViewManager.swift      # Управление WebView
    ├── Tunnel/
    │   ├── Models.swift          # Модели данных
    │   ├── VpnManager.swift      # Управление VPN
    │   └── RelayController.swift # Контроллер релея
    ├── Util/
    │   └── LogWriter.swift       # Логирование
    └── Assets/
        ├── dc-joiner-vk.js           # DC хук для VK
        ├── dc-joiner-telemost.js     # DC хук для Telemost
        ├── video-vk.js               # Pion Video хук для VK
        ├── video-telemost.js         # Pion Video хук для Telemost
        ├── autoclick-vk.js           # Авто-кликер VK
        ├── autoclick-telemost.js     # Авто-кликер Telemost
        └── mute-audio-context.js     # Mute audio
```

## Требования

- macOS 13+ с Xcode 15+
- Go 1.21+ с gomobile для сборки Mobile.framework
- iOS 15.0+ target

## Сборка

### 1. Сборка Go Mobile framework

```bash
cd /workspace/relay/mobile
gomobile init
gomobile bind -target ios -o /workspace/ios-app/Frameworks/Mobile.framework ./mobile
```

### 2. Открыть проект в Xcode

```bash
open /workspace/ios-app/WhitelistBypass/WhitelistBypass.xcodeproj
```

### 3. Добавить Mobile.framework

В Xcode:
1. Перетащить `Mobile.framework` в проект
2. В настройках target → General → Frameworks добавить Mobile.framework
3. Убедиться что "Embed & Sign" выбрано

### 4. Собрать приложение

В Xcode выбрать устройство и нажать Build (Cmd+B)

## Режимы работы

Приложение поддерживает те же режимы что и Android-версия:

### DC Mode (DataChannel)
- Браузерный режим через JavaScript хуки
- Создает DataChannel параллельно каналу видеозвонка
- Трафик передается через WebSocket на локальный SOCKS5 прокси

### Pion Video Mode
- Go-based WebRTC через библиотеку Pion
- Данные кодируются внутри VP8 видео фреймов
- Прямое подключение к TURN/SFU серверам платформы

## Поддерживаемые платформы

- **VK Call** - vk.com
- **Yandex Telemost** - tm.me / t.me

## Использование

1. Запустить приложение на iPhone
2. Выбрать режим туннеля (DC или Pion Video)
3. Вставить ссылку на видеозвонок от Creator (desktop)
4. Нажать GO
5. Приложение подключится к звонку и запустит VPN
6. Весь трафик устройства пойдет через туннель

## Отличия от Android-версии

| Компонент | Android | iOS |
|-----------|---------|-----|
| VPN | VpnService + tun2socks | NetworkExtension (требует separate extension target) |
| WebView | Android WebView | WKWebView |
| Go Integration | .aar library | Mobile.framework (gomobile) |
| UI | Kotlin/XML | Swift/UIKit |

## Примечания

### VPN Extension

Для полноценной работы VPN на iOS требуется создать отдельный target типа "Packet Tunnel Provider":

1. В Xcode: File → New → Target → Packet Tunnel Provider
2. Назвать "TunnelExtension"
3. Bundle ID: com.whitelist.bypass.tunnel-extension
4. Реализовать логику подключения к SOCKS5 прокси

### Entitlements

Приложению требуются следующие entitlements:
- `com.apple.developer.networking.vpn-api` - для VPN API
- `com.apple.security.application-groups` - для обмена данными с extension

### App Store

Приложение может не пройти модерацию App Store из-за использования VPN API и обхода цензуры. Рекомендуется использовать для личного использования через TestFlight или direct installation.

## Лицензия

MIT License
