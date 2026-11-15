# Android 签名：Infisical Cloud 托管与构建期注入

> 讲清楚 release 签名材料从哪来、CI 和本机构建怎么取到**同一把 key**，以及出问题时的判据。
> 速查口径见 `AGENTS.md` §8.3；本文是完整操作手册与排错记录。
>
> 本文配置于 2026-11-15 实测：CI 的 `push-build` run `43688964758` 中
> 「从 Infisical 拉取签名密钥 (OIDC)」「写入 Android 签名材料」两步均 success；
> 本机 `infisical run` 写出的 keystore 与基准逐字节一致。

---

## 0. 为什么换掉 git-crypt

本仓是 `deretame/Breeze` 的 fork。仓库里 `android/key.properties` 与
`android/Breeze-key.keystore` 原本由 git-crypt 加密，但**对称密钥是带外分发的，fork 时不会带过来**
（实测这两个 blob 与上游逐字节相同，而本仓既没有 `.git/git-crypt/keys/`，
CI 的 `secrets.GIT_CRYPT_KEY` 也一直为空）。

后果是 `android/app/build.gradle.kts` 的 `releaseSigningAvailable` 判据恒为假，
release 构建回退到 `signingConfigs.getByName("debug")`——即 AGP 默认的
`~/.android/debug.keystore`。GitHub Actions 每次都是全新 runner，那把 debug key
**每次重新生成**，于是 v0.1.2 / v0.1.3 的签名证书各不相同，用户升级只能卸载重装
（丢书架、设置、下载）。

现在改为：签名材料由 Infisical Cloud 托管，仓库内不留任何副本，CI 与本机在构建前
**现场写出**这两个文件。两端取同一份 secret，签名不再漂移。

## 1. 总体链路

```
Infisical Cloud · project breeze-android-signing · env prod
        │
        ├── CI：Infisical/secrets-action@v1.0.9（GitHub OIDC，无静态密钥）
        │         ↓ 注入 4 个环境变量
        │   script/android/prepare_signing_from_infisical.py
        │         ↓ 写文件
        │   android/Breeze-key.keystore + android/key.properties
        │         ↓ releaseSigningAvailable = true
        │   gradle release 用发布 key 签名
        │
        └── 本机：infisical run --env=prod -- <同一脚本>
                  ↓ 同一份 secret、同一套写入逻辑
```

写入点只有一处（`prepare_signing_from_infisical.py`），CI 与本机共用，避免两套逻辑各自演化。
两个产物已加进 `.gitignore`，**任何情况下都不要提交**。

## 2. Infisical 侧（一次性配置）

组织 `HibernalGlow`，项目 `breeze-android-signing`：

| 项 | 值 |
|---|---|
| Project slug | `breeze-android-signing` |
| Project ID | `1e80d249-9750-43b0-9c0e-16a2b74ef65d` |
| 环境 | `Production`，slug **`prod`**（`dev` / `staging` / `prod` 是默认三个） |
| 机器身份 | `breeze-ci-oidc`，ID `eecb0a28-d6c3-4daf-b135-ec38f6f30bd1` |
| 项目角色 | **Viewer**（只读，最小权限；CI 只需要读 secret） |

**Production 环境里的 4 个 secret**（缺任一个，脚本直接 exit 1）：

| Key | 说明 |
|---|---|
| `ANDROID_KEYSTORE_B64` | keystore 文件的 base64，单行、无换行 |
| `ANDROID_KEY_ALIAS` | 密钥别名，当前 `breeze-release` |
| `ANDROID_KEY_PASSWORD` | key 口令 |
| `ANDROID_STORE_PASSWORD` | store 口令 |

UI 里可用 secrets 页的 **Paste Secrets** 批量导入，JSON 格式最稳
（base64 值里含 `=`，用 `.env` 格式容易被解析器切坏）。

**OIDC 认证方式**（机器身份 `breeze-ci-oidc` 只保留这一个，删掉创建时自动带的
Universal Auth，否则后者也能认证）：

| 字段 | 值 |
|---|---|
| OIDC Discovery URL / Issuer | `https://token.actions.githubusercontent.com` |
| Subject | `repo:HibernalGlow@154863885/rossi@1371436928:ref:refs/heads/main` |
| Audiences | `https://github.com/HibernalGlow` |

> **Subject 是本仓最容易踩的坑**：本仓创建于 2026-09-15，GitHub 用
> **immutable subject**（owner/repo 名后带数字 ID）。写成 legacy 的
> `repo:HibernalGlow/rossi:ref:refs/heads/main` 会一律 403。
> 核对命令：`gh api repos/HibernalGlow/rossi/actions/oidc/customization/sub --jq .sub_claim_prefix`。
>
> 当前绑定的是 `refs/heads/main`：**从 tag 或其它分支触发 `release.yml` 会认证失败**，
> 需要放宽 Subject 或另建身份。`push-build.yml` 的 PR 场景因拿不到 Variables 而整体跳过
> Android 腿，不受影响。

## 3. GitHub 侧（一次性配置）

仓库 `HibernalGlow/rossi` → Settings → Secrets and variables → Actions → **Variables**：

| Variable | 值 |
|---|---|
| `INFISICAL_IDENTITY_ID` | 上面的机器身份 ID（公开标识符，可入库） |
| `INFISICAL_PROJECT_SLUG` | `breeze-android-signing` |
| `INFISICAL_ENV_SLUG` | `prod`（可不填，workflow 默认 `prod`） |

**注意是 Variables 不是 Secrets**：OIDC 方案里 GitHub 不需要存任何长期凭据；
`vars.*` 还能直接用于 job 级 `if`（`secrets.*` 不行）。

两个 workflow 的改动：

- `release.yml` / `push-build.yml` 的解密 step 换成
  `Infisical/secrets-action@v1.0.9`（`method: oidc` + `domain: https://app.infisical.com`），
  随后跑 `python3 script/android/prepare_signing_from_infisical.py`。
- 两个 `build-android` job 都加 `permissions: contents: read, id-token: write`。
- `push-build.yml` 的 `check-android-secret` / `android-skip-notice` gate 改为检查
  `vars.INFISICAL_IDENTITY_ID`；为空时跳过 Android 并打印原因，其它平台照常构建。
- `release.yml` 的 Android 腿**没有 gate**：Variables 未配好就触发发布会直接红，
  而 `publish` needs 全部腿，所以不会产出半套 Release。这是刻意的 fail-fast。

`release.yml` 的签名判据 step 在脚本后会 `grep -q '^keyAlias='`，不满足即
`::error::` 退出，不让「其实没取到 secret」变成跑完 30 分钟才从包签名上看出来的秘密。

## 4. 本机首次配置

```bash
brew install infisical

# 1) 浏览器授权登录（会打印 https://app.infisical.com/login?callback_port=... 并监听 localhost）
infisical login
#    已登录态查：infisical login status
#    会话存在系统 keyring，profile 形如 <邮箱>--<组织>--<后缀>；token 有效期 10 天，过期重跑 login

# 2) 绑定项目（非交互，写 .infisical.yaml）
infisical init --project-id 1e80d249-9750-43b0-9c0e-16a2b74ef65d
```

`.infisical.yaml` 只有 `project-id`，**不含任何凭据，已入库**；团队 clone 后各自跑一次
`infisical login` 即可，不用重跑 `init`。

`infisical login` 是交互式命令：不带参数会先让选 region（US/EU/自托管），
非 TTY 环境会 EOF 失败。要跳过这一步可显式给
`--domain https://app.infisical.com/api`；`-i` 是纯命令行输入邮箱口令的模式，
**只适用于邮箱口令登录**（本组织用 GitHub 登录，走浏览器回调）。

## 5. 日常构建

```bash
cd /Users/glow/Base/Code/Freya/rossi

# 从 Infisical 现场写出 android/ 下两个签名文件
infisical run --env=prod -- python3 script/android/prepare_signing_from_infisical.py

# 然后照常构建 / 安装
dart ./script/build/build_apk.dart
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

`infisical run` 会把 `prod` 的 secret 注入子进程环境变量（实测 `Injecting 4 Infisical secrets`）。
脚本读这 4 个变量，写出：

```properties
keyAlias=breeze-release
keyPassword=<口令>
storeFile=../Breeze-key.keystore
storePassword=<口令>
```

> `storeFile` 必须是 `../Breeze-key.keystore`：`build.gradle.kts` 里
> `project.file(it)` 相对的是 **`android/app/`**，keystore 落在 `android/`。

验证本机与 CI 同源：写出的 keystore 与 `~/.config/rossi-signing/` 下的基准
`cmp` 一致；`keytool -list -keystore ...` 能看到 `breeze-release` 私钥条目。

## 6. 密钥轮换

1. 生成新 keystore（PKCS12，建议 RSA 2048 / 10000 天）：
   `keytool -genkeypair -alias <新别名> -keyalg RSA -keysize 2048 -validity 10000 -storetype PKCS12 -keystore Breeze-key.keystore ...`
2. 更新 Infisical `prod` 的 4 个 secret（别名改了要同步 `ANDROID_KEY_ALIAS`）。
3. 本机 `infisical run ...` 验证能写出、`keytool -list` 能读到新别名。
4. **换 key 等于换签名**：所有用户必须卸载重装一次，之后才重新稳定。
   发布说明里要写清楚，别让用户以为能直接覆盖升级。

日常不需要轮换；CI 用 OIDC 换短期 token，没有长期凭据可泄露或到期。

## 7. 故障排查

| 现象 | 判据 / 修法 |
|---|---|
| OIDC 403 | Subject 与 GitHub token 的 `sub` 不符。先查 `gh api repos/HibernalGlow/rossi/actions/oidc/customization/sub`；从 tag/其它分支触发也会 403 |
| action 报读不到 secret | 机器身份是否加进项目、角色是否至少 Viewer、`env-slug` 是否 `prod` |
| 脚本 `缺少 Infisical secret: ...` | 4 个 secret 是否都在 `prod`（不是 `dev` / `staging`） |
| CI 日志出现 `release 回退 debug 签名` | `android/key.properties` 没写出；看签名判据 step，别等 30 分钟后从包上看 |
| 本机 `infisical: You are not authenticated` | token 过期，重跑 `infisical login` |
| `infisical run` 注入 0 个 secret | `.infisical.yaml` 的 project-id 不对，或 `--env` 写错 |

## 8. 不入库的东西

- `android/key.properties`、`android/Breeze-key.keystore` —— 已在 `.gitignore`，构建期现场生成。
- `~/.config/rossi-signing/` —— 迁移期本机备份（含明文口令），Infisical 已是唯一密钥源，可删除。
- CLI 登录会话 —— 存在系统 keyring，不在仓库里。

`.gitattributes` 里原有的 git-crypt filter 规则已删除；仓库内不再有任何加密密文副本。
