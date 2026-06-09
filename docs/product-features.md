# Simon Ledger 产品功能说明

本文档描述 Simon Ledger 当前产品能力和核心业务规则。历史 TODO、后端草案和验收过程已合并到本文档及各项目 README 中。

## 产品定位

Simon Ledger 是一个本地优先的多人账本工具。它既支持未登录用户在本机独立记账，也支持登录用户把账本同步到云端并邀请其他用户共同维护。

核心原则：

- 本地可用优先：记账、编辑、删除、维护参与人等高频操作应先落本地并立即反馈。
- 网络不阻塞操作：弱网或离线时保留待同步状态，恢复网络后自动上传。
- User 与 Person 分离：登录账号负责访问权限，账本参与人负责分摊和统计。
- 历史数据可解释：删除参与人使用软删除，历史流水仍能显示原参与人信息。
- 多端一致：Android、iOS、Web 共享业务逻辑，平台差异集中在适配层。

## 使用模式

### 未登录本地模式

- 设置本地昵称和头像。
- 创建、编辑、删除本地账本。
- 创建账本时初始化参与人，并可默认加入本人。
- 新增、编辑、软删除参与人。
- 新增、编辑、删除收入和支出流水。
- 支出支持共同钱包或指定参与人垫付。
- 查看账本详情、流水筛选、人员结算、分类统计。
- 登录后可选择把本地账本导入云端。

### 登录云端模式

- 注册、登录、退出、恢复登录态。
- 账号资料和本地资料统一展示，离线修改先保存本地，后续自动同步。
- 创建云端账本并初始化参与人。
- 邀请其他账号加入共享账本。
- 账本列表展示共享状态、在线成员和手动参与人。
- 流水记录创建者，支持区分谁添加了流水。
- 云端拉取失败时继续使用本地缓存。
- 待同步流水、人员和账本在列表与同步中心可见，支持自动同步和手动重试。

## 核心概念

### User

登录账号，存储在后端 `user_account` 表中。User 决定是否能访问某个云端账本。

### Ledger Member

账本成员，存储在后端 `ledger_member` 表中。成员是某个 User 在某个账本里的权限记录。

角色：

- owner：账本拥有者。
- admin：管理成员、邀请和账本设置。
- editor：新增和编辑流水。
- viewer：只读查看。

### Person

账本参与人，存储在前端本地缓存和后端 `ledger_person` 表中。Person 是分摊对象，可以绑定 User，也可以只是手动添加的普通参与人。

示例：

- 登录用户本人。
- 家人、朋友、同事。
- 公司报销、公共基金、临时垫付对象。

## 账本与同步

本地创建的账本使用本地 UUID。上传云端成功后，不删除本地记录，而是在本地账本上记录 `syncedRemoteUuid`，保证页面和离线链路连续。

同步顺序：

```text
账本 -> 参与人 -> 流水
```

关键字段：

- `Ledger.syncedRemoteUuid`
- `Person.syncedRemoteUuid`
- `pendingSync`
- `syncError`
- `clientOperationId`
- `version`

统一映射逻辑在：

```text
lib/core/services/sync_identity_resolver.dart
```

## 流水规则

流水类型：

```text
0 = 支出
1 = 收入
```

支出方式：

- `payerPersonUuid == null`：共同钱包。
- `payerPersonUuid != null`：指定参与人垫付。

垫付模式下，付款人可以不属于使用人员。统计会计算应收应付，并抵消双向债务，避免同时出现 A 欠 B 和 B 欠 A。

## 币种规则

- 每个账本保存基础币种 `baseCurrencyCode`。
- 每个账本保存基础币种到人民币汇率 `exchangeRateToCNY`。
- 流水保存实际币种。
- 人民币流水不重复展示换算金额。
- 非人民币流水展示原币金额和人民币换算金额。

## 邀请规则

- 只有已同步到云端的账本可以生成邀请。
- 同一账本默认维护一个当前可用邀请码。
- 用户主动重新生成时，后端禁用旧邀请码并创建新邀请码。
- 邀请码有过期时间、使用次数和默认角色。
- 加入账本必须登录。
- 邀请链接格式：

```text
https://ledger.simon996.com/invite/{code}
```

移动端通过 App Links / Universal Links 打开，Web 通过 `/invite/{code}` 路由打开。

## 前端主要入口

```text
lib/main.dart
lib/app.dart
lib/features/home/presentation/screens/home_page.dart
lib/core/di/providers.dart
lib/core/database/database_service.dart
lib/core/services/sync_coordinator.dart
```

## 后端主要入口

```text
simon-ledger-api/src/main/java/com/simon/ledger/controller
simon-ledger-api/src/main/java/com/simon/ledger/service
simon-ledger-api/sql
```

## 后台管理规划

后台管理 Web 位于：

```text
simon-ledger-admin
```

第一阶段定位为运维、客服和数据核查控制台：

- 管理员登录。
- 用户查询和账号状态查看。
- 账本查询和账本详情只读排查。
- 邀请码查看和禁用。
- 同步与变更日志查看。
- 系统健康检查。
- 后台管理员操作日志。

后台不应在第一阶段直接编辑用户流水金额，避免破坏离线同步和版本一致性。
