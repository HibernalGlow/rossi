# UI 基线是现有 lib/page/comic_read，neoview 只提供视觉与交互语言

`lib/page/comic_read` 已经是一个带 bloc / controller / widgets 分层与 `ARCHITECTURE.md` 的 Flutter Reader；
而 neoview 是 20 万行的完整应用（前端 602 文件 / 96,384 行，后端 632 文件 / 103,216 行），
其中约 80% 的行数是与版式无关的业务实现（OPDS 客户端、归档 loader、5 个超分 service、AI 翻译、语音手势输入）。
我们决定：**Reader 骨骼用现有 `comic_read` 改造，只从 neoview 提取视觉语言与交互方式**；
neoview 的业务实现**不迁移**。

## Consequences

- 「迁移」一词在 Rossi 语境下只指视觉与交互，不再指代码移植（见 `CONTEXT.md`）。
- neoview 值得取的是它真正稀缺的那部分：`src/index.css` 里 366 个 CSS 变量、21 套主题、
  224 KB 的 `theme.json`、29 张截图。
- 避免了一次 20 万行的移植承诺，代价是版式需要手工重建，不能靠自动化提取。
