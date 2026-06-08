# Simon Ledger 邀请链接部署

账本邀请统一使用以下 HTTPS 地址：

```text
https://ledger.simon996.com/invite/{code}
```

## Web

`nginx.conf` 已支持 Flutter Web SPA 回退。直接访问 `/invite/{code}` 时，Nginx
会返回 `index.html`，Flutter 再打开邀请确认页面。

## Android App Links

Android 已声明处理 `https://ledger.simon996.com/invite/*`。部署前：

1. 使用正式 APK 签名证书生成 SHA-256 指纹。
2. 将 `web/.well-known/assetlinks.json.example` 复制为
   `build/web/.well-known/assetlinks.json`。
3. 将 `REPLACE_WITH_RELEASE_APK_SIGNING_CERT_SHA256` 替换为正式指纹。
4. 部署后确认以下地址无需跳转即可返回 JSON：

```text
https://ledger.simon996.com/.well-known/assetlinks.json
```

## iOS Universal Links

iOS 已添加 `applinks:ledger.simon996.com` Associated Domain。部署前：

1. 在 Apple Developer 后台确认 App ID 已启用 Associated Domains。
2. 将 `web/.well-known/apple-app-site-association.example` 复制为
   `build/web/.well-known/apple-app-site-association`。
3. 将 `REPLACE_WITH_APPLE_TEAM_ID` 替换为 Apple Team ID。
4. 部署后确认以下地址无需跳转即可返回 JSON：

```text
https://ledger.simon996.com/.well-known/apple-app-site-association
```

两个验证文件都不能经过登录鉴权，也不要配置 301 或 302 跳转。
