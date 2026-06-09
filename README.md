# Simon Ledger Flutter

Simon Ledger 的多端客户端，支持 Android、iOS 和 Web。应用定位是本地优先的多人账本：用户可以不登录直接记账，也可以登录后把账本同步到云端并邀请其他成员协作。

## 核心能力

- 本地账本：未登录时也能创建账本、维护参与人、记录收入和支出。
- 云端协作：登录后使用远端 API，同步账本、参与人和流水。
- 离线优先：写操作先落本地缓存，网络恢复后由同步协调器自动上传。
- 多人分摊：账本成员和账本参与人分离，支持未注册人员作为分摊对象。
- 代付结算：支出可选择共同钱包或指定参与人垫付，并在统计中计算应收应付。
- 统计分析：支持账本、分类、人员结余和展示币种切换。
- 分享邀请：已同步账本可生成邀请码/邀请链接，支持 Web 路由、移动端深链和剪贴板识别。
- 图片分享：可生成账本概览图或长图，移动端保存到相册，Web 下载 PNG。

## 技术栈

- Flutter 3 / Dart 3.11
- Riverpod：状态管理和依赖注入
- shared_preferences：跨端本地缓存
- Dio：HTTP 客户端
- fl_chart：统计图表
- screenshot：分享图片生成
- connectivity_plus / app_links：网络恢复和邀请链接接入

## 目录结构

```text
lib/
  app.dart                         # MaterialApp、路由、全局同步触发
  main.dart                        # 初始化本地数据库并启动 ProviderScope
  core/
    common/                        # 平台能力适配：相册、图片保存等
    config/                        # 头像等统一配置
    database/                      # shared_preferences 本地数据层
    di/                            # Riverpod 依赖注入
    models/                        # Ledger、Person、TransactionRecord 等
    network/                       # Dio、Token、API 响应和错误处理
    preferences/                   # 本地偏好和资料缓存
    repositories/                  # 本地/远端仓库实现
    services/                      # 同步、导入、邀请链接、资料同步
  features/
    auth/                          # 我的、登录注册、同步中心
    home/                          # 四个主 Tab 容器
    ledgers/                       # 账本列表、详情、邀请、分享图
    onboarding/                    # 首次使用引导
    people_pool/                   # 参与人编辑
    statistics/                    # 统计页
    transactions/                  # 记账、编辑流水、流水详情
```

## 数据与同步原则

本地数据存储在 `shared_preferences` 中：

```text
local_store.people.v1
local_store.ledgers.v1
local_store.transactions.v1
```

Repository 会根据 token 自动切换：

- 无有效 token：使用 `LocalLedgerRepository`、`LocalPersonRepository`、`LocalTransactionRepository`。
- 有有效 token：使用 `Remote*Repository`，但仍优先写本地缓存，再尝试同步云端。

本地临时 UUID 与远端 UUID 的映射统一由 `SyncIdentityResolver` 维护。不要在业务代码里自行猜测或拼接远端 UUID。

## API 地址

默认 API：

```text
https://ledger-api.simon996.com
```

构建时可覆盖：

```bash
flutter build web --dart-define=API_BASE_URL=https://example.com
```

## 本地开发

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

Web 调试：

```bash
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:18080
```

## 构建

```bash
flutter build apk --debug
flutter build web --release
flutter build ios --no-codesign
```

Web 构建产物需要通过 HTTP 服务或 nginx 部署，不能直接双击 `build/web/index.html`。

## 文档

- [产品功能说明](docs/product-features.md)
- [项目接手说明](docs/project-handoff.md)
- [UI 方向](docs/ui-direction.md)
- [账本邀请功能](docs/ledger-invite-feature.md)
- [邀请链接部署](docs/invite-link-deployment.md)

## Git

- Remote: `git@github.com:simon-996/simon_ledger_flutter.git`
- Default branch: `master`
- Commit message style: `feat: ...`、`fix: ...`、`docs: ...`

提交前请检查工作区，避免误提交本地配置、构建产物或他人未提交修改。
