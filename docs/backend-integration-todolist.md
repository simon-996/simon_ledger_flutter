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

- [x] 写接口支持 `Idempotency-Key` 或 `clientOperationId`。
- [x] 创建账本支持幂等。
- [x] 创建邀请支持幂等。
- [x] 加入账本支持幂等。
- [x] 新增流水支持幂等。
- [x] 编辑流水支持幂等。
- [x] 删除流水支持幂等。
- [x] 实现变更记录写入 `ledger_change_log`。
- [x] 实现增量变更接口 `GET /api/ledgers/{ledgerUuid}/changes`。

## 11. Flutter API 基础层

- [x] 添加 HTTP 客户端依赖。
- [x] 新增 `lib/core/network/api_client.dart`。
- [x] 新增 `lib/core/network/api_result.dart`。
- [x] 新增 Token 存储。
- [x] 添加请求自动带 Token。
- [x] 添加统一错误解析。
- [x] 添加登录状态 Provider。

## 12. Flutter Repository 抽象

- [x] 新增 `AuthRepository`。
- [x] 新增 `LedgerRepository`。
- [x] 新增 `PersonRepository`。
- [x] 新增 `TransactionRepository`。
- [x] 新增本地 Repository 实现，包装本地存储。
- [x] 新增远端 Repository 实现，调用后端 API。
- [x] Provider 改为依赖 Repository，不直接依赖 `DatabaseService`。
- [x] 未登录时保留本地账本模式。
- [x] 已登录时使用云端账本模式。

说明：当前 Flutter 仍有全局人员池 UI，远端 `PersonRepository` 先支持读取，远端人员新增、编辑、删除需要后续改成账本维度人员工作流后启用。

## 13. Flutter 登录接入

- [x] 新增登录页面。
- [x] 新增注册页面。
- [x] 登录成功保存 Token。
- [x] 退出登录清理 Token。
- [x] App 启动时恢复登录态。
- [x] 登录后加载当前用户信息。
- [x] 未登录时仍允许使用本地模式。

## 14. Flutter 云账本接入

- [x] 云端账本列表接入 `GET /api/ledgers`。
- [x] 云端创建账本接入 `POST /api/ledgers`。
- [x] 云端编辑账本接入 `PUT /api/ledgers/{ledgerUuid}`。
- [x] 云端删除账本接入 `DELETE /api/ledgers/{ledgerUuid}`。
- [x] 云端参与人列表接入。
- [x] 云端账本列表加载参与人失败时不阻断账本列表展示，避免单个账本人员异常导致整页加载失败。
- [x] 账本相关界面展示 `Simon-{uuid 后 8 位}` 短标识，用于区分同名账本。
- [x] 登录态恢复完成后再加载账本列表和统计，避免登录后仍显示未登录本地空账本。
- [x] 删除账本时先从列表移除并失败回滚，避免 `Dismissible` 删除动画结束后短暂红屏警告。
- [x] 云端新增、编辑、删除参与人接入。
- [x] 云端流水列表接入。
- [x] 云端新增、编辑、删除流水接入。
- [x] 写操作失败时提示用户重试。

## 15. 本地数据导入云端

- [x] 扫描本地账本。
- [x] 展示可导入账本列表。
- [x] 用户选择要导入的账本。
- [x] 创建云端账本。
- [x] 上传账本参与人。
- [x] 上传流水。
- [x] 记录导入进度。
- [x] 防止已导入账本重复上传。
- [x] 导入失败可重试。
- [x] 修复本地账本导入云端时过长幂等键可能触发后端系统错误的问题，导入用固定长度稳定 key。

## 16. Web 端适配

- [x] 移除 Flutter 共享模型对 Isar 生成代码的直接依赖。
- [x] 将未登录本地模式切换为 `shared_preferences` 存储，兼容 web 构建。
- [x] 移除 Flutter 项目中的 Isar 运行时和生成器依赖。
- [x] 云端账本解析保留后端返回的成员角色字段。
- [x] `flutter build web` 构建通过。
- [x] 添加 Flutter Web nginx 静态部署 Dockerfile。
- [x] 添加 Flutter Web nginx SPA 回退配置。
- [x] 添加本地 Web 部署脚本 `/Users/simon/workplace/projects/simon_ledger/deploy_web.sh`，脚本不提交到 git。
- [x] 添加服务器 Web 部署脚本 `/apps/simon_ledger/scripts/deploy_web.sh`。
- [x] Web 部署包使用 `web.tar.gz.tmp` 上传并校验后替换，避免半包覆盖正式包。
- [x] Web 容器 `simon_ledger-web` 运行在服务器 `18081` 端口。

说明：旧版 Isar 本地数据不会自动迁移到新的本地存储，如需保留历史本地数据，后续需要单独增加迁移入口。

## 17. 本地身份

- [x] 未登录用户可在“我的”页面设置本地昵称。
- [x] 未登录用户可在“我的”页面选择本地头像图标。
- [x] 本地身份使用 `shared_preferences` 持久化，兼容 Android、iOS 和 Web。
- [x] 新建账本时默认勾选“加入本人”。
- [x] 新建账本时自动把本地身份加入账本人员，并避免重复创建同名人员。
- [x] 注册时自动使用本地身份的昵称和头像。
- [x] 登录用户可在“我的”页面修改账号昵称和头像。
- [x] 后端提供当前用户资料更新接口 `PUT /api/auth/me`。
- [x] 在线用户加入账本按绑定用户 ID 去重，不按昵称限制。
- [x] 手动添加的账本参与人按名称去重，避免同一账本出现重复手动名称。

## 18. 审计待修改

- [x] 修复后端幂等实现的并发双执行窗口：当前先查幂等记录、执行业务后再保存记录，并发相同 `Idempotency-Key` 时可能重复执行写操作；应改为先占用幂等键或用数据库唯一键/状态机锁住请求，再执行业务并保存响应。
- [x] 修复 Flutter 云端流水只读取第一页 100 条的问题：当前远端流水列表固定请求 `page=1&pageSize=100`，会导致超过 100 条后的账本详情、统计、筛选和分享结果不完整；应实现分页加载或改用后端统计接口。

## 19. 代付支出

- [x] Flutter 本地流水模型增加 `payerPersonUuid`，兼容旧流水为空表示共同钱包。
- [x] 本地 `shared_preferences` 流水持久化支持付款人字段。
- [x] 新增支出方式选择：共同钱包、某人代付。
- [x] 支持付款人给部分使用人员代付，付款人不强制加入使用人员。
- [x] 编辑流水支持修改支出方式和付款人。
- [x] 流水详情展示共同钱包或具体付款人。
- [x] 人员结余统计支持代付应收应付口径。
- [x] 账本详情和统计页展示代付结算。
- [x] 云端流水请求和响应增加 `payerPersonUuid`。
- [x] 后端 `ledger_transaction` 增加 `payer_person_id` 字段。
- [x] 后端流水创建、编辑、详情、列表支持付款人字段。
- [x] 后端人员结余统计兼容代付支出口径。
- [x] 增加数据库迁移 SQL `simon-ledger-api/sql/002_add_transaction_payer.sql`。
- [x] 代付结算支持双向净额抵消，避免同时出现 A 欠 B 和 B 欠 A。
- [x] 后端流水列表批量查询付款人 UUID，避免付款人 N+1 查询。
- [x] 统计页按收支类型区分“人员承担”和“人员收入”。
- [x] 记账和编辑页面补充分摊说明，明确共同钱包和某人代付口径。
- [x] 修复无付款人的共同钱包/收入流水返回时后端空 key 查询导致系统错误的问题。

## 20. 登录后离线记账

- [x] 登录后新增流水先写入本地缓存，不再被网络请求阻塞。
- [x] 云端模式新增流水失败时保留本地待同步状态，后续进入流水列表时自动重试同步。
- [x] 本地流水持久化增加 `clientOperationId`、`version`、`pendingSync`、`syncError` 字段。
- [x] 云端流水拉取失败时继续展示本地缓存，避免无网络时记账功能不可用。

## 21. 头像配置统一

- [x] 新增 Flutter 统一头像配置 `lib/core/config/avatar_config.dart`。
- [x] “我的”页面账号头像选择使用统一头像配置。
- [x] “我的”页面本地身份头像选择使用统一头像配置。
- [x] 账本人员新增和编辑弹窗使用统一头像配置。
- [x] 兼容旧本地身份头像 key，注册和创建账本继续使用同一头像值。

## 22. 账户资料统一和离线同步

- [x] “我的”页面只保留一个“账户昵称和头像”入口，不再拆成本地资料和账号资料两个设置。
- [x] 账户资料以本地 `LocalProfile` 为优先显示源，未登录和已登录共用同一套资料。
- [x] 登录后在没有待同步修改时，用云端账号资料刷新本地资料。
- [x] 已登录修改头像昵称时先写本地，网络失败时保留待同步状态。
- [x] “我的”页面在资料待同步时显示提示，同步中显示 loading，同步成功显示成功提示。
- [x] 后端 `PUT /api/auth/me` 同步更新所有绑定当前用户的账本参与人头像昵称，并写变更日志。
- [x] Flutter 账本本人匹配在云端模式优先使用 `linkedUserUuid`，不再按昵称匹配在线用户。
- [x] 编辑账本参与人时保留 `linkedUserUuid`，避免误解除在线用户绑定。
- [x] 后端参与人列表兼容未绑定用户的手动参与人，避免 `linked_user_id` 为空时返回系统错误。
- [x] 后端幂等服务增加 `Idempotency-Key` 长度校验，避免数据库字段超长时返回系统错误。

## 23. 验收

说明：2026-05-22 已通过自动化检查：后端 `mvn test`、Flutter `flutter analyze`、Flutter `flutter test`、Flutter `flutter build web`。以下验收项需要连接真实后端服务和目标数据库后逐项确认。

验收步骤见 `docs/backend-acceptance-checklist.md`。

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

## 24. 审查优化待办

- [ ] 人员和流水 Provider 等待登录态恢复后再选择本地/远端仓储，避免登录后短暂读取本地空数据。
- [ ] 账本下拉框选中态改为单行展示，弹出菜单保留名称和短标识，避免选中后溢出警告。
- [ ] 远端流水编辑使用持久化的远端 UUID 和版本信息，避免 App 重启后编辑变成新增重复流水。
- [ ] 远端流水删除支持本地待同步队列，没网时可先删除本地显示，联网后自动同步。
- [ ] 记账列表展示待同步、同步失败状态，让用户知道离线记录是否已上传。
- [ ] 云端创建账本时“加入本人”流程增加失败恢复或重试入口，避免账本创建成功但本人加入失败。
- [ ] 优化云端账本参与人加载方式，减少账本列表 N+1 请求对首页加载速度的影响。
