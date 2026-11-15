# Breeze

<p align="center">
  <a href="README.md">简体中文</a> · <a href="README.en.md">English</a>
</p>

> The Chinese README is the primary version; this English translation is provided for convenience.

## 💖 Acknowledgements & Sponsorship

Thanks to the following organizations for supporting the open-source community:

| [![Sentry Logo](asset/sentry-wordmark-dark-400x119.png)](https://sentry.io/) | This project is sponsored by **[Sentry](https://sentry.io/)** for comprehensive error monitoring. Its Sponsored Business plan helps us catch and fix crashes faster and improve the user experience. |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------- |

We also thank **[Aidoku](https://github.com/Aidoku/Aidoku)** — our iOS / macOS image upscaling implementation references its approach and model handling.

### ☕ Personal Sponsorship (Afdian)

☕ Thank you to everyone who sponsors this project. Your support is a major driving force behind its continued maintenance.

👉 **[Sponsor the author on Afdian: afdian.com/a/deretame](https://afdian.com/a/deretame)**

<img src="asset/aifadian.jpg" alt="Afdian sponsorship QR code" width="260" />

> - Sponsorship does not grant specific benefits, such as requesting a feature or priority bug fixes. All requests and feedback follow the normal process and are not treated differently based on sponsorship.
> - The project's direction, feature planning, and release cadence are decided by the author. Sponsorship does not come with decision-making power.
> - Sponsorship is a voluntary gift. Please give only what you can afford; donations are non-refundable.
> - Finally, the author will do their best to keep maintaining the project but cannot promise it will never slow down. If updates slow down someday, thank you for your understanding; your support will always keep the project going.

## Project Development Guide

Plugin development documentation: <https://breeze-project-org.github.io/plugin-dev-docs/>

Plugin list: <https://github.com/breeze-project-org/Breeze-plugin-list>

<details>
<summary>Currently included plugins (click to expand)</summary>

<!-- PLUGIN-LIST-START -->
包子漫画 Plus e-hentai 禁漫天堂 漫画柜 NoyAcg 如漫画 蛙漫3 包子漫画 哔咔漫画 拷贝漫画 hitomi JJ漫画 Komiic nhentai 绅士漫画 WEBTOON 再漫画 拷贝漫画 Copy4000 코사이트 MangaDex WeebCentral zero搬运网 禁漫天堂(mumushu0501-boop) Toomics
<!-- PLUGIN-LIST-END -->

</details>

> **Note:** Plugin support is still in beta and may change significantly. It is not recommended to build plugins on it for production; it is intended for learning purposes only.

### 1. Core Toolchain Installation

Before you start, make sure the base tools are installed and up to date:

- **Flutter SDK**: verify with `flutter doctor`.
- **Rust Toolchain**: install via `rustup` and add the required cross-compilation targets (e.g. `aarch64-linux-android`).
- **LLVM / Clang**: libraries such as `rustqjs` need to parse C headers, so LLVM is required (on Windows, `choco install llvm` or the official installer is recommended). Make sure the `LIBCLANG_PATH` environment variable is set.

### 2. Environment Variables

Depending on what you build, configure the following environment variables:

| Variable             | Purpose                                                     | Example path (reference)                          |
| :------------------- | :---------------------------------------------------------- | :------------------------------------------------ |
| **JAVA_HOME**        | Required for Android, Windows, and Linux builds             | `C:\Program Files\Android\Android Studio\jbr`     |
| **ANDROID_NDK_HOME** | Required for cross-compiling the Android Rust library       | `...\AppData\Local\Android\Sdk\ndk\29.0.14206865` |
| **LIBCLANG_PATH**    | Used by `bindgen` (Rust) to generate FFI bindings           | `C:\Program Files\LLVM\bin`                       |

> **Note**: Make sure the `PATH` variable includes the directories containing `javac` and `clang`.

### 3. Dependency Initialization

1. **Root project dependencies**:
   Run from the project root to download Flutter dependencies:
   ```bash
   flutter pub get
   ```

### 4. Platform-Specific Notes

- **Android**: Make sure `local.properties` points to the correct SDK path.
- **Windows/Linux**: Make sure Visual Studio (C++) or the appropriate GCC toolchain is installed so Rust can compile natively.

# 🚀 Installation

### 📱 Android / HarmonyOS

- Go to the [Releases page](https://github.com/breeze-project-org/Breeze/releases) and download `app-arm64-v8a-release.apk`.

  > **Note**: In mainland China, apps that have not gone through app-store review may fail to install. You can bypass the system installer with [GBox](https://gboxlab.com/i18n/zh-Hant/), [Chujingyi](https://www.chujingapp.com/), or [GSpace](https://gspaceteam.com/) (HarmonyOS users can download it from the app store).

### 🪟 Windows

- Download `windows-installer.exe` and run it to install.

### 🐧 Linux

Linux builds are available as both Flatpak and DEB packages. Choose the one that fits your distribution.

#### Option 1: Install the DEB (recommended for Debian/Ubuntu and derivatives)

Releases currently provide an `amd64` DEB package. Go to the [Releases page](https://github.com/breeze-project-org/Breeze/releases), download the file ending in `.deb`, and run:

> **Note**: The DEB package is not guaranteed to work on every Debian/Ubuntu derivative. If installation or startup fails, use the Flatpak build instead.

```shell
# If the downloaded Breeze DEB is the only package in the current directory, the wildcard works directly
sudo apt install ./breeze_*.deb
```

`apt` resolves the required system dependencies automatically. After installation, launch **Breeze** from the application menu or run:

```shell
breeze
```

To uninstall:

```shell
sudo apt remove breeze
```

#### Option 2: Install Flatpak (recommended; supports one-step install and updates)

The Flatpak build is distributed through a self-hosted repository to ensure compatibility across distributions. Add the repository once, then follow releases with `flatpak update`.

#### 1. Prepare the environment

If Flatpak is not configured on your system, follow the [Flatpak setup guide](https://flathub.org/setup) first.

> **Speed-up tip**: Users in mainland China may configure the [CERNET mirror](https://help.mirrors.cernet.edu.cn/flathub/) to improve download speed.

#### 2. One-step installation

```shell
curl -fsSL https://raw.githubusercontent.com/breeze-project-org/Breeze-flathub/main/install.sh | bash
```

Or add the repository manually and install:

```shell
flatpak remote-add --user --if-not-exists breeze \
  https://raw.githubusercontent.com/breeze-project-org/Breeze-flathub/main/breeze.flatpakrepo
flatpak install --user -y breeze io.github.windy.breeze
```

> If you previously added the old repository (`deretame.github.io/Breeze-flathub`), run
> `flatpak remote-modify --user --url=https://breeze-project-org.github.io/Breeze-flathub/repo/ breeze`
> once, or re-run the one-step script; otherwise `flatpak update` will fail because the old address is gone.

> The GNOME 50 Runtime is pulled automatically during installation; no manual step is needed.

#### 3. Update the app

```shell
flatpak update --user io.github.windy.breeze
```

#### 4. Run the app

After installation, find **Breeze** in the application menu or run:

```shell
flatpak run io.github.windy.breeze
```

> The old single-file `breeze-*.flatpak` is still available on the Releases page for manual installation, but it cannot be updated with `flatpak update`; the repository method above is recommended.

### 💻 macOS

macOS users are recommended to install and manage Breeze with Homebrew. You can also download the DMG and install manually.

#### Method 1: Install with Homebrew (recommended)

**1. Add the tap**
First, add this repository to your Homebrew taps:

```bash
brew tap deretame/breeze
```

**2. Install Breeze**
Homebrew downloads and installs the latest version into your Applications folder:

```bash
brew install --cask breeze
```

**3. Update Breeze**
When a new version is released, upgrade with:

```bash
brew upgrade breeze
```

**4. Uninstall completely**
To uninstall Breeze and also remove its database, caches, and configuration files, add the `--zap` flag (**note: this does not delete files you exported manually, but it clears the app's internal data**):

```bash
brew uninstall --zap breeze
```

#### Method 2: Download the DMG manually

1. Go to the [Releases page](https://github.com/breeze-project-org/Breeze/releases) and download the latest `Breeze-macOS.dmg`.
2. Open the `.dmg` and drag `Breeze.app` into the `Applications` folder.

> ⚠️ **First launch (macOS Gatekeeper)**
> This is a free, open-source project without an Apple Developer signature. If macOS reports **"The app is damaged"** or **"Cannot verify the developer"** on first launch, run the following command in Terminal to allow it:
>
> ```bash
> xattr -cr /Applications/Breeze.app
> ```
>
> _(Alternative: find Breeze in the Applications folder, Control-click the icon, and choose "Open" from the menu.)_

### 📱 iOS / iPadOS

Because iOS is closed, apps that are not on the App Store must be sideloaded and self-signed. Go to the [Releases page](https://github.com/breeze-project-org/Breeze/releases), download the unsigned `Breeze-iOS.ipa`, and install it with one of the following tools:

#### 🌟 Recommended: AltStore

AltStore is currently the most stable and beginner-friendly sideloading tool for iOS. It can automatically re-sign the app through a computer on the same LAN.

- **Download**: [AltStore official site](https://altstore.io/)
- **Guides**:
- [AltStore official FAQ (English)](https://faq.altstore.io/)
- [Zhihu: AltStore-based self-signing guide (Chinese)](https://zhuanlan.zhihu.com/p/143936759)
- [Bilibili: unlimited iOS IPA self-signing (Chinese)](https://b23.tv/UbuuJTZ)

#### 🔧 Other self-signing / no-signing options

If AltStore is not an option, consider:

- **Sideloadly**: a powerful desktop self-signing tool for Windows and macOS that works without jailbreak. ([Official site and guides](https://sideloadly.io/))
- **TrollStore**: if your iOS version falls within a supported vulnerability range, **strongly recommended** for permanent, non-expiring installation. ([TrollStore supported versions and installation guide](https://ios.cfw.guide/installing-trollstore/))

---

# **Open Source Disclaimer**

1. **Nature of the project**
   This is an open-source project developed and maintained independently by the author. It is provided "as is", and the developer makes no express or implied warranties regarding its completeness, stability, security, or fitness for any purpose.
2. **Limitation of liability**
   The developer is not liable for any direct, indirect, special, incidental, or consequential damages arising from the use, modification, or distribution of this project (including but not limited to direct use, secondary development, or integration into other projects). Such damages may include, without limitation, data loss, device damage, business interruption, loss of profits, or other economic losses.
3. **User responsibility**
   Users must evaluate the suitability of the project themselves and bear all risks. Users are responsible for ensuring their use complies with the laws, regulations, and ethical standards of their country or region. The developer is not responsible for any consequences of illegal or improper use.
4. **Third-party dependencies and resources**
   This project may depend on or reference third-party libraries, tools, services, or other resources. The developer is not responsible for the content, functionality, security, or legality of those third-party resources. Users must evaluate and bear the risks of using them.
5. **No warranty**
   The developer expressly disclaims all warranties, including but not limited to:

- merchantability;
- fitness for a particular purpose;
- non-infringement of third-party rights;
- error-free or uninterrupted operation.

6. **Modification and termination**
   The developer reserves the right to modify, suspend, or terminate the project at any time without prior notice and is not liable for any consequences.
7. **Contributor responsibility**
   If the project accepts external contributions, contributors act in their personal capacity and do not represent the developer's views. The developer is not responsible for contributors' actions or contributions.
8. **Legal compliance**
   Users must ensure their use complies with the laws and regulations of their country or region. The developer is not responsible for any consequences of non-compliance.

---

**Important**
Read and understand this disclaimer before using the project. If you disagree with any part of it, stop using the project immediately. Continuing to use the project means you have read, understood, and accepted the entire disclaimer.

---

**Developer**

- Developer: **[windy](https://github.com/deretame)**
- Repository: **[Breeze](https://github.com/breeze-project-org/Breeze)**
- Contact: **[Telegram](https://t.me/breeze_zh_cn)**

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://star-history.dera.page/svg?repos=breeze-project-org/Breeze&type=Date&theme=dark" />
    <source media="(prefers-color-scheme: light)" srcset="https://star-history.dera.page/svg?repos=breeze-project-org/Breeze&type=Date" />
    <img alt="Star History Chart" src="https://star-history.dera.page/svg?repos=breeze-project-org/Breeze&type=Date" />
  </picture>
</p>
