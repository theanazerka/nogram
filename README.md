# nogram

Лёгкий клиент Telegram для **iOS 6+** (armv7), собирается через **Theos** в GitHub Actions.

Это не ремейк Telegram 4.9.1. От него взято сетевое ядро **MtProtoKit**, а слой API написан
заново на актуальной схеме (**layer 232**). Старый клиент 4.9.1 больше не может войти: серверы
отвечают `UPDATE_APP_TO_LOGIN` всем клиентам на старых слоях (у 4.9.1 был слой 86).

## Что работает

- Вход: номер → код (SMS / в приложении / звонок / почта), привязка почты, если Telegram её требует,
  двухэтапная аутентификация (SRP), регистрация нового аккаунта, автоматический переход на нужный DC.
- Список чатов: подгрузка страницами, закреплённые чаты, счётчики непрочитанных, обновления в реальном времени.
- Чат: история с подгрузкой, отправка текста, входящие в реальном времени, отметка о прочтении.
- Медиа пока показываются текстовыми плашками: `[Фото]`, `[Стикер 😀]`, `[Голосовое, 5 сек]` и т.п.
- Выход из аккаунта.

## Установка

1. Скачайте артефакт `nogram` со страницы последнего запуска в **Actions**: в нём `.deb` и `.ipa`.
2. Нужен джейлбрейк:
   - `.deb` — поставить через Cydia, iFile или `dpkg -i`, затем выполнить `uicache`;
   - `.ipa` — поставить через AppSync Unified + iFile/Filza (подпись фейковая, через ldid).
3. При первом запуске введите свой `api_id` и `api_hash` с <https://my.telegram.org> → *API development tools*.

Чтобы не вводить их на телефоне, добавьте в репозиторий секреты `TG_API_ID` и `TG_API_HASH`
(*Settings → Secrets and variables → Actions*): workflow вшьёт их при сборке.

## Сборка локально

```sh
export THEOS=~/theos            # Theos + iOS toolchain + iPhoneOS9.3.sdk в $THEOS/sdks (плюс liblaunch.tbd из 10.3, см. workflow)
make ipa FINALPACKAGE=1         # packages/nogram.ipa и packages/*.deb
make package TG_API_ID=123 TG_API_HASH=abc...   # с вшитыми ключами
```

Точный рецепт окружения — в `.github/workflows/build.yml`.

## Устройство

| Путь | Что там |
|---|---|
| `tl/telegram_api.tl` | схема API (из tdlib), номер слоя в `tl/LAYER` |
| `tools/tl2json.py` | компилирует схему в `Resources/scheme.json` (запускается при сборке) |
| `Sources/TL.[hm]` | TL-движок: сериализует и разбирает объекты по схеме во время работы. Объекты — это `NSDictionary` с ключом `@"_"`, флаги вычисляются сами |
| `Sources/TGNSerialization.m` | реализация `MTSerialization` для MtProtoKit |
| `Sources/TGNClient.m` | сеть: запросы, `*_MIGRATE_X`, апдейты, выход |
| `Sources/TGNSRP.m` | пароль 2FA (SRP) |
| `Sources/TGNStore.m` | кэш пользователей и чатов, разбор сообщений |
| `Sources/*Controller.m` | интерфейс на UIKit для iOS 6 |
| `vendor/MTProtoKit` | MtProtoKit (2019) с правками, см. ниже |
| `vendor/openssl` | OpenSSL 1.0.2, только armv7 |

### Правки в MtProtoKit

- `initConnection#c1cd5ea9` вместо `#785188b8`.
- Добавлен актуальный RSA-ключ серверов (fingerprint `d09d1d85de64fd85`).
- Создание ключа авторизации переведено на `p_q_inner_data_dc` и `RSA_PAD`.
  Шифрование RSA сделано через OpenSSL, а не через Security.framework: так не нужны права на keychain.
- `auth.exportedAuthorization.id` стал 64-битным.
- Совместимость с iOS 6 SDK: `endian.h`, `CFAutorelease`, пути импортов.

### Обновить слой

Положите свежий `telegram_api.tl` в `tl/`, обновите `tl/LAYER` и соберите проект заново.
Генерировать код не нужно. Если сервер поменял поля, которые читает интерфейс, их придётся поправить
в `TGNStore.m` и в контроллерах.

## Лицензия

GPL v2: код MtProtoKit и Telegram распространяется под GPL.
