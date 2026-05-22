# Backend Integration TODO

本文档用于跟踪 Simon Ledger 接入后端的实施进度。每完成一项，就把 `[ ]` 改成 `[x]`。

## 执行约束

- [ ] 不负责本地运行环境搭建，环境由项目维护者自行准备。
- [ ] 后端只提交项目代码、配置文件和数据库 SQL。
- [ ] 数据库初始化以 SQL 文件交付，不强依赖本地 Docker Compose。
- [ ] 配置只保留连接项和可替换占位值，不提交真实密码、Token、生产地址。
- [ ] 第一阶段只做稳定闭环，不做复杂离线同步、实时协作和冲突合并。
- [x] 写后端代码时参考 `/Users/simon/workplace/projects/comp-stat/comp-stat-api` 的项目标准。
- [x] Git 提交信息参考 `comp-stat-api` 的提交规范，使用 `feat: ...`、`fix: ...` 等 Conventional Commits 风格。
- [x] 后端优先参考 `comp-stat-api` 的 Maven、Spring Boot、Java 21、分层目录和配置文件组织方式。

## 1. 后端项目骨架

- [x] 新增后端项目目录 `/Users/simon/workplace/projects/simon_ledger/simon-ledger-api`，与 `simon_ledger_flutter` 同级。
- [x] 使用 Java 21。
- [x] 使用 Spring Boot 3.x。
- [x] 构建工具优先使用 Maven，参考 `comp-stat-api/pom.xml`。
- [x] 后端项目名称确定为 `simon-ledger-api`。
- [x] 后端包名确定为 `com.simon.ledger`。
- [x] 后端 Git 仓库初始化为 `master` 分支。
- [x] 后端 Git 远程仓库设置为 `git@github.com:simon-996/simon-ledger-api.git`。
- [x] 后端初始骨架已提交并推送到 `origin/master`。
- [x] 添加基础目录结构：`common`、`module`、`infrastructure`。
- [x] 添加统一响应对象。
- [x] 添加统一异常处理。
- [x] 添加基础错误码。
- [x] 添加 OpenAPI 配置。

## 2. 配置连接

- [x] 添加后端主配置文件。
- [x] 添加数据库连接配置项。
- [x] 添加 Redis 连接配置项。
- [x] 添加 Sa-Token 配置项。
- [x] 添加 CORS 配置。
- [x] 添加日志级别配置。
- [x] 添加本地开发配置，且 `application-dev.yml` 不提交到远程。
- [x] 添加生产配置示例 `application-prod.yml.example`。
- [x] 确认配置中没有真实敏感信息。

## 3. 数据库 SQL

- [x] 编写 `user_account` 建表 SQL。
- [x] 编写 `ledger` 建表 SQL。
- [x] 编写 `ledger_member` 建表 SQL。
- [x] 编写 `ledger_person` 建表 SQL。
- [x] 编写 `ledger_transaction` 建表 SQL。
- [x] 编写 `ledger_transaction_person` 建表 SQL。
- [x] 编写 `ledger_invite` 建表 SQL。
- [x] 编写 `idempotency_record` 建表 SQL。
- [x] 编写 `ledger_change_log` 建表 SQL。
- [x] 添加必要索引和唯一约束。
- [x] 添加软删除字段。
- [x] 添加创建时间和更新时间字段。
- [x] 整理成可直接执行的初始化 SQL 文件 `simon-ledger-api/sql/001_init_schema.sql`。

## 4. 登录注册

- [x] 实现用户注册接口 `POST /api/auth/register`。
- [x] 实现用户登录接口 `POST /api/auth/login`。
- [x] 实现用户退出接口 `POST /api/auth/logout`。
- [x] 实现当前用户接口 `GET /api/auth/me`。
- [x] 密码使用 BCrypt 或 Argon2 存储。
- [x] 登录成功返回 Token。
- [x] 业务接口默认要求登录。
- [x] 注册和登录参数校验。

## 5. 账本接口

- [x] 实现账本列表接口 `GET /api/ledgers`。
- [x] 实现创建账本接口 `POST /api/ledgers`。
- [x] 创建账本时自动创建 owner 成员。
- [x] 实现账本详情接口 `GET /api/ledgers/{ledgerUuid}`。
- [x] 实现编辑账本接口 `PUT /api/ledgers/{ledgerUuid}`。
- [x] 实现删除账本接口 `DELETE /api/ledgers/{ledgerUuid}`。
- [x] 所有账本接口校验成员权限。

## 6. 参与人接口

- [x] 实现参与人列表接口 `GET /api/ledgers/{ledgerUuid}/people`。
- [x] 实现新增参与人接口 `POST /api/ledgers/{ledgerUuid}/people`。
- [x] 实现编辑参与人接口 `PUT /api/ledgers/{ledgerUuid}/people/{personUuid}`。
- [x] 实现删除参与人接口 `DELETE /api/ledgers/{ledgerUuid}/people/{personUuid}`。
- [x] 删除参与人使用软删除。
- [x] 历史流水仍可展示已删除参与人名称。

## 7. 流水接口

- [x] 实现流水列表接口 `GET /api/ledgers/{ledgerUuid}/transactions`。
- [x] 支持流水列表查询参数：`startAt`、`endAt`、`type`、`category`、`personUuid`、`page`、`pageSize`。
- [x] 实现新增流水接口 `POST /api/ledgers/{ledgerUuid}/transactions`。
- [x] 新增流水必须传 `clientOperationId`。
- [x] 实现流水详情接口 `GET /api/ledgers/{ledgerUuid}/transactions/{transactionUuid}`。
- [x] 实现编辑流水接口 `PUT /api/ledgers/{ledgerUuid}/transactions/{transactionUuid}`。
- [x] 编辑流水校验 `version`。
- [x] 实现删除流水接口 `DELETE /api/ledgers/{ledgerUuid}/transactions/{transactionUuid}`。
- [x] 删除流水校验 `version`。
- [x] 版本冲突返回 `409001`。

## 8. 成员和邀请

- [x] 实现成员列表接口 `GET /api/ledgers/{ledgerUuid}/members`。
- [x] 实现修改成员角色接口 `PUT /api/ledgers/{ledgerUuid}/members/{memberUuid}/role`。
- [x] 实现移除成员接口 `DELETE /api/ledgers/{ledgerUuid}/members/{memberUuid}`。
- [x] 实现创建邀请接口 `POST /api/ledgers/{ledgerUuid}/invites`。
- [x] 实现查询邀请接口 `GET /api/invites/{code}`。
- [x] 实现加入账本接口 `POST /api/invites/{code}/join`。
- [x] 邀请码支持过期时间。
- [x] 邀请码支持默认角色。

## 9. 统计接口

- [x] 实现账本汇总接口 `GET /api/ledgers/{ledgerUuid}/stats/summary`。
- [x] 实现分类统计接口 `GET /api/ledgers/{ledgerUuid}/stats/categories`。
- [x] 实现人员结余接口 `GET /api/ledgers/{ledgerUuid}/stats/people-balances`。
- [x] 统计逻辑按参与人平均分摊。
- [x] 统计排除软删除流水。

## 10. 幂等和同步基础

- [ ] 写接口支持 `Idempotency-Key` 或 `clientOperationId`。
- [ ] 创建账本支持幂等。
- [ ] 创建邀请支持幂等。
- [ ] 加入账本支持幂等。
- [ ] 新增流水支持幂等。
- [ ] 编辑流水支持幂等。
- [ ] 删除流水支持幂等。
- [ ] 实现变更记录写入 `ledger_change_log`。
- [ ] 实现增量变更接口 `GET /api/ledgers/{ledgerUuid}/changes`。

## 11. Flutter API 基础层

- [ ] 添加 HTTP 客户端依赖。
- [ ] 新增 `lib/core/network/api_client.dart`。
- [ ] 新增 `lib/core/network/api_result.dart`。
- [ ] 新增 Token 存储。
- [ ] 添加请求自动带 Token。
- [ ] 添加统一错误解析。
- [ ] 添加登录状态 Provider。

## 12. Flutter Repository 抽象

- [ ] 新增 `AuthRepository`。
- [ ] 新增 `LedgerRepository`。
- [ ] 新增 `PersonRepository`。
- [ ] 新增 `TransactionRepository`。
- [ ] 新增本地 Repository 实现，包装现有 Isar。
- [ ] 新增远端 Repository 实现，调用后端 API。
- [ ] Provider 改为依赖 Repository，不直接依赖 `DatabaseService`。
- [ ] 未登录时保留本地账本模式。
- [ ] 已登录时使用云端账本模式。

## 13. Flutter 登录接入

- [ ] 新增登录页面。
- [ ] 新增注册页面。
- [ ] 登录成功保存 Token。
- [ ] 退出登录清理 Token。
- [ ] App 启动时恢复登录态。
- [ ] 登录后加载当前用户信息。
- [ ] 未登录时仍允许使用本地模式。

## 14. Flutter 云账本接入

- [ ] 云端账本列表接入 `GET /api/ledgers`。
- [ ] 云端创建账本接入 `POST /api/ledgers`。
- [ ] 云端编辑账本接入 `PUT /api/ledgers/{ledgerUuid}`。
- [ ] 云端删除账本接入 `DELETE /api/ledgers/{ledgerUuid}`。
- [ ] 云端参与人列表接入。
- [ ] 云端新增、编辑、删除参与人接入。
- [ ] 云端流水列表接入。
- [ ] 云端新增、编辑、删除流水接入。
- [ ] 写操作失败时提示用户重试。

## 15. 本地数据导入云端

- [ ] 扫描本地账本。
- [ ] 展示可导入账本列表。
- [ ] 用户选择要导入的账本。
- [ ] 创建云端账本。
- [ ] 上传账本参与人。
- [ ] 上传流水。
- [ ] 记录导入进度。
- [ ] 防止已导入账本重复上传。
- [ ] 导入失败可重试。

## 16. 验收

- [ ] 注册、登录、退出流程可用。
- [ ] 登录后能创建云端账本。
- [ ] 登录后能看到自己的云端账本列表。
- [ ] 账本参与人 CRUD 可用。
- [ ] 流水 CRUD 可用。
- [ ] 多用户成员权限基本可用。
- [ ] 统计接口结果和 Flutter 本地统计口径一致。
- [ ] OpenAPI 文档可访问。
- [ ] SQL 可在目标数据库直接执行。
- [ ] Flutter 本地模式没有被破坏。
