---
name: breeze-upstream-sync
description: 同步 deretame/Breeze 到 Rossi 的真实 Git merge 工作流；用于处理长期未同步、冲突取舍、上游优先和同步记录。
---

# Breeze 上游同步

用于把 `upstream/main` 的 Breeze 更新合并到 Rossi，同时保留 Rossi 的独有扩展和工作区里的在途改动。目标是让同一功能只有一个正本：上游已经可用的实现以上游为准，Rossi 额外行为挂在上游接口或明确登记的适配层上。

## 工作区与历史

1. 先执行 `git status --short --branch`、`git remote -v` 和 `git log`，确认当前分支、共同基线及未提交文件。使用普通 `git`，不要调用 GitButler 的 `but` 命令。
2. 工作区有改动时，先建立可回退引用：`git branch backup/pre-upstream-sync-YYYYMMDD HEAD`，再用 `git stash push --include-untracked` 保存未提交改动。不要清理、覆盖或删除其他并行工作；忽略文件（签名材料、插件源码等）不应被加入 stash。
3. `git fetch upstream --prune` 后记录 `git merge-base HEAD upstream/main`、双方提交数及上游最新 tag。同步必须保留真实 merge commit 和上游父节点，不用 squash、rebase 或手工复制提交。
4. 以 `git merge --no-commit upstream/main` 建立合并现场。逐个检查三方差异和生产消费者；自动合并成功的重叠模块同样需要检查语法及 Rossi 扩展入口。

## 冲突取舍

- 上游与 Rossi 达成同一功能目标且在本仓可用：采用上游实现、状态模型和测试，删除或收拢本地平行实现。
- Rossi 的行为比上游多：保留上游核心，把额外行为放到薄适配或扩展点，并在 `docs/upstream-sync.md` 记录来源、差异和回归测试。
- 上游依赖本仓没有的能力、在目标平台无法编译或没有生产消费者：保留 Rossi 实现，写明具体理由，避免下轮同步误判。
- Rossi 的品牌、包名、安装标识、数据迁移、GPU/OCR 等独有能力优先保留；上游迁移基础设施时，把这些能力接到上游新入口，不恢复已删除的重复实现。
- 生成文件（slang、build_runner、FRB、auto_route、ObjectBox）不能靠手工拼接长期维护。先合并输入和源文件，再使用项目唯一代码生成入口重建。
- ObjectBox 的 `objectbox-model.json` 是**已发布数据库的契约**：合并后逐项比对合并前的实体 / 属性 / 索引 UID，
  旧表必须原样保留，新增实体和索引只能用未占用 ID。自动合并常把上游新实体和本地新实体分到同一个 ID，
  只有真实建库（跑一次带 `TestObjectBoxHelper` 的用例）才暴露，schema 文件里看不出来。
- 上游改了共享文案或默认值时（例如 `reader.settings` 由「阅读设置」改为「阅读」、DoH 默认改为关闭），
  按上游行为更新既有用例的断言，不要为迁就用例把产品默认改回去。
- 国际化输入按三方键和值核对，保留 Rossi 翻译并接入上游新增条目；比较输入与生成物，避免自动合并或过期生成物静默丢键。用户限定生成范围时按授权执行。

## 完成顺序

1. 处理所有冲突，确认 `git diff --name-only --diff-filter=U` 为空；对 modify/delete 冲突按上游迁移方向决定，记录 Rossi 适配是否需要另落点。
2. 在合并树上跑一遍唯一代码生成入口 `dart ./script/codegen/code_generate.dart`，再跑应用级测试。冲突标记为零、定向分析通过都不够：`flutter analyze` 能放过被拼坏的局部函数，只有能加载 `main.dart` 的 `flutter test`（例如插件初始化协调器用例）才会把它当编译错误抛出来。
3. 全仓 `flutter analyze` 的 error 必须清零（`poc/`、`tool/` 等未改动的独立工具若有既有 error，单独列出并说明不属于本轮）；`flutter test` 全量跑完并记录通过/失败数。分批跑的子集不能算全量。
4. 只把纯上游合并结果提交为一个真实 merge commit，提交前后各执行 `git status`。合并提交不要夹带 stash 中仍在开发的功能。
5. `git stash pop` 恢复在途改动；以合并后的上游代码为基准重新解决身份、品牌、平台工程和生成文件冲突。恢复后的新功能继续保持未提交，除非用户明确要求提交。
6. 更新 `docs/upstream-sync.md`：写入日期、旧基准、新基准、采用的上游功能、保留的 Rossi 扩展、未采用及理由、生成命令和验证结果。若上游改了安装器、包名或发布链，同步更新 `AGENTS.md` 中的入口说明。

## 验收门禁

- `git merge-base HEAD upstream/main` 已推进到本轮上游父节点，历史中存在以 `upstream/main` 为第二父节点的真实 merge commit。
- `git diff --name-only --diff-filter=U` 无输出，源码和生成物中无 `<<<<<<<`、`=======`、`>>>>>>>`。
- 重叠功能只保留一套实现；Rossi 独有功能仍由现有测试或新增定向测试覆盖。
- 至少完成一次真实平台构建（本机可做 macOS Release；其它平台按可用环境），并在构建后执行
  `./script/refresh_release_dylib.sh` 用 hook 产物跑依赖原生库的用例，确认 Swift/FRB 侧没有因合并丢接线。
- 同步记录与实际合并树一致，不能只写提交摘要而跳过行为核对。
- 分别说明合并树、暂存区和工作区的验证结果；工作区修好不代表已提交版本通过，失败或未执行的检查不能记为通过。
- 工作区里的用户在途改动仍存在，签名材料、插件源码等本机忽略内容未被加入版本控制。

参考：

- `docs/adr/0023-upstream-implementation-first-for-overlap.md`：重叠功能的判定与例外。
- `docs/upstream-sync.md`：每轮同步的基准、取舍和验证记录。
- `AGENTS.md` §12–§13：真实 merge、普通 Git 和上游优先约束。
