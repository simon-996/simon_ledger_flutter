# Simon Ledger 项目接手说明

本文档是继续维护 Simon Ledger 前请先阅读的入口。更完整的功能规则见 [产品功能说明](product-features.md)。

## 仓库

工作区包含三个独立仓库：

```text
simon_ledger_flutter   # Flutter 多端客户端
simon-ledger-api       # Spring Boot 后端 API
simon-ledger-admin     # React 后台管理 Web
```

远程仓库：

```text
git@github.com:simon-996/simon_ledger_flutter.git
git@github.com:simon-996/simon-ledger-api.git
git@github.com:simon-996/simon-ledger-admin.git
```

默认分支均为 `master`。

## 产品目标

Simon Ledger 是一个本地优先的多人账本工具。它要同时满足：

- 未登录用户可以在本机完整记账。
- 登录用户可以使用云端账本和多人协作。
- 弱网或离线时，写操作不阻塞，恢复网络后自动同步。
- 账本成员和账本参与人分离，避免把登录账号和分摊对象强行绑定。

## 前端客户端

入口：

```text
lib/main.dart
lib/app.dart
lib/features/home/presentation/screens/home_page.dart
```

核心目录：

```text
lib/core/database        # shared_preferences 本地数据层
lib/core/di              # Riverpod Provider
lib/core/repositories    # 本地/远端 Repository
lib/core/services        # 同步、导入、邀请、资料同步
lib/features             # 页面和业务组件
```

本地存储键：

```text
local_store.people.v1
local_store.ledgers.v1
local_store.transactions.v1
```

重要原则：

- 写操作优先保存本地。
- 登录态通过 Provider 决定使用本地仓库还是远端仓库。
- 本地 UUID 与远端 UUID 的映射只能通过 `SyncIdentityResolver` 处理。
- 平台差异集中在 `core/common`，业务层不要直接依赖 `dart:io` 或浏览器 API。

常用检查：

```bash
flutter analyze
flutter test
flutter build web
```

## 后端 API

入口：

```text
src/main/java/com/simon/ledger/controller
src/main/java/com/simon/ledger/service
sql
```

核心表：

```text
user_account
ledger
ledger_member
ledger_person
ledger_transaction
ledger_transaction_person
ledger_invite
idempotency_record
ledger_change_log
```

配置：

- `application-dev.yml` 本地使用，不提交。
- `application-prod.yml.example` 是生产配置模板。
- SQL 迁移文件放在 `sql/`，改表时必须新增 SQL，不只改实体。

常用检查：

```bash
mvn test
```

## 后台管理

后台项目使用 React + TypeScript + Vite，第一阶段做运维和客服排查：

- 用户搜索和账号状态查看。
- 账本搜索和账本详情排查。
- 邀请码查看和禁用。
- 同步/变更日志查看。
- 系统健康检查。
- 后台操作日志。

后台第一阶段应尽量只读，不直接修改流水金额或账本核心数据。

常用检查：

```bash
npm run lint
npm run build
```

## 文档索引

- [产品功能说明](product-features.md)
- [UI 方向](ui-direction.md)
- [账本邀请功能](ledger-invite-feature.md)
- [邀请链接部署](invite-link-deployment.md)

## 提交流程

1. 修改前分别检查相关仓库的 `git status --short`。
2. 不覆盖用户或他人已有未提交修改。
3. 文档和代码变更尽量按仓库分开提交。
4. 提交信息使用 Conventional Commits，例如：

```text
docs: update project documentation
feat: add admin user list
fix: preserve pending sync state
```

5. 提交前运行与改动范围匹配的检查。

## 当前维护重点

- 继续补齐离线同步组合场景测试。
- 完善冲突恢复体验。
- 后台管理接入独立 `/api/admin/*` 接口。
- 数据量增长后评估把本地 JSON 存储迁移到结构化本地数据库。
- 真实多用户环境继续验证邀请、权限、同步和统计口径。
