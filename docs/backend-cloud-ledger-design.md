# Simon Ledger 云端多人账本后端设计

## 1. 目标

将当前本地单机账本升级为云端多人协作账本，支持用户登录、云端同步、多人共同维护账本、成员权限控制和基础统计。

第一版目标是做出稳定闭环，不追求复杂离线冲突合并和强实时协作。后续再逐步加入离线队列、实时推送和审计日志。

## 2. 技术选型

后端选型：

- Java 21
- Spring Boot 3.x
- Sa-Token
- MySQL 8
- MyBatis-Plus
- Redis
- Flyway
- springdoc-openapi
- Docker Compose

选型理由：

- Spring Boot 生态成熟，长期维护成本低。
- Sa-Token 适合快速完成登录态、权限校验、踢人、注销、Token 续期。
- MyBatis-Plus 适合 CRUD 业务，和 MySQL 配合稳定。
- Redis 用于登录态、验证码、邀请码、限流和热点缓存。
- Flyway 管理数据库版本，避免手工改表不可追踪。
- OpenAPI 文档方便 Flutter 端对接。

## 3. 总体架构

```text
Flutter App / Web
        |
        | HTTPS + JSON
        v
Spring Boot API
        |
        | Sa-Token
        v
Auth / Permission
        |
        +---------- MySQL
        |
        +---------- Redis
```

Flutter 端不直接操作数据库，统一通过后端 API 读写云端数据。

本地 Isar 后续可以作为缓存层保留：

- 未登录：允许本地单机模式。
- 已登录：云端为准，本地缓存用于加速展示。
- 第一版不做复杂离线合并，只做失败提示和手动重试。

## 4. 核心设计原则

### 4.1 User 和 Person 分离

`user` 是登录账号。

`ledger_person` 是账本里的参与人。

一个账本参与人可以绑定登录用户，也可以只是一个普通记账对象。

示例：

- 张三是登录用户，也是账本成员。
- 妈妈只是一个分摊对象，没有登录账号。
- 公司报销也是账本参与对象，但不是用户。

这可以避免把“账号体系”和“账本参与人”强行绑定。

### 4.2 账本权限是账本维度，不是全局角色

同一个用户在不同账本里可能有不同权限：

- 在家庭账本是 owner。
- 在旅行账本是 editor。
- 在公司报销账本是 viewer。

Sa-Token 只负责确认用户是否登录。具体账本权限通过 `ledger_member` 表判断。

### 4.3 分阶段同步策略

第一阶段采用“云端为准，本地缓存”的策略：

- App 启动后拉取云端账本。
- 进入账本后拉取成员、参与人、流水。
- 新增、编辑、删除直接请求后端。
- 请求成功后更新本地 UI。
- 请求失败提示用户重试。

第二阶段支持离线新增流水：

- 无网或弱网时允许新增流水。
- 本地先写入流水和同步队列。
- UI 立即展示，状态标记为 `pending`。
- 网络恢复后自动上传。
- 服务端通过 `client_operation_id` 幂等去重。
- 上传成功后，其他共享成员通过刷新、轮询或后续实时推送看到新流水。

第三阶段再支持离线编辑和删除已同步流水，并引入版本号和冲突处理。

## 5. 模块划分

建议后端目录：

```text
simon-ledger-api
├── common
│   ├── auth
│   ├── config
│   ├── exception
│   ├── result
│   └── web
├── module
│   ├── auth
│   ├── user
│   ├── ledger
│   ├── member
│   ├── person
│   ├── transaction
│   ├── invite
│   └── stats
└── infrastructure
    ├── persistence
    ├── redis
    └── security
```

模块职责：

- `auth`: 注册、登录、退出、Token 刷新。
- `user`: 用户资料。
- `ledger`: 账本 CRUD。
- `member`: 账本成员和权限。
- `person`: 账本参与人。
- `transaction`: 流水 CRUD。
- `invite`: 邀请码和邀请链接。
- `stats`: 账本统计、人员结余、分类统计。

## 6. 数据库设计

### 6.1 user_account

```text
id bigint primary key
uuid varchar(64) unique not null
email varchar(128) unique null
phone varchar(32) unique null
password_hash varchar(255) null
nickname varchar(64) not null
avatar varchar(255) null
status tinyint not null
created_at datetime not null
updated_at datetime not null
deleted_at datetime null
```

说明：

- `uuid` 给客户端使用，避免暴露自增 ID。
- 邮箱和手机号可以二选一。
- `status`: 1 正常，2 禁用。

### 6.2 ledger

```text
id bigint primary key
uuid varchar(64) unique not null
name varchar(128) not null
base_currency_code varchar(16) not null
exchange_rate_to_cny decimal(18, 8) not null
owner_user_id bigint not null
created_at datetime not null
updated_at datetime not null
deleted_at datetime null
```

### 6.3 ledger_member

```text
id bigint primary key
uuid varchar(64) unique not null
ledger_id bigint not null
user_id bigint not null
role varchar(32) not null
status tinyint not null
joined_at datetime not null
created_at datetime not null
updated_at datetime not null
deleted_at datetime null
unique key uk_ledger_user (ledger_id, user_id)
```

角色：

- `owner`: 账本拥有者。
- `admin`: 管理成员、管理流水。
- `editor`: 新增和编辑流水。
- `viewer`: 只读。

### 6.4 ledger_person

```text
id bigint primary key
uuid varchar(64) unique not null
ledger_id bigint not null
linked_user_id bigint null
name varchar(64) not null
avatar varchar(64) not null
created_at datetime not null
updated_at datetime not null
deleted_at datetime null
```

说明：

- `linked_user_id` 为空时，表示普通参与人。
- 绑定用户后，可以用于展示“这个参与人对应哪个真实账号”。

### 6.5 ledger_transaction

```text
id bigint primary key
uuid varchar(64) unique not null
ledger_id bigint not null
type tinyint not null
amount decimal(18, 2) not null
currency_code varchar(16) not null
category varchar(64) not null
note varchar(512) null
created_by_user_id bigint not null
last_modified_by_user_id bigint null
client_operation_id varchar(128) null
version int not null
happened_at datetime not null
created_at datetime not null
updated_at datetime not null
deleted_at datetime null
```

说明：

- `type`: 0 支出，1 收入。
- `happened_at`: 业务发生时间。
- `created_at`: 记录创建时间。
- `client_operation_id`: 客户端写操作 ID，用于离线重试和服务端幂等。
- `version`: 数据版本，用于后续编辑和删除冲突检测。

### 6.6 ledger_transaction_person

```text
id bigint primary key
transaction_id bigint not null
person_id bigint not null
share_amount decimal(18, 2) null
share_ratio decimal(10, 6) null
created_at datetime not null
unique key uk_transaction_person (transaction_id, person_id)
```

第一版可以平均分摊，只保存参与人。后续支持自定义分摊时再使用 `share_amount` 或 `share_ratio`。

### 6.7 ledger_invite

```text
id bigint primary key
uuid varchar(64) unique not null
ledger_id bigint not null
code varchar(64) unique not null
role varchar(32) not null
created_by_user_id bigint not null
max_uses int null
used_count int not null
expires_at datetime not null
created_at datetime not null
disabled_at datetime null
```

说明：

- 邀请码可以设置默认加入角色，例如 `editor` 或 `viewer`。
- 可以限制使用次数和过期时间。

### 6.8 idempotency_record

```text
id bigint primary key
user_id bigint not null
request_key varchar(128) not null
request_method varchar(16) not null
request_path varchar(255) not null
response_code int not null
response_body json null
created_at datetime not null
expires_at datetime not null
unique key uk_user_request_key (user_id, request_key)
```

说明：

- 用于防止弱网重试或离线队列重复提交造成重复账本、重复邀请、重复流水。
- `request_key` 来自客户端的 `Idempotency-Key` 或 `clientOperationId`。
- 第一次请求成功后保存响应摘要，重复请求直接返回第一次结果。
- 记录可以设置过期时间，例如 7-30 天。

### 6.9 ledger_change_log

```text
id bigint primary key
uuid varchar(64) unique not null
ledger_id bigint not null
entity_type varchar(32) not null
entity_uuid varchar(64) not null
operation varchar(32) not null
operator_user_id bigint not null
version int not null
created_at datetime not null
```

说明：

- 用于增量同步和多人协作变更感知。
- `entity_type`: ledger / member / person / transaction。
- `operation`: create / update / delete。
- App 可以根据最后同步版本拉取变更。

## 7. 权限规则

### 7.1 登录权限

所有业务接口默认要求登录：

```java
@SaCheckLogin
```

例外：

- 注册
- 登录
- 验证码
- 健康检查
- 公开邀请信息查询

### 7.2 账本权限

每次访问账本资源都需要检查用户是否属于该账本。

权限建议：

```text
viewer:
  - 查看账本
  - 查看流水
  - 查看统计

editor:
  - viewer 权限
  - 新增流水
  - 编辑自己创建的流水

admin:
  - editor 权限
  - 编辑所有流水
  - 删除流水
  - 管理账本参与人
  - 邀请成员

owner:
  - admin 权限
  - 转让账本
  - 删除账本
  - 移除 admin
```

实现方式：

- Sa-Token 获取当前 userId。
- 查询 `ledger_member`。
- 根据 role 判断是否允许操作。
- 权限校验封装成 `LedgerPermissionService`。

## 8. API 草案

### 8.1 Auth

```text
POST /api/auth/register
POST /api/auth/login
POST /api/auth/logout
GET  /api/auth/me
```

### 8.2 Ledger

```text
GET    /api/ledgers
POST   /api/ledgers
GET    /api/ledgers/{ledgerUuid}
PUT    /api/ledgers/{ledgerUuid}
DELETE /api/ledgers/{ledgerUuid}
```

### 8.3 Member

```text
GET    /api/ledgers/{ledgerUuid}/members
PUT    /api/ledgers/{ledgerUuid}/members/{memberUuid}/role
DELETE /api/ledgers/{ledgerUuid}/members/{memberUuid}
```

### 8.4 Invite

```text
POST /api/ledgers/{ledgerUuid}/invites
GET  /api/invites/{code}
POST /api/invites/{code}/join
```

### 8.5 Person

```text
GET    /api/ledgers/{ledgerUuid}/people
POST   /api/ledgers/{ledgerUuid}/people
PUT    /api/ledgers/{ledgerUuid}/people/{personUuid}
DELETE /api/ledgers/{ledgerUuid}/people/{personUuid}
```

### 8.6 Transaction

```text
GET    /api/ledgers/{ledgerUuid}/transactions
POST   /api/ledgers/{ledgerUuid}/transactions
GET    /api/ledgers/{ledgerUuid}/transactions/{transactionUuid}
PUT    /api/ledgers/{ledgerUuid}/transactions/{transactionUuid}
DELETE /api/ledgers/{ledgerUuid}/transactions/{transactionUuid}
POST   /api/ledgers/{ledgerUuid}/transactions/sync
```

流水列表查询参数：

```text
startAt
endAt
type
category
personUuid
page
pageSize
```

写接口要求：

- 创建流水必须传 `clientOperationId`。
- 编辑和删除已同步流水时必须传 `version`。
- 服务端发现版本不一致时返回 `409001 数据冲突`。

### 8.7 Sync

```text
GET  /api/ledgers/{ledgerUuid}/changes?afterVersion=123
POST /api/ledgers/{ledgerUuid}/sync/outbox
```

说明：

- `changes` 用于拉取账本增量变更。
- `sync/outbox` 用于批量上传本地离线操作。
- 第一版可以先不用批量接口，离线新增流水可以逐条调用创建流水接口。

### 8.8 Stats

```text
GET /api/ledgers/{ledgerUuid}/stats/summary
GET /api/ledgers/{ledgerUuid}/stats/categories
GET /api/ledgers/{ledgerUuid}/stats/people-balances
```

## 9. 统一响应

建议统一返回：

```json
{
  "code": 0,
  "message": "ok",
  "data": {}
}
```

错误示例：

```json
{
  "code": 401001,
  "message": "未登录",
  "data": null
}
```

常用错误码：

```text
0       成功
400001  参数错误
401001  未登录
403001  无权限
404001  资源不存在
409001  数据冲突
500001  系统错误
```

## 10. Flutter 接入计划

### 10.1 新增 API 层

```text
lib/core/network
├── api_client.dart
├── auth_interceptor.dart
└── api_result.dart
```

建议使用 `dio`：

- 统一 baseUrl。
- 自动带 token。
- 统一错误处理。
- 请求超时和重试。

### 10.2 Repository 抽象

当前 UI 不应该直接依赖本地数据库。建议抽象：

```text
LedgerRepository
PersonRepository
TransactionRepository
AuthRepository
```

实现：

```text
LocalLedgerRepository
RemoteLedgerRepository
```

第一阶段可以保留本地模式，登录后使用远端模式。

### 10.3 数据迁移

第一次登录后可以提供“导入本地账本到云端”：

1. 读取本地 Isar 账本。
2. 用户选择要上传的账本。
3. 调用云端创建账本、人员、流水接口。
4. 成功后标记本地账本已同步。

## 11. 应用设计

这一阶段只关注产品和应用本身，重点放在账号、协作、权限、流水、同步状态和数据导入。

### 11.1 登录和账号

第一版账号能力：

- 手机号或邮箱注册。
- 密码登录。
- 退出登录。
- 获取当前用户信息。
- 修改昵称和头像。

后续可扩展：

- 验证码登录。
- Apple 登录。
- 微信登录。
- 账号注销。
- 设备管理。

登录后的 App 首页展示“我的云账本”。未登录时可以继续使用本地账本，登录后再提供本地数据导入云端。

### 11.2 账本协作

账本是协作的核心单位。

一个账本包含：

- 账本基础信息。
- 成员列表。
- 账本参与人。
- 流水记录。
- 统计数据。

多人协作流程：

1. 用户创建账本，自动成为 owner。
2. owner 或 admin 创建邀请。
3. 被邀请用户登录后加入账本。
4. 加入后根据角色获得对应权限。
5. 成员可以共同新增、编辑、删除流水。

账本成员和账本参与人不是同一个概念：

- 成员是登录用户，决定谁能访问和维护账本。
- 参与人是分摊对象，决定一条流水算到谁身上。

### 11.3 邀请和加入

第一版使用邀请码：

- 邀请码有过期时间。
- 邀请码可以设置默认角色。
- 邀请码可以限制使用次数。
- 加入前展示账本名称、邀请人和默认角色。

加入成功后的处理：

- 创建 `ledger_member`。
- 可选创建或绑定 `ledger_person`。
- 刷新用户账本列表。

后续可以扩展邀请链接和二维码。

### 11.4 参与人设计

参与人属于某个账本。

参与人可以是：

- 已登录用户绑定的参与人。
- 未绑定用户的普通参与人。
- 临时对象，例如“公司报销”“公共基金”。

绑定规则：

- 一个 `ledger_person` 可以绑定一个 `user_account`。
- 同一个账本内，一个用户通常只绑定一个参与人。
- 未绑定参与人仍然可以参与分摊。

App 中的展示：

- 参与人头像和名称优先来自 `ledger_person`。
- 如果绑定了用户，可以展示账号头像作为辅助信息。
- 删除参与人使用软删除，历史流水仍能显示原名称。

### 11.5 流水设计

流水是账本的主要业务数据。

第一版字段：

- 类型：支出 / 收入。
- 金额。
- 币种。
- 分类。
- 备注。
- 发生时间。
- 参与人列表。
- 创建人。

第一版分摊策略：

- 多人参与时默认平均分摊。
- 服务端保存流水和参与人关系。
- 统计时根据参与人数量计算每个人的收入、支出和结余。

后续分摊策略：

- 按固定金额分摊。
- 按比例分摊。
- 某人代付、多人分摊。
- 借还款记录。

### 11.6 同步和缓存

同步能力分阶段实现，避免一开始把离线编辑、冲突合并和实时协作全部做进去。

第一阶段：云端为准，本地缓存。

- 进入账本时拉取云端最新数据。
- 数据拉取成功后写入本地缓存。
- 下次进入时可以先展示缓存，再刷新云端数据。
- 缓存数据需要记录 `lastSyncedAt`。
- 新增、编辑、删除流水直接请求服务端。
- 服务端成功后返回最新数据。
- App 更新本地状态和缓存。
- 失败时不修改本地最终数据，只提示用户重试。

第二阶段：支持离线新增流水。

- 网络不可用或请求失败时，允许用户继续新增流水。
- App 本地创建流水并写入同步队列。
- 流水在 UI 中立即出现，状态显示为 `pending`。
- 网络恢复、App 启动、进入账本、下拉刷新时触发自动同步。
- 上传成功后状态改为 `synced`。
- 上传失败后状态改为 `failed`，允许用户手动重试。

第三阶段：支持离线编辑和删除已同步流水。

- 已同步流水必须带 `version`。
- 离线编辑和删除写入同步队列。
- 上传时服务端检查版本。
- 如果服务端版本已变化，返回冲突，App 展示冲突处理界面。

### 11.7 本地同步队列

App 需要维护本地 `sync_outbox`。

建议字段：

```text
local_id
client_operation_id
ledger_uuid
entity_type
entity_uuid
operation
payload_json
base_version
status
retry_count
last_error
created_at
updated_at
```

字段说明：

- `client_operation_id`: 每个本地操作唯一 ID。
- `entity_type`: transaction / person / ledger。
- `operation`: create / update / delete。
- `payload_json`: 请求服务端所需数据。
- `base_version`: 编辑和删除时客户端看到的版本。
- `status`: pending / syncing / synced / failed / conflict。

同步规则：

- 同一个账本内按创建时间顺序上传。
- 正在上传的操作标记为 `syncing`。
- 上传成功后标记为 `synced`，并写入服务端返回的 uuid/version。
- 可重试错误进入 `failed`，保留错误信息。
- 冲突错误进入 `conflict`，等待用户处理。

第一版离线能力只要求支持 `transaction create`。其他操作可以保持在线请求。

### 11.8 幂等和防重复提交

记账类应用必须避免重复流水。

App 侧：

- 保存按钮点击后进入 loading。
- 请求完成前禁用重复点击。
- 每个写操作生成 `clientOperationId`。

服务端：

- 写接口接收 `clientOperationId` 或 `Idempotency-Key`。
- 同一用户、同一接口、同一幂等 key 只处理一次。
- 重复请求返回第一次处理结果。

适用接口：

- 创建账本。
- 创建邀请。
- 加入账本。
- 新增流水。
- 编辑流水。
- 删除流水。

### 11.9 冲突处理

离线新增流水通常不需要冲突处理，因为它是新增数据。

离线编辑和删除已同步流水必须处理冲突。

冲突场景：

- A 离线编辑流水时，本地看到 `version = 3`。
- B 在线修改同一条流水，服务端版本变成 `version = 4`。
- A 恢复网络后上传编辑请求，仍然带 `baseVersion = 3`。
- 服务端发现版本不一致，返回 `409001 数据冲突`。

App 处理方式：

- 拉取服务端最新流水。
- 展示“本地修改”和“云端最新版本”的差异。
- 用户选择保留云端、覆盖云端或手动合并。

第一版不做离线编辑已同步流水，因此可以先不做冲突 UI。文档保留该设计，后续实现。

### 11.10 共享账本增量同步

当 A 离线新增流水并自动上传成功后，其他成员需要看到这条流水。

第一版实现：

- 其他成员进入账本时拉取最新流水。
- 下拉刷新拉取最新流水。
- 当前账本页面可以定时轮询 `changes` 接口，例如 30 秒一次。

后续实现：

- WebSocket / SSE 推送账本变更。
- 服务端写入 `ledger_change_log`。
- 在线成员收到事件后拉取增量变更。
- App 根据 change log 更新本地缓存。

增量同步流程：

1. App 保存每个账本的 `lastChangeVersion`。
2. 请求 `GET /api/ledgers/{ledgerUuid}/changes?afterVersion=lastChangeVersion`。
3. 服务端返回变更列表。
4. App 按顺序应用变更。
5. 更新本地 `lastChangeVersion`。

### 11.11 同步状态

App 需要清楚告诉用户数据状态。

建议状态：

- `synced`: 已同步。
- `syncing`: 同步中。
- `failed`: 同步失败。
- `cached`: 正在展示缓存。
- `localOnly`: 仅本地数据，尚未上传。
- `conflict`: 存在冲突，需要用户处理。

展示位置：

- 账本详情页顶部。
- 流水列表下拉刷新区域。
- 写操作失败的 SnackBar / Dialog。
- 待同步流水条目右侧状态标识。

### 11.12 变更记录

多人协作时，用户需要知道谁改了什么。

第一版至少记录：

- 流水创建人。
- 流水最后修改人。
- 流水创建时间。
- 流水更新时间。

后续可以增加完整操作日志：

- 谁创建了账本。
- 谁邀请了成员。
- 谁加入了账本。
- 谁修改了成员权限。
- 谁新增、编辑、删除了流水。

### 11.13 通知设计

第一版可以不做推送，只在 App 内展示必要反馈：

- 邀请加入成功。
- 权限不足。
- 流水保存成功。
- 流水保存失败。
- 数据刷新失败。

后续可扩展：

- 账本成员变更通知。
- 新流水提醒。
- 成员权限变更提醒。
- WebSocket 实时刷新。

### 11.14 本地数据导入云端

用户升级到云端后，需要保留原本本地账本。

导入流程：

1. 用户登录。
2. App 扫描本地账本。
3. 展示可导入账本列表。
4. 用户选择要导入的账本。
5. 创建云端账本。
6. 上传参与人。
7. 上传流水。
8. 标记本地账本已导入。

导入要求：

- 导入过程可取消。
- 已导入账本不要重复上传。
- 上传失败可以重试。
- 云端账本创建成功但流水未完全上传时，需要保留导入进度。

### 11.15 Web 版本应用策略

Web 版本可以作为后续目标，但第一版后端设计不依赖 Web。

Web 需要额外处理：

- 当前 Isar 依赖不适合直接编译到 Web。
- Web 本地缓存可以使用浏览器存储。
- 分享长图在 Web 上应改为下载图片。
- 登录态保存要考虑浏览器刷新后的恢复。

建议先完成移动端云同步，再处理 Web 兼容。

## 12. 安全设计

必须做：

- HTTPS。
- 密码使用 BCrypt / Argon2。
- Token 存 Redis。
- 登录限流。
- 验证码限流。
- 邀请码过期。
- 所有账本资源都做成员权限校验。
- 删除使用软删除。
- 服务端不要信任客户端传入的 userId。

建议做：

- 操作日志。
- 异常登录提醒。
- 敏感接口二次确认。
- 数据库定时备份和恢复演练。

## 13. 开发里程碑

### Milestone 1: 后端骨架

- Spring Boot 项目
- Docker Compose: MySQL + Redis
- Sa-Token 配置
- 统一响应
- 全局异常处理
- Flyway 初始化
- OpenAPI 文档

### Milestone 2: 登录注册

- 用户注册
- 用户登录
- 用户退出
- 当前用户信息
- Flutter 保存 Token

### Milestone 3: 云账本

- 账本 CRUD
- 账本成员 owner 自动创建
- 账本列表
- 权限校验基础服务

### Milestone 4: 多人协作

- 邀请码创建
- 邀请码加入账本
- 成员列表
- 成员角色修改
- 移除成员

### Milestone 5: 云端流水

- 人员 CRUD
- 流水 CRUD
- 流水参与人
- 基础统计接口

### Milestone 6: Flutter 接入

- 登录页
- API Client
- Repository 抽象
- 云端账本列表
- 云端流水
- 本地数据导入云端

### Milestone 7: 离线新增和自动同步

- 本地缓存增强
- 请求幂等键
- 同步状态 UI
- 本地 `sync_outbox`
- 离线新增流水
- 网络恢复后自动上传
- 上传成功后更新共享账本变更版本

### Milestone 8: 协作增量同步

- `ledger_change_log`
- `changes` 增量接口
- 当前账本轮询刷新
- 成员看到其他人新增的流水
- 后续扩展 WebSocket / SSE

### Milestone 9: 应用体验完善

- 本地账本导入云端
- 成员变更提示
- 流水操作记录
- 离线编辑和删除设计落地
- 冲突处理 UI

## 14. 推荐第一步

先创建后端项目 `/Users/simon/workplace/projects/simon_ledger/simon-ledger-api`，与 `simon_ledger_flutter` 同级，包名使用 `com.simon.ledger`，完成：

1. Spring Boot 项目骨架。
2. MySQL + Redis Docker Compose。
3. Sa-Token 登录配置。
4. Flyway 建表。
5. 用户注册和登录接口。
6. OpenAPI 文档。

完成后再让 Flutter 接入登录，不要同时大规模改 App 和后端。
