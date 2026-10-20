# Bro Rogue

بازی دوبعدی پیکسل‌آرت، اکشن run-and-gun با چرخه‌ی روگلایک، با انجین Godot 4.

## ساختار پروژه

| مسیر | محتوا |
|---|---|
| `art/palettes/master.yaml` | پالت اصلی. همه‌ی رنگ‌های بازی از اینجا می‌آیند |
| `art/palettes/sets/*.yaml` | پالت هر شخصیت یا شیء (نماد → نام رنگ) |
| `art/sprites/*.yaml` | مشخصات هر اسپرایت: قطعه‌ها (پیکسل‌به‌پیکسل) و انیمیشن‌ها |
| `art/storyboards/*.yaml` | استوری‌بوردها |
| `design/controls.yaml` | همه‌ی دکمه‌ها و کاری که هر کدام انجام می‌دهد |
| `design/entities/*.yaml` | کاتالوگ هر شخصیت یا شیء: اعداد گیم‌پلی، انیمیشن‌ها، صداها، فایل‌ها |
| `audio/catalog.yaml` | کاتالوگ همه‌ی صداها و موسیقی‌ها (پرامپت ElevenLabs) |
| `tools/` | ابزارهای ساخت |
| `docs/catalog.html` | کاتالوگ بصری همه‌ی دارایی‌ها (ساخته‌شده‌ی خودکار) |
| `game/` | پروژه‌ی Godot. این پوشه را در Godot باز کن |
| `art.lock.json`, `audio.lock.json` | قفل دارایی‌های تأییدشده |

## قانون ثبات (عقب‌وجلو نشدن)

- هر اسپرایت از روی مشخصاتش ساخته می‌شود و هر بار دقیقاً همان خروجی را می‌دهد.
- دارایی تأییدشده قفل است. اگر تغییری روی آن اثر بگذارد، ساخت متوقف می‌شود و تصویر قبل و بعد در `docs/diff/` ذخیره می‌شود. فقط با `--accept NAME` تغییر پذیرفته می‌شود.
- صدایی که یک بار ساخته شد، دیگر دوباره ساخته نمی‌شود، مگر با `--regen NAME`.

## دستورها

```bash
py tools/build.py
```
```bash
py tools/build.py --accept bro
```
```bash
py tools/build.py --check
```
```bash
py tools/audio_build.py
```
```bash
py tools/audio_build.py --music
```

کلید ElevenLabs از متغیر محیطی `ELEVENLABS_API_KEY` خوانده می‌شود.

## کنترل‌ها

فهرست کامل و همیشه‌به‌روز در بخش Controls فایل `docs/catalog.html` است (از `design/controls.yaml` ساخته می‌شود).

## تغییر اعداد بازی

سرعت، پرش، نرخ شلیک، جان بلوک و... در `design/entities/*.yaml` هستند. عدد را آنجا عوض کن و `py tools/build.py` را اجرا کن. بازی و کاتالوگ هر دو به‌روز می‌شوند. فایل `game/scripts/generated/game_data.gd` را دستی ویرایش نکن.
