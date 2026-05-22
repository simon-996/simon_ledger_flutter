# Backend Acceptance Checklist

本文档用于连接真实后端、数据库和 Flutter 客户端后执行验收。验收通过后，再回到 `backend-integration-todolist.md` 第 16 节把对应事项标记为 `[x]`。

## 前置准备

- 后端目录：`/Users/simon/workplace/projects/simon_ledger/simon-ledger-api`
- Flutter 目录：`/Users/simon/workplace/projects/simon_ledger/simon_ledger_flutter`
- 后端配置：复制并调整 `simon-ledger-api/src/main/resources/application-prod.yml.example`，本地开发使用不提交的 `application-dev.yml`。
- 数据库 SQL：执行 `simon-ledger-api/sql/001_init_schema.sql`。
- OpenAPI 地址：`http://localhost:18080/swagger-ui.html`
- API Docs 地址：`http://localhost:18080/v3/api-docs`
- Token Header：`simon-ledger: <token>`

## 后端基础验收

1. 执行 SQL 初始化数据库。
2. 启动后端服务。
3. 打开 `http://localhost:18080/swagger-ui.html`，确认 OpenAPI 页面可访问。
4. 请求健康检查接口，确认服务可访问。

```bash
curl http://localhost:18080/health
```

## 登录注册

1. 注册用户 A。
2. 用户 A 登录并记录返回 token。
3. 使用 token 请求当前用户。
4. 调用退出登录。
5. 退出后再次请求需要登录的接口，应返回未登录错误。

```bash
curl -X POST http://localhost:18080/api/auth/register \
  -H 'Content-Type: application/json' \
  -d '{"email":"a@example.com","password":"12345678","nickname":"用户A"}'

curl -X POST http://localhost:18080/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"account":"a@example.com","password":"12345678"}'

curl http://localhost:18080/api/auth/me \
  -H 'simon-ledger: <token>'
```

## 云账本

1. 登录 Flutter。
2. 创建云端账本。
3. 回到账本列表，确认新账本可见。
4. 编辑账本名称、默认币种、汇率。
5. 删除账本，确认列表不再显示。

后端接口可用性：

```bash
curl http://localhost:18080/api/ledgers \
  -H 'simon-ledger: <token>'
```

## 参与人

1. 在 Flutter 中进入已创建的云端账本编辑页。
2. 新增参与人。
3. 编辑参与人姓名和头像。
4. 删除参与人。
5. 回到账本详情、记账页、统计页，确认参与人显示一致。

后端接口可用性：

```bash
curl http://localhost:18080/api/ledgers/<ledgerUuid>/people \
  -H 'simon-ledger: <token>'
```

## 流水

1. 在 Flutter 中选择云端账本。
2. 新增一条支出流水，选择参与人。
3. 新增一条收入流水，选择参与人。
4. 编辑流水金额、分类、备注、参与人。
5. 删除流水。
6. 刷新后确认列表与后端一致。

后端接口可用性：

```bash
curl 'http://localhost:18080/api/ledgers/<ledgerUuid>/transactions?page=1&pageSize=20' \
  -H 'simon-ledger: <token>'
```

## 多用户成员权限

1. 注册并登录用户 A，创建账本。
2. 用户 A 创建邀请链接或邀请码。
3. 注册并登录用户 B，通过邀请码加入账本。
4. 用户 B 能查看账本、参与人、流水。
5. 用户 A 调整用户 B 角色。
6. 用非成员用户访问账本接口，应返回无权限错误。

## 统计口径

1. 创建同一组测试流水，至少包含收入、支出、多人平摊。
2. 对比 Flutter 本地模式统计结果和后端统计接口结果。
3. 验证总收入、总支出、余额、分类统计、人员结余一致。

```bash
curl http://localhost:18080/api/ledgers/<ledgerUuid>/stats/summary \
  -H 'simon-ledger: <token>'

curl http://localhost:18080/api/ledgers/<ledgerUuid>/stats/categories \
  -H 'simon-ledger: <token>'

curl http://localhost:18080/api/ledgers/<ledgerUuid>/stats/people-balances \
  -H 'simon-ledger: <token>'
```

## 本地模式

1. 退出登录。
2. 创建本地账本。
3. 新增、编辑、删除本地参与人。
4. 新增、编辑、删除本地流水。
5. 查看本地账本详情和统计。
6. 重新登录后确认云端模式可用，本地数据不被误删。

## 本地数据导入云端

1. 退出登录，在本地模式创建账本、参与人和流水。
2. 登录后进入“我的”页面。
3. 点击“本地数据导入云端”中的“选择并导入”。
4. 勾选账本并导入。
5. 确认导入进度显示正常。
6. 导入完成后确认云端账本、参与人和流水存在。
7. 再次打开导入入口，确认已导入账本不会重复上传。
