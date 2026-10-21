<a id="top"></a>

<p align="center">
  <img src="./assets/readme/hero.svg" width="100%"
       alt="Rossi — a cross-platform manga reader. Any third-party comic source, one shared bookshelf. Android, iOS, Windows, macOS and Linux, MPL-2.0.">
</p>

<p align="center">
  <a href="README.md"><b>中文</b></a> · <b>English</b>
</p>

## What Rossi is

A cross-platform manga reader written in **Flutter + Rust**.

It ships **no comic content at all** — where the comics come from is entirely up to **plugins**. One JS file describes how to list, how to search and how to restore the images; a QuickJS sandbox on the Rust side runs it. Install a plugin and that source becomes readable; install none and it stays a clean bookshelf for local CBZ files.

Two example source plugins ship built in: `rust/build.rs` downloads their bundles at compile time, so the first run already works.

### Capabilities

#### Sources and search

- Two example source plugins are built in; install your own `.js` / `.cjs` / `.br` plugins, with one-tap download, manual update and drag-to-reorder.
- **Aggregate search** asks several sources in one go. Tag syntax and excluded terms are supported, and searches are kept in history.
- Local CBZ / ZIP archives read directly, with no extraction step.

#### Reading

- Six modes: right to left (Japanese order, unmirrored), left to right, webtoon top to bottom, double page (seamless, optional leading blank), split landscape pages, auto read.
- **Every comic can override the settings** without touching the global set.
- E-ink tuning, volume-key page turns, left/right hand mode, ambient background colour, thumbnail scrubbing, persistent control bar.
- Desktop bindings are fully editable: keyboard, mouse, side buttons, wheel, gamepad, touch and region gestures, in separate global and reader contexts.

#### Bookshelf and downloads

- Favorites come in **local** and **cloud** kinds, and can be grouped.
- The follow tab lists exactly what updated but has not been read yet.
- A custom download queue: task manager, incremental retry of failures, read while downloading, export to ZIP / gallery / folder, and re-import.
- **WebDAV and S3 sync** (with a path-style toggle), plus manual upload and download.

#### Picture quality

- Picks a working super-resolution backend per platform, runs only below the resolution you set, and downloads weights on first use.

#### Manga translation (finished pages)

- Detect → recognize → erase → translate → re-typeset, producing a **redrawn page**, not subtitles laid over the original.
- Three translation engines to choose from: an API endpoint (cloud, or local Ollama / Foundry Local), local Hunyuan Hy-MT2, and Apple's system translation (on-device, offline, free).
- Glossary: one `source=target` per line, so proper nouns stay where you put them.
- Windows / Linux / macOS only for now — see [this section](#translation-details).

#### Elsewhere

- In-app update check and changelog; 20 preset theme colours (the default one is the mask red from the icon), light/dark following the system, and dynamic colour.
- Custom reading font; data backup import and export; cache management; GitHub / jsdelivr acceleration proxies; gesture and PIN app lock.
- System tray on macOS and Linux.

---

### Screens

<table>
  <tr>
    <th align="left" width="18%">Screen</th>
    <th align="left" width="48%">Desktop</th>
    <th align="left" width="34%">Mobile</th>
  </tr>
  <tr>
    <td>Shelf & layout</td>
    <td align="center" valign="top"><img src="./assets/readme/screenshots/shelf-desktop.webp" width="460" alt="Desktop shelf and gallery layout: a card grid with the gallery customisation panel open."></td>
    <td align="center" valign="top"><img src="./assets/readme/screenshots/shelf-mobile.webp" width="220" alt="Mobile shelf: continue-reading and currently-reading cards."></td>
  </tr>
  <tr>
    <td>Reader settings (light)</td>
    <td align="center" valign="top"><img src="./assets/readme/screenshots/settings-desktop-light.webp" width="460" alt="Desktop reader settings: reading mode, double-page reading, system theme and reading background."></td>
    <td align="center" valign="top"><img src="./assets/readme/screenshots/settings-mobile-light.webp" width="220" alt="Mobile reader settings: bottom navigation and vertically stacked options."></td>
  </tr>
  <tr>
    <td>Reader settings (dark)</td>
    <td align="center" valign="top"><img src="./assets/readme/screenshots/settings-desktop-dark.webp" width="460" alt="Desktop dark reader settings: the same reading mode and background options."></td>
    <td align="center" valign="top"><img src="./assets/readme/screenshots/settings-mobile-dark.webp" width="220" alt="Mobile dark reader settings: bottom navigation and vertically stacked options."></td>
  </tr>
  <tr>
    <td>Info panel</td>
    <td align="center" valign="top"><img src="./assets/readme/screenshots/info-desktop.webp" width="460" alt="Desktop info panel: book, image, storage and preload state."></td>
    <td align="center" valign="top"><img src="./assets/readme/screenshots/info-mobile.webp" width="220" alt="Narrow info panel: book, image and storage sections stacked vertically."></td>
  </tr>
</table>

These are in-app screens; titles and covers in the shots are sample data, with no third-party comic content.

---

### How it runs

<p align="center">
  <img src="./assets/readme/plugin-architecture.en.svg" width="100%"
       alt="Flow diagram: comic sources (built-in example plugins, plus custom JS plugins) feed into the Rust-side windcore sandbox, where QuickJS executes plugin code, reqwest performs requests, and decoding, de-obfuscation and archive handling happen; flutter_rust_bridge then hands everything to the Flutter UI layer — discovery, aggregate search, bookshelf and reader.">
</p>

The chain is `Dart → Flutter Rust Bridge → Rust → QuickJS`. Plugin code never runs inside Dart and never touches platform APIs: it can only describe which request to send, how to parse the answer and how to restore the image. Network and file capabilities are granted per feature by the host.

> ⚠️ **Plugins are still beta** — the API may change substantially, and today it suits learning better than shipping.
> But remember: inside the sandbox a plugin can still make network requests and read or write files. **Installing a plugin means trusting the code it contains.**

---

### Six ways to read

<p align="center">
  <img src="./assets/readme/reading-experience.en.svg" width="100%"
       alt="Six cells: right to left, left to right, webtoon top to bottom, seamless double page, split landscape pages, auto read. Each one can apply to the current comic only.">
</p>

Direction, page turning, double-page pairing and auto-scroll intervals each have more than one switch, so the model is one global set plus a per-comic override. Desktop adds a complete binding editor where keyboard, mouse, side buttons, wheel, gamepad, touch and region gestures can all be remapped.

---

<a id="translation-details"></a>

### Manga translation (finished pages)

<p align="center">
  <img src="./assets/readme/ocr-translate.en.svg" width="100%"
       alt="Six-step pipeline: 01 detect text boxes with PP-OCRv4 det, 02 recognize speech with manga-ocr, 03 erase the original text with LaMa, 04 translate with one of three engines, 05 re-typeset with LXGW WenKai, 06 finished page, toggled per page in the reader. Below, the three translation engines, and a note that this is Windows, Linux and macOS only.">
</p>

Unlike overlaying a translation, this path **erases the original text from the image** and re-typesets the translation into the shape of the bubble, so what you get is a page you can simply read. In the reader toolbar, tap Translate to switch the current page only.

Limits worth knowing:

- **Desktop only.** Android and iOS are excluded on purpose, not left on a backlog: this repo's ONNX Runtime registers no accelerator EP for the linux/android sections, and the recognizer is an fp32 ViT + BERT — making it usable on mobile needs an int8 re-export first. So the entry point is not drawn at all on mobile, rather than drawn and then erroring.
- Weights are not bundled: about **660 MB**, downloaded from the settings page on first use (PP-OCRv4 det + manga-ocr recognition + LaMa erase).
- Each engine trades something off: the API endpoint needs network or a local service and supports the glossary; Hunyuan Hy-MT2 needs you to start `llama-server` yourself; Apple system translation is on-device, offline and free, but **exposes no glossary API**, so on that route proper nouns get the generic translation.
- If the endpoint is unavailable at that moment the page **degrades**: it is erased and re-typeset with the source text instead of stalling the whole chapter.
- Finished pages are cached, and there is a one-tap clear after changing model or font (your originals are never touched).
- All six stages write one log line per page, so when something goes wrong the settings page shows you which stage.

---

### Download and install

Get the installer for your platform from [Rossi Releases](https://github.com/HibernalGlow/rossi/releases).

---

### Building from source

> For anyone changing the code. If you only want to read, you can stop above.

#### 1. Core toolchain

- **Flutter SDK**: must pass `flutter doctor`.
- **Rust toolchain**: install via `rustup` and add the cross-compilation targets you need (for example `aarch64-linux-android`).
- **LLVM / Clang**: libraries such as `rustqjs` parse C headers, so LLVM is required (on Windows, `choco install llvm` or the upstream installer).

#### 2. Dependencies and code generation

```bash
# root project Flutter dependencies
flutter pub get

# required again after touching auto_route / freezed / json_serializable / objectbox / FRB
dart ./script/code_generate.dart
```

#### 3. Platform notes

- **Android**: point `local.properties` at the right SDK path.
- **Windows / Linux**: install Visual Studio (C++) or an equivalent GCC toolchain so the Rust parts can compile locally.
- **Repository layout, build scripts and conventions**: see [`AGENTS.md`](./AGENTS.md) and [`docs/`](./docs/).

---

> A short English summary of the project disclaimer, for convenience. **The authoritative text is the Chinese version in [README.md](README.md#开源项目免责声明).**
> The app is provided as-is with no warranty of any kind; the developer is not liable for any damage from using, modifying or redistributing it. You are responsible for checking that your use is lawful where you are, and for the content any third-party plugin fetches — the app itself ships none. External contributions represent their authors only. Keep working on a plugin's source before installing it: it runs code you did not write.

---

---

## Credits

| [![Sentry Logo](asset/sentry-wordmark-dark-400x119.png)](https://sentry.io/) | This project is supported by **[Sentry](https://sentry.io/)**; its Sponsored Business plan helps us catch and fix crashes faster and keep the app stable. |
| :--- | :--- |

Thanks also to **[Aidoku](https://github.com/Aidoku/Aidoku)** — the iOS / macOS image upscaling work here follows its approach and model handling.

## License

This project is licensed under the **Mozilla Public License 2.0** — see [LICENSE](./LICENSE).

The app ships no comic content; everything is fetched by third-party plugins from their own sources. Follow the laws of your region when developing and using it.

---

**Repository**

- [HibernalGlow/rossi](https://github.com/HibernalGlow/rossi)
