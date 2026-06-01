# Simon Ledger 项目接手说明

> 每次开始维护 Simon Ledger 前先阅读本文档。本文档描述当前产品目标、已实现能力、实际架构、离线同步原则、三端差异、验证方式和已知待办。  
> 实施历史与逐项进度见 `docs/backend-integration-todolist.md`，高频使用体验优化见 `docs/high-frequency-user-optimization-todolist.md`，真实服务验收步骤见 `docs/backend-acceptance-checklist.md`。

## 1. 项目位置与仓库

工作区根目录：

```text
/Users/simon/workplace/projects/simon_ledger
```

前端：

```text
/Users/simon/workplace/projects/simon_ledger/simon_ledger_flutter
git@github.com:simon-996/simon_ledger_flutter.git
master
```

后端：

```text
/Users/simon/workplace/projects/simon_ledger/simon-ledger-api
git@github.com:simon-996/simon-ledger-api.git
master
```

约束：

- 每次功能修改完成后执行检查、提交并推送。
- Git 提交信息使用 Conventional Commits，例如 `feat: ...`、`fix: ...`、`docs: ...`。
- 不提交真实密码、Token 和生产环境私密配置。
- 不提交部署产物：Flutter 的 `web.tar.gz`、后端的 `app.tar.gz`。
- 不覆盖工作区已有的未提交修改。开始工作前先执行 `git status --short`。

## 2. 产品核心目标

Simon Ledger 是支持单机使用、云端协作和离线操作的多人账本。

最高优先级原则：

1. **本地可用优先**：创建账本、编辑账本、维护参与人、记账、编辑和删除流水，应尽量先在本地完成并立即更新 UI。
2. **网络不阻塞操作**：已登录用户在无网、弱网情况下仍应能够继续使用；联网后自动同步待上传数据。
3. **三端逻辑一致**：Android、iOS、Web 共用业务逻辑。只在平台能力层处理相册、下载等差异。
4. **历史数据可解释**：删除参与人后，历史流水仍保留原人员信息，不显示为“未知人员”。
5. **多人账本职责清晰**：登录账号 `User` 与账本参与人 `Person` 分离。参与人既可以绑定真实账号，也可以只是手工添加的分摊对象。

产品目前支持人民币与账本基础币种。流水记录原币种和汇率换算后的人民币口径；统计可以切换展示币种。

## 3. 主要功能

### 3.1 未登录本地模式

- 设置本地昵称和头像图标。
- 创建、编辑、删除本地账本。
- 创建账本时初始化人员，默认包含本人。
- 新增、编辑、软删除参与人。
- 新增、编辑、删除收入和支出流水。
- 支出支持共同钱包或某人代付。
- 查看账本详情、筛选、人员结算、分类统计。
- 登录后可选择将本地账本导入云端。

### 3.2 登录后云端协作模式

- 注册、登录、退出、恢复登录态。
- 本地昵称头像与云端账号资料逻辑统一；离线修改先落本地，后续自动同步。
- 创建云端账本并一次性初始化参与人。
- 邀请其他账号加入共享账本。
- 在账本列表展示共享状态、在线成员和手工参与人。
- 流水记录创建者，支持区分由谁添加。
- 云端数据拉取失败时继续使用本地缓存。
- 待同步流水在列表和账本界面可见，支持自动静默同步和手动同步。

### 3.3 统计与分享

- 总收入、总支出、余额。
- 按账本、分类、人员统计。
- 多人支出平均分摊。
- 代付结算支持双向抵消，展示应收与应付。
- 分享账本概览图，或分享包含流水的长图。
- Android/iOS 保存到相册；Web 下载 PNG 文件。

## 4. Flutter 架构

版本：

```text
Flutter app version: 2.0.0+2
Dart SDK: ^3.11.3
Android applicationId: com.simon.ledger
iOS Bundle Identifier: com.simon.ledger
```

主要依赖：

- `flutter_riverpod`、`riverpod_annotation`：状态管理和依赖注入。
- `shared_preferences`：三端统一的本地持久化。
- `dio`：HTTP 客户端。
- `fl_chart`：统计图表。
- `screenshot`：生成账本分享长图。
- `gal`、`permission_handler`：移动端相册能力。

目录职责：

```text
lib/
├── core/
│   ├── common/          # 平台能力适配，例如相册打开、图片保存
│   ├── config/          # 统一头像配置
│   ├── database/        # shared_preferences 本地数据层
│   ├── di/              # Riverpod 依赖注入
│   ├── models/          # Ledger、Person、TransactionRecord 等模型
│   ├── network/         # Dio、Token、API 响应和友好错误转换
│   ├── preferences/     # 本地资料、最近账本、记账选项缓存
│   ├── repositories/    # 本地与远端 Repository
│   └── services/        # 云端导入、账户资料同步
└── features/
    ├── auth/
    ├── home/
    ├── ledgers/
    ├── people_pool/
    ├── statistics/
    └── transactions/
```

入口：

- `lib/main.dart`：初始化 `DatabaseService`，启动 `ProviderScope`。
- `lib/app.dart`：创建 `MaterialApp`。
- `lib/features/home/presentation/screens/home_page.dart`：四个主 Tab：记账、账本、统计、我的。

### 4.1 本地存储

本地数据层为 `lib/core/database/database_service.dart`。

使用 `shared_preferences` 存储 JSON，三端共用：

```text
local_store.people.v1
local_store.ledgers.v1
local_store.transactions.v1
```

核心模型：

- `Ledger`：账本、币种、汇率、参与人、排序、共享成员、远端映射、待同步状态。
- `Person`：账本参与人、头像、绑定账号、软删除、待同步状态。
- `TransactionRecord`：流水、币种、付款人、使用人员、创建者、版本、软删除、待同步状态。

### 4.2 Repository 选择

依赖注入入口为 `lib/core/di/providers.dart`。

- 无有效 Token：使用 `LocalLedgerRepository`、`LocalPersonRepository`、`LocalTransactionRepository`。
- 有有效 Token：使用对应的 `Remote*Repository`。

注意：远端 Repository 并不是“直接网络写入”。当前实现应遵循本地优先：

1. 先写 `DatabaseService`。
2. 立即更新 Riverpod state，保证界面无延迟。
3. 尝试请求远端。
4. 请求失败则保留 `pendingSync` 和 `syncError`。
5. 下次进入列表或主动同步时重试。

流水的离线链路最完整。账本和参与人已经支持本地优先写入，但后续修改时仍需重点验证本地临时账本与远端 UUID 映射。

### 4.3 本地临时账本

本地新账本使用本地 UUID。同步成功后保留本地记录，并用 `syncedRemoteUuid` 指向云端 UUID。

相关字段：

```text
Ledger.uuid
Ledger.syncedRemoteUuid
Ledger.remoteSyncUuid
Ledger.pendingSync
Ledger.syncError
```

不要在同步成功后直接删除本地临时账本，否则会破坏离线可用性和界面连续性。

账本和人员的本地 UUID 到远端 UUID 映射统一通过：

```text
lib/core/services/sync_identity_resolver.dart
```

人员映射保存在 `Person.syncedRemoteUuid`。后续同步链路不得在业务代码中自行猜测 UUID。

### 4.4 流水同步

实现位置：

```text
lib/core/repositories/transaction_repository.dart
```

关键点：

- 写流水先本地保存，随后异步同步。
- `clientOperationId` 用于幂等。
- 远端更新与删除带 `version`，用于冲突检测。
- 云端流水按页拉取，不只读取第一页。
- 待同步状态通过 `ledgerSyncStatusProvider` 暴露给 UI。
- 进入账本时可以静默尝试同步；用户也可以手动触发同步。

### 4.5 平台能力适配

平台差异集中在：

```text
lib/core/common/gallery_launcher.dart
lib/core/common/gallery_launcher_io.dart
lib/core/common/gallery_launcher_web.dart
lib/core/common/image_saver.dart
lib/core/common/image_saver_io.dart
lib/core/common/image_saver_web.dart
```

规则：

- 页面和业务层只调用统一接口。
- Android/iOS 使用相册权限并保存图片。
- Web 使用浏览器下载 PNG。
- 不要在普通业务文件中直接新增 `dart:io`、`dart:html` 或移动端插件调用。

## 5. 后端架构

后端目录：

```text
/Users/simon/workplace/projects/simon_ledger/simon-ledger-api
```

技术栈：

- Java 21
- Spring Boot 3.5.x
- Maven
- MySQL 8
- Redis
- MyBatis-Plus
- Sa-Token
- springdoc-openapi
- Log4j2

包名：

```text
com.simon.ledger
```

目录：

```text
src/main/java/com/simon/ledger/
├── common/       # Result、ErrorCode、业务异常
├── config/       # Web、CORS、登录拦截、MyBatis 配置
├── controller/   # REST API
├── dto/          # 请求和响应对象
├── entity/       # 数据库实体
├── mapper/       # MyBatis-Plus Mapper
└── service/      # 接口与实现
```

### 5.1 数据库

初始化与迁移 SQL：

```text
simon-ledger-api/sql/001_init_schema.sql
simon-ledger-api/sql/002_add_transaction_payer.sql
```

核心表：

- `user_account`
- `ledger`
- `ledger_member`
- `ledger_person`
- `ledger_transaction`
- `ledger_transaction_person`
- `ledger_invite`
- `idempotency_record`
- `ledger_change_log`

生产数据库必须同时执行初始化 SQL 和后续迁移 SQL。缺少 `002_add_transaction_payer.sql` 会导致 `payer_person_id` 列不存在。

### 5.2 主要 API

公开接口：

```text
POST /api/auth/register
POST /api/auth/login
GET  /health
GET  /api/health
GET  /api/invites/{code}
```

登录后主要接口：

```text
GET    /api/auth/me
PUT    /api/auth/me
POST   /api/auth/logout

GET    /api/ledgers
POST   /api/ledgers
POST   /api/ledgers/with-people
GET    /api/ledgers/{ledgerUuid}
PUT    /api/ledgers/{ledgerUuid}
DELETE /api/ledgers/{ledgerUuid}

GET    /api/ledgers/people?ledgerUuids=uuid1,uuid2
GET    /api/ledgers/{ledgerUuid}/people
POST   /api/ledgers/{ledgerUuid}/people
PUT    /api/ledgers/{ledgerUuid}/people/{personUuid}
DELETE /api/ledgers/{ledgerUuid}/people/{personUuid}

GET    /api/ledgers/{ledgerUuid}/transactions
POST   /api/ledgers/{ledgerUuid}/transactions
PUT    /api/ledgers/{ledgerUuid}/transactions/{transactionUuid}
DELETE /api/ledgers/{ledgerUuid}/transactions/{transactionUuid}
```

还有成员、邀请、统计和变更日志接口，详见 Swagger：

```text
http://localhost:18080/swagger-ui.html
```

统一响应：

```json
{
  "code": 0,
  "message": "success",
  "data": {}
}
```

Token Header：

```text
simon-ledger: <token>
```

线上 API 默认地址：

```text
https://ledger-api.simon996.com
```

Flutter 可用构建参数覆盖：

```bash
flutter build web --dart-define=API_BASE_URL=https://example.com
```

## 6. 关键业务规则

### 6.1 User 与 Person

- `User` 是登录账号。
- `Person` 是某个账本中的参与人。
- 在线用户加入账本按用户 ID 去重，不按昵称限制。
- 手工添加的参与人同一账本内名称不能重复。
- 已绑定在线用户的参与人修改时不得丢失 `linkedUserUuid`。
- 删除参与人使用软删除，历史流水继续引用该参与人。

### 6.2 支出与代付

流水类型：

```text
0 = 支出
1 = 收入
```

支出模式：

- `payerPersonUuid == null`：共同钱包。
- `payerPersonUuid != null`：指定参与人代付。

代付模式下，付款人可以不属于使用人员。统计需要计算应收、应付，并抵消双向债务。

### 6.3 币种

- 每个账本保存基础币种 `baseCurrencyCode`。
- 每个账本保存基础币种到人民币汇率 `exchangeRateToCNY`。
- 流水保存实际币种。
- 人民币流水无需重复展示换算。
- 非人民币流水展示原币金额和换算人民币金额。

### 6.4 幂等与版本

- 写接口通过 `Idempotency-Key` 或 `clientOperationId` 保证重试安全。
- 后端幂等服务已处理并发双执行窗口，并校验 Key 长度。
- 流水编辑和删除使用 `version` 防止覆盖并发修改。
- 版本冲突返回业务错误码 `409001`。

## 7. 三端运行与验证

常规检查：

```bash
cd /Users/simon/workplace/projects/simon_ledger/simon_ledger_flutter
flutter analyze
flutter test
flutter build apk --debug
flutter build web
flutter build ios --simulator
```

后端检查：

```bash
cd /Users/simon/workplace/projects/simon_ledger/simon-ledger-api
mvn test
```

最近一次三端构建验证已通过：

```text
flutter analyze
flutter test
flutter build apk --debug
flutter build web
flutter build ios --simulator
```

注意：

- iOS 构建可能自动生成或修改 `ios/Podfile`、`ios/Podfile.lock`、Xcode 配置文件。提交前先检查差异，不要误提交构建噪音。
- `permission_handler_apple` 当前会提示 Swift Package Manager 兼容性警告，尚未阻断构建。
- Android 当前会提示 Kotlin Gradle Plugin 未来兼容性警告，尚未阻断构建。
- Web 构建产物必须通过 nginx 或 HTTP 服务部署，不能直接双击 `build/web/index.html`。

## 8. 部署

本地部署脚本位于工作区根目录，按约定不提交 Git：

```text
/Users/simon/workplace/projects/simon_ledger/deploy_api.sh
/Users/simon/workplace/projects/simon_ledger/deploy_web.sh
/Users/simon/workplace/projects/simon_ledger/deploy_web_server.sh
```

后端：

- Maven 打包 `target/app.jar`。
- 将 `app.jar` 和后端 `Dockerfile` 打包为 `app.tar.gz`。
- 上传至 `simon996.com:/apps/simon_ledger`。

Web：

- 执行 `flutter build web --release`。
- 将 `build/web`、Flutter `Dockerfile`、`nginx.conf` 打包为 `web.tar.gz`。
- 上传至 `simon996.com:/apps/simon_ledger`。
- 服务器构建 nginx 镜像并运行容器 `simon_ledger-web`，宿主机端口为 `18081`。

后端环境配置：

```text
simon-ledger-api/src/main/resources/application-dev.yml
simon-ledger-api/src/main/resources/application-prod.yml
```

这些文件是本地或服务器私密配置，不提交。生产示例：

```text
simon-ledger-api/src/main/resources/application-prod.yml.example
```

## 9. 已知待办与风险

开始新功能前先审视以下事项：

1. **离线同步仍需持续补测**：尤其验证本地临时账本同步成功后，再离线新增、编辑、删除人员和流水，随后恢复网络是否正确映射到远端账本。
2. **冲突处理仍偏基础**：流水依赖版本号避免覆盖，但 UI 还需要更明确地提示冲突并提供恢复动作。
3. **真实环境验收未全部勾选**：继续按 `docs/backend-acceptance-checklist.md` 在真实 API、数据库和多用户环境验证。
4. **本地存储容量有限**：当前使用 `shared_preferences` JSON。数据量增长后应评估迁移到三端兼容的结构化本地数据库。
5. **旧 Isar 数据不自动迁移**：如需要保留旧版本本地数据，应单独增加迁移入口。

## 10. 继续开发时的检查清单

1. 阅读本文档与 `docs/backend-integration-todolist.md`。
2. 分别检查 Flutter 和后端仓库 `git status --short`。
3. 不覆盖已有未提交文件。
4. 修改业务逻辑时同时评估未登录、本地临时账本、登录在线、登录离线四种场景。
5. 修改平台能力时保持业务层统一，通过 `core/common` 增加适配层。
6. 修改后端表结构时新增 SQL 迁移文件，不只改实体。
7. 修改接口时同步更新 Flutter Repository、后端 Controller/DTO/Service 和本文档。
8. 完成后执行必要测试和三端构建。
9. 更新 TODO 文档，使用 Conventional Commits 提交并推送。
