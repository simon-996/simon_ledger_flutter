# API Optimistic Conflict Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为账户资料、账本、成员、参与人和流水建立统一、原子的实体版本控制，返回可供 Flutter 冲突中心直接消费的结构化 HTTP 409，并补齐软删除恢复和 editor 自有流水删除权限。

**Architecture:** 每个可修改实体持久化 `version`。更新、软删除和恢复都使用 MyBatis-Plus `LambdaUpdateWrapper` 执行单条条件 SQL，条件同时包含 `id`、客户端提交的 `version` 和正确的 `deleted_at` 状态；不使用“先查版本、再无条件 updateById”。条件更新影响 0 行时，在事务内使用当前读重新加载包含软删除的远端实体，并抛出携带安全业务快照的 `VersionConflictException`。控制器把它映射为 HTTP 409 / 业务码 `409001`。删除返回轻量版本结果，恢复返回完整实体。

**Tech Stack:** Java 21、Spring Boot 3.5.11、MyBatis-Plus 3.5.12、Sa-Token、Jakarta Validation、JUnit 5、Mockito、Maven、MySQL 8

---

## Scope and invariants

本计划只实现设计稿第 14 节的“API 并发基础”。Flutter 冲突存储/UI、邀请加入自动参与人、邀请角色 UI 和云端统计在后续独立计划中完成。

实现过程中必须保持以下不变量：

- 创建版本固定为 `1`；成功更新、软删除、恢复后版本严格 `+1`。
- 持久化字段为 `user_account.version`、`ledger.version`、`ledger_member.version`、`ledger_person.version` 和已存在的 `ledger_transaction.version`。
- 普通更新/删除的 SQL 必须包含 `id = ? AND version = ? AND deleted_at IS NULL`。
- 恢复的 SQL 必须包含 `id = ? AND version = ? AND deleted_at IS NOT NULL`。
- 已软删除目标的普通更新/删除返回 409，而不是 404。
- 真正不存在或 UUID 不属于当前账本的目标仍返回 404。
- 写入流程先根据当前远端实体处理 deleted/version 不匹配，再做业务字段校验，最后仍由条件 SQL 防住校验后的竞态。
- 冲突快照不得包含密码 hash、Token、数据库主键或内部用户 ID。
- 409 不能写入幂等成功缓存；成功删除/恢复需要缓存并返回版本结果。
- 远端快照重新加载使用 `FOR UPDATE` 当前读，避免 MySQL `REPEATABLE READ` 在条件更新失败后仍读到事务旧快照。
- `owner` 不可修改/移除；只有 owner 能任命、降级或移除 admin；admin 只能管理 editor/viewer。
- editor 只能编辑、删除、恢复自己创建的流水。

## API contract after this plan

```text
PUT    /api/auth/me
PUT    /api/ledgers/{ledgerUuid}
DELETE /api/ledgers/{ledgerUuid}
POST   /api/ledgers/{ledgerUuid}/restore
POST   /api/ledgers/{ledgerUuid}/leave
PUT    /api/ledgers/{ledgerUuid}/members/{memberUuid}/role
DELETE /api/ledgers/{ledgerUuid}/members/{memberUuid}
POST   /api/ledgers/{ledgerUuid}/members/{memberUuid}/restore
PUT    /api/ledgers/{ledgerUuid}/people/{personUuid}
DELETE /api/ledgers/{ledgerUuid}/people/{personUuid}
POST   /api/ledgers/{ledgerUuid}/people/{personUuid}/restore
PUT    /api/ledgers/{ledgerUuid}/transactions/{transactionUuid}
DELETE /api/ledgers/{ledgerUuid}/transactions/{transactionUuid}
POST   /api/ledgers/{ledgerUuid}/transactions/{transactionUuid}/restore
```

除创建接口外，上述写请求均携带 `version`。删除和 leave 使用：

```json
{ "version": 3 }
```

成功删除返回：

```json
{
  "code": 0,
  "message": "ok",
  "data": { "uuid": "entity-uuid", "version": 4, "deleted": true }
}
```

冲突统一返回：

```json
{
  "code": 409001,
  "message": "数据已被其他设备修改",
  "data": {
    "entityType": "transaction",
    "entityUuid": "entity-uuid",
    "submittedVersion": 3,
    "remoteVersion": 4,
    "remoteDeleted": false,
    "remoteSnapshot": {}
  }
}
```

## Task 1: Add the database and Java version contract

**Files:**

- Create: `simon-ledger-api/sql/004_add_optimistic_versions.sql`
- Modify: `simon-ledger-api/sql/001_init_schema.sql`
- Modify: `simon-ledger-api/src/main/java/com/simon/ledger/entity/UserAccount.java`
- Modify: `simon-ledger-api/src/main/java/com/simon/ledger/entity/Ledger.java`
- Modify: `simon-ledger-api/src/main/java/com/simon/ledger/entity/LedgerMember.java`
- Modify: `simon-ledger-api/src/main/java/com/simon/ledger/entity/LedgerPerson.java`
- Modify: `simon-ledger-api/src/main/java/com/simon/ledger/entity/LedgerTransaction.java`
- Modify: `simon-ledger-api/src/main/java/com/simon/ledger/dto/req/AuthProfileUpdateReq.java`
- Modify: `simon-ledger-api/src/main/java/com/simon/ledger/dto/req/LedgerUpdateReq.java`
- Modify: `simon-ledger-api/src/main/java/com/simon/ledger/dto/req/MemberRoleUpdateReq.java`
- Modify: `simon-ledger-api/src/main/java/com/simon/ledger/dto/req/PersonUpdateReq.java`
- Modify: `simon-ledger-api/src/main/java/com/simon/ledger/dto/req/TransactionUpdateReq.java`
- Create: `simon-ledger-api/src/main/java/com/simon/ledger/dto/req/VersionDeleteReq.java`
- Modify: `simon-ledger-api/src/main/java/com/simon/ledger/dto/resp/AuthUserResp.java`
- Modify: `simon-ledger-api/src/main/java/com/simon/ledger/dto/resp/LedgerResp.java`
- Modify: `simon-ledger-api/src/main/java/com/simon/ledger/dto/resp/LedgerMemberSummaryResp.java`
- Modify: `simon-ledger-api/src/main/java/com/simon/ledger/dto/resp/MemberResp.java`
- Modify: `simon-ledger-api/src/main/java/com/simon/ledger/dto/resp/PersonResp.java`
- Create: `simon-ledger-api/src/main/java/com/simon/ledger/dto/resp/VersionMutationResp.java`
- Create: `simon-ledger-api/src/test/java/com/simon/ledger/concurrency/VersionContractTests.java`
- Create: `simon-ledger-api/src/test/java/com/simon/ledger/concurrency/ConcurrencyFixtures.java`

- [ ] **Step 1: Write the failing contract test**

使用反射断言五个实体和所有更新/响应 DTO 暴露 `Integer version`，并断言新实体默认版本为 1。读取 `sql/004_add_optimistic_versions.sql`，断言只为前四张缺失版本的表添加字段，不能再次修改 `ledger_transaction.version`。

```java
@Test
void mutableEntitiesAndResponsesExposeVersion() throws Exception {
    assertEquals(1, new UserAccount().getVersion());
    assertEquals(1, new Ledger().getVersion());
    assertEquals(1, new LedgerMember().getVersion());
    assertEquals(1, new LedgerPerson().getVersion());
    assertEquals(1, new LedgerTransaction().getVersion());
    assertEquals(Integer.class, LedgerUpdateReq.class.getDeclaredField("version").getType());
    assertEquals(Integer.class, MemberResp.class.getDeclaredField("version").getType());
}
```

- [ ] **Step 2: Run the focused test and confirm failure**

Run from `D:/workplace/projects/simon-ledger/simon-ledger-api`:

```powershell
mvn -Dtest=VersionContractTests test
```

Expected: test compilation or assertions fail because the new fields/classes/migration do not exist.

- [ ] **Step 3: Implement schema and model fields**

在 `001_init_schema.sql` 的五张表中声明 `version INT NOT NULL DEFAULT 1`；迁移只 ALTER 现有四张缺失字段的表：

```sql
USE simon_ledger;

ALTER TABLE user_account ADD COLUMN version INT NOT NULL DEFAULT 1 AFTER status;
ALTER TABLE ledger ADD COLUMN version INT NOT NULL DEFAULT 1 AFTER owner_user_id;
ALTER TABLE ledger_member ADD COLUMN version INT NOT NULL DEFAULT 1 AFTER status;
ALTER TABLE ledger_person ADD COLUMN version INT NOT NULL DEFAULT 1 AFTER avatar;
```

五个实体使用显式初值，不添加 `@Version`，因为后续需要同时约束软删除状态：

```java
private Integer version = 1;
```

所有更新请求的版本字段使用：

```java
@NotNull(message = "版本号不能为空")
@Min(value = 1, message = "版本号必须大于 0")
private Integer version;
```

删除结果定义为：

```java
@Data
@AllArgsConstructor
public class VersionMutationResp {
    private String uuid;
    private Integer version;
    private Boolean deleted;
}
```

- [ ] **Step 4: Make all create/toResp paths honor the contract**

检查注册、账本创建、owner 成员创建、参与人创建和流水创建；依赖实体默认值或显式 `setVersion(1)`，并在所有 `toResp`/`toMemberSummary` 中复制版本。不要把 `deletedAt` 加入普通公开响应。

```java
// UserAccount, Ledger, LedgerMember, LedgerPerson, LedgerTransaction
private Integer version = 1;

// AuthServiceImpl.toUserResp
resp.setVersion(user.getVersion());
// LedgerServiceImpl.toResp
resp.setVersion(ledger.getVersion());
// LedgerServiceImpl.toMemberSummary
resp.setVersion(member.getVersion());
// MemberServiceImpl.toResp
resp.setVersion(member.getVersion());
// PersonServiceImpl.toResp
resp.setVersion(person.getVersion());
// TransactionServiceImpl.toResp already copies transaction.getVersion()
```

新增测试工厂，后续测试通过 `import static com.simon.ledger.concurrency.ConcurrencyFixtures.*;` 使用，避免各测试文件出现未定义 helper：

```java
public final class ConcurrencyFixtures {
    private ConcurrencyFixtures() {}

    public static UserAccount user(long id, String uuid, String nickname, int version) {
        UserAccount value = new UserAccount();
        value.setId(id);
        value.setUuid(uuid);
        value.setNickname(nickname);
        value.setAvatar("");
        value.setStatus(1);
        value.setVersion(version);
        return value;
    }

    public static AuthProfileUpdateReq profileReq(String nickname, int version) {
        AuthProfileUpdateReq value = new AuthProfileUpdateReq();
        value.setNickname(nickname);
        value.setAvatar("");
        value.setVersion(version);
        return value;
    }

    public static Ledger ledger(long id, String uuid) {
        return ledger(id, uuid, 1, null);
    }

    public static Ledger ledger(
            long id,
            String uuid,
            int version,
            LocalDateTime deletedAt) {
        Ledger value = new Ledger();
        value.setId(id);
        value.setUuid(uuid);
        value.setName("测试账本");
        value.setBaseCurrencyCode("CNY");
        value.setExchangeRateToCny(BigDecimal.ONE);
        value.setOwnerUserId(7L);
        value.setVersion(version);
        value.setDeletedAt(deletedAt);
        return value;
    }

    public static LedgerMember member(
            long ledgerId,
            long userId,
            String role) {
        LedgerMember value = new LedgerMember();
        value.setId(41L + userId);
        value.setUuid("m-" + userId);
        value.setLedgerId(ledgerId);
        value.setUserId(userId);
        value.setRole(role);
        value.setStatus(1);
        value.setVersion(1);
        return value;
    }

    public static LedgerMember ownerMember(long ledgerId, long userId) {
        return member(ledgerId, userId, LedgerRoles.OWNER);
    }

    public static LedgerMember adminMember(long ledgerId, long userId) {
        return member(ledgerId, userId, LedgerRoles.ADMIN);
    }

    public static VersionDeleteReq deleteReq(int version) {
        VersionDeleteReq value = new VersionDeleteReq();
        value.setVersion(version);
        return value;
    }

    public static LedgerPerson person(
            long id,
            String uuid,
            int version,
            LocalDateTime deletedAt) {
        LedgerPerson value = new LedgerPerson();
        value.setId(id);
        value.setUuid(uuid);
        value.setLedgerId(11L);
        value.setName("测试参与人");
        value.setAvatar("");
        value.setVersion(version);
        value.setDeletedAt(deletedAt);
        return value;
    }

    public static PersonUpdateReq personReq(String name, int version) {
        PersonUpdateReq value = new PersonUpdateReq();
        value.setName(name);
        value.setAvatar("");
        value.setVersion(version);
        return value;
    }

    public static LedgerTransaction transaction(
            long id,
            String uuid,
            long createdBy,
            int version,
            LocalDateTime deletedAt) {
        LedgerTransaction value = new LedgerTransaction();
        value.setId(id);
        value.setUuid(uuid);
        value.setLedgerId(11L);
        value.setCreatedByUserId(createdBy);
        value.setVersion(version);
        value.setDeletedAt(deletedAt);
        return value;
    }
}
```

- [ ] **Step 5: Run tests**

```powershell
mvn -Dtest=VersionContractTests test
mvn test
```

Expected: `VersionContractTests` and the existing 4 tests pass.

- [ ] **Step 6: Commit**

```powershell
git add sql src/main/java src/test/java/com/simon/ledger/concurrency
git commit -m "feat: add optimistic versions to mutable entities"
```

## Task 2: Return structured conflicts with real HTTP status codes

**Files:**

- Modify: `simon-ledger-api/src/main/java/com/simon/ledger/common/Result.java`
- Modify: `simon-ledger-api/src/main/java/com/simon/ledger/common/exception/BusinessException.java`
- Create: `simon-ledger-api/src/main/java/com/simon/ledger/common/exception/VersionConflictException.java`
- Create: `simon-ledger-api/src/main/java/com/simon/ledger/dto/resp/ConflictResp.java`
- Modify: `simon-ledger-api/src/main/java/com/simon/ledger/config/web/RestExceptionHandler.java`
- Create: `simon-ledger-api/src/test/java/com/simon/ledger/config/web/RestExceptionHandlerTests.java`

- [ ] **Step 1: Write failing handler tests**

覆盖以下断言：

1. `VersionConflictException` -> HTTP 409、code `409001`、message 和 `ConflictResp` 原样输出。
2. BAD_REQUEST/UNAUTHORIZED/FORBIDDEN/NOT_FOUND -> 对应 HTTP 400/401/403/404。
3. 未知异常 -> HTTP 500，响应不泄露异常文本。

```java
@Test
void versionConflictReturnsHttp409AndSnapshot() {
    ConflictResp conflict = new ConflictResp(
            "ledger", "l-1", 2, 3, false, Map.of("name", "远端账本", "version", 3));
    ResponseEntity<Result<?>> response = handler.businessExceptionHandler(
            new VersionConflictException(conflict));

    assertEquals(HttpStatus.CONFLICT, response.getStatusCode());
    assertEquals(ErrorCode.CONFLICT.getCode(), response.getBody().getCode());
    assertSame(conflict, response.getBody().getData());
}
```

- [ ] **Step 2: Run and confirm failure**

```powershell
mvn -Dtest=RestExceptionHandlerTests test
```

Expected: compilation fails because conflict payload/status support does not exist.

- [ ] **Step 3: Add the conflict payload and exception**

```java
@Data
@AllArgsConstructor
public class ConflictResp {
    private String entityType;
    private String entityUuid;
    private Integer submittedVersion;
    private Integer remoteVersion;
    private Boolean remoteDeleted;
    private Object remoteSnapshot;
}
```

`BusinessException` 增加可空 `Object data`，原构造器保持兼容。`VersionConflictException` 固定使用 `ErrorCode.CONFLICT` 和文案“数据已被其他设备修改”。`Result` 增加带 data 的 `fail` 工厂。

```java
@Getter
public class BusinessException extends RuntimeException {
    private final ErrorCode errorCode;
    private final Object data;

    public BusinessException(ErrorCode errorCode) {
        this(errorCode, errorCode.getMessage(), null);
    }

    public BusinessException(ErrorCode errorCode, String message) {
        this(errorCode, message, null);
    }

    public BusinessException(ErrorCode errorCode, String message, Object data) {
        super(message);
        this.errorCode = errorCode;
        this.data = data;
    }
}

public final class VersionConflictException extends BusinessException {
    public VersionConflictException(ConflictResp conflict) {
        super(ErrorCode.CONFLICT, "数据已被其他设备修改", conflict);
    }
}

public static <T> Result<T> fail(ErrorCode errorCode, String message, T data) {
    return new Result<T>()
            .setCode(errorCode.getCode())
            .setMessage(message)
            .setData(data);
}
```

- [ ] **Step 4: Map exceptions to `ResponseEntity<Result<?>>`**

```java
private HttpStatus status(ErrorCode code) {
    return switch (code) {
        case BAD_REQUEST -> HttpStatus.BAD_REQUEST;
        case UNAUTHORIZED -> HttpStatus.UNAUTHORIZED;
        case FORBIDDEN -> HttpStatus.FORBIDDEN;
        case NOT_FOUND -> HttpStatus.NOT_FOUND;
        case CONFLICT -> HttpStatus.CONFLICT;
        case SYSTEM_ERROR -> HttpStatus.INTERNAL_SERVER_ERROR;
        default -> HttpStatus.OK;
    };
}
```

所有异常 handler 都返回对应 HTTP 状态；不要只给 409 特判后保留其他错误为 HTTP 200。

```java
@ExceptionHandler(BusinessException.class)
public ResponseEntity<Result<?>> businessExceptionHandler(BusinessException e) {
    log.warn("business exception: {}", e.getMessage());
    Result<?> body = Result.fail(e.getErrorCode(), e.getMessage(), e.getData());
    return ResponseEntity.status(status(e.getErrorCode())).body(body);
}

@ExceptionHandler(Exception.class)
public ResponseEntity<Result<?>> exceptionHandler(Exception e) {
    log.error("system exception", e);
    return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
            .body(Result.fail(ErrorCode.SYSTEM_ERROR));
}
```

- [ ] **Step 5: Run tests and commit**

```powershell
mvn -Dtest=RestExceptionHandlerTests test
mvn test
git add src/main/java src/test/java/com/simon/ledger/config/web/RestExceptionHandlerTests.java
git commit -m "feat: return structured optimistic conflicts"
```

Expected: all tests pass; conflict test explicitly observes HTTP 409.

## Task 3: Make profile updates atomic and versioned

**Files:**

- Modify: `simon-ledger-api/src/main/java/com/simon/ledger/service/impl/AuthServiceImpl.java`
- Create: `simon-ledger-api/src/test/java/com/simon/ledger/service/impl/AuthServiceConcurrencyTests.java`
- Create: `simon-ledger-api/src/main/java/com/simon/ledger/dto/resp/ProfileConflictSnapshotResp.java`

- [ ] **Step 1: Write failing service tests**

使用 Mockito mock `UserAccountMapper`、`LedgerPersonMapper`、`ChangeLogService`，静态 mock `StpUtil.getLoginIdAsLong()`。至少覆盖：

- version 2 成功更新后返回 version 3。
- mapper 条件更新影响 0 行时，重新加载 version 3 并抛出 profile 冲突快照。
- 快照使用专用 `ProfileConflictSnapshotResp`，只含 `uuid/nickname/avatar/version`，不含 email、phone、status、passwordHash 或 Token。
- 同步已绑定参与人的昵称/头像时同时执行 `version = version + 1` 并记录 person change log。

先实现最小失败样例，随后按同一 fixture 补齐上面四个命名场景：

```java
@Test
void staleProfileUpdateReturnsSafeRemoteSnapshot() {
    UserAccount initial = user(7L, "u-1", "本机前", 2);
    UserAccount remote = user(7L, "u-1", "云端昵称", 3);
    when(userAccountMapper.selectById(7L)).thenReturn(initial);
    when(userAccountMapper.update(isNull(), any())).thenReturn(0);
    when(userAccountMapper.selectOne(any())).thenReturn(remote);
    AuthProfileUpdateReq req = profileReq("本机昵称", 2);

    try (MockedStatic<StpUtil> stp = mockStatic(StpUtil.class)) {
        stp.when(StpUtil::getLoginIdAsLong).thenReturn(7L);
        VersionConflictException ex = assertThrows(
                VersionConflictException.class,
                () -> service.updateProfile(req));
        ConflictResp conflict = (ConflictResp) ex.getData();
        ProfileConflictSnapshotResp snapshot =
                (ProfileConflictSnapshotResp) conflict.getRemoteSnapshot();
        assertAll(
                () -> assertEquals("profile", conflict.getEntityType()),
                () -> assertEquals(2, conflict.getSubmittedVersion()),
                () -> assertEquals(3, conflict.getRemoteVersion()),
                () -> assertEquals("云端昵称", snapshot.getNickname()),
                () -> assertFalse(snapshot.toString().contains("password")));
    }
}
```

- [ ] **Step 2: Run and confirm failure**

```powershell
mvn -Dtest=AuthServiceConcurrencyTests test
```

Expected: current `updateById(user)` does not expose atomic predicate or conflict payload.

- [ ] **Step 3: Replace `updateById` with one conditional update**

核心形态：

```java
int affected = baseMapper.update(null, Wrappers.<UserAccount>lambdaUpdate()
        .eq(UserAccount::getId, user.getId())
        .eq(UserAccount::getVersion, req.getVersion())
        .isNull(UserAccount::getDeletedAt)
        .set(UserAccount::getNickname, nickname)
        .set(UserAccount::getAvatar, avatar)
        .set(UserAccount::getVersion, req.getVersion() + 1)
        .set(UserAccount::getUpdatedAt, LocalDateTime.now()));
```

初次读取仍负责身份/状态校验，但不能把它当作并发保护。若 `affected == 0`，按主键使用 `.last("FOR UPDATE")` 当前读重新加载；存在则抛 profile `VersionConflictException`，不存在才返回 UNAUTHORIZED/NOT_FOUND。

- [ ] **Step 4: Version derived linked-person updates**

资料更新成功后，绑定参与人的昵称/头像是服务端派生同步：更新业务字段并使用 `version = version + 1`，记录 change log。它不接收 profile 的客户端版本，也不伪造 person 冲突；事务失败时 profile 和所有派生更新一起回滚。

```java
@Data
@AllArgsConstructor
public class ProfileConflictSnapshotResp {
    private String uuid;
    private String nickname;
    private String avatar;
    private Integer version;
}

private void syncLinkedPeople(Long userId, UserAccount user) {
    List<LedgerPerson> people = ledgerPersonMapper.selectList(
            Wrappers.<LedgerPerson>lambdaQuery()
                    .eq(LedgerPerson::getLinkedUserId, userId)
                    .isNull(LedgerPerson::getDeletedAt));
    LocalDateTime now = LocalDateTime.now();
    for (LedgerPerson person : people) {
        int affected = ledgerPersonMapper.update(null, Wrappers.<LedgerPerson>lambdaUpdate()
                .eq(LedgerPerson::getId, person.getId())
                .isNull(LedgerPerson::getDeletedAt)
                .set(LedgerPerson::getName, user.getNickname())
                .set(LedgerPerson::getAvatar, Objects.requireNonNullElse(user.getAvatar(), ""))
                .setSql("version = version + 1")
                .set(LedgerPerson::getUpdatedAt, now));
        if (affected == 1) {
            changeLogService.record(person.getLedgerId(), "person", person.getUuid(), "update", userId);
        }
    }
}
```

- [ ] **Step 5: Run and commit**

```powershell
mvn -Dtest=AuthServiceConcurrencyTests test
mvn test
git add src/main/java/com/simon/ledger/service/impl/AuthServiceImpl.java src/test/java/com/simon/ledger/service/impl/AuthServiceConcurrencyTests.java
git commit -m "feat: version profile updates atomically"
```

## Task 4: Version ledger update, delete, restore, and leave

**Files:**

- Modify: `simon-ledger-api/src/main/java/com/simon/ledger/controller/LedgerController.java`
- Modify: `simon-ledger-api/src/main/java/com/simon/ledger/service/LedgerService.java`
- Modify: `simon-ledger-api/src/main/java/com/simon/ledger/service/impl/LedgerServiceImpl.java`
- Create: `simon-ledger-api/src/test/java/com/simon/ledger/service/impl/LedgerServiceConcurrencyTests.java`
- Create: `simon-ledger-api/src/test/java/com/simon/ledger/controller/LedgerControllerContractTests.java`

- [ ] **Step 1: Write failing controller/service tests**

覆盖：

- update 成功 `2 -> 3`，wrapper 包含 `version` 与 `deleted_at IS NULL`。
- stale update 返回含完整 `LedgerResp` 的 ledger 冲突。
- 远端已删除时 update/delete 返回 409 且 `remoteDeleted=true`。
- delete 仅 owner 可用，返回 `VersionMutationResp(deleted=true)`。
- restore 仅 owner 可用，要求 `deleted_at IS NOT NULL`，成功 `version + 1`。
- leave 使用当前成员版本，返回 member 删除结果；owner 仍不可 leave。
- DELETE 和 leave 控制器要求 `@Valid @RequestBody VersionDeleteReq`；restore 使用 `Idempotency-Key`。

先写代表性的 stale-delete 测试，其他场景分别命名为 `updateIncrementsVersionAtomically`、`remoteDeletedUpdateReturnsConflict`、`ownerCanRestoreDeletedLedger`、`adminCannotDeleteOrRestoreLedger`、`leaveReturnsMemberVersion`、`ownerCannotLeave` 和 `deleteAndLeaveRequireVersionBody`：

```java
@Test
void staleLedgerDeleteReturnsLatestSnapshot() {
    Ledger initial = ledger(11L, "l-1", 2, null);
    Ledger remote = ledger(11L, "l-1", 3, null);
    when(ledgerMapper.selectOne(any())).thenReturn(initial, remote);
    when(ledgerMemberMapper.selectOne(any())).thenReturn(ownerMember(11L, 7L));
    when(ledgerMapper.update(isNull(), any())).thenReturn(0);
    VersionDeleteReq req = deleteReq(2);

    try (MockedStatic<StpUtil> stp = mockStatic(StpUtil.class)) {
        stp.when(StpUtil::getLoginIdAsLong).thenReturn(7L);
        VersionConflictException ex = assertThrows(
                VersionConflictException.class,
                () -> service.delete("l-1", req));
        ConflictResp conflict = (ConflictResp) ex.getData();
        assertAll(
                () -> assertEquals("ledger", conflict.getEntityType()),
                () -> assertEquals(2, conflict.getSubmittedVersion()),
                () -> assertEquals(3, conflict.getRemoteVersion()),
                () -> assertFalse(conflict.getRemoteDeleted()));
    }
}
```

- [ ] **Step 2: Run and confirm failure**

```powershell
mvn -Dtest=LedgerServiceConcurrencyTests,LedgerControllerContractTests test
```

- [ ] **Step 3: Change service signatures**

```java
LedgerResp update(String ledgerUuid, LedgerUpdateReq req);
VersionMutationResp delete(String ledgerUuid, VersionDeleteReq req);
LedgerResp restore(String ledgerUuid, LedgerUpdateReq req);
VersionMutationResp leave(String ledgerUuid, VersionDeleteReq req);
```

删除与 leave 从 `idempotencyService.executeVoid` 改为带 `VersionMutationResp.class` 和 supplier 的 `idempotencyService.execute`，确保重试能返回同一新版本。

- [ ] **Step 4: Implement active/deleted lookup and atomic mutations**

为 ledger 写入路径提供“包含软删除”查询。update/delete 只更新 active 行；restore 只更新 deleted 行。条件更新 0 行后用 `FOR UPDATE` 重载并生成冲突。

restore 不能依赖 `requireLedger()`，因为它会过滤 deleted；应先找到 ledger，再用保留的 owner member 做权限判断。

```java
private Ledger findLedgerIncludingDeleted(String ledgerUuid, boolean forUpdate) {
    var query = Wrappers.<Ledger>lambdaQuery().eq(Ledger::getUuid, ledgerUuid);
    if (forUpdate) {
        query.last("FOR UPDATE");
    }
    return baseMapper.selectOne(query);
}

private void throwLedgerConflict(Ledger remote, Integer submittedVersion, String role) {
    LedgerResp snapshot = toResp(
            remote,
            role,
            membersMap(List.of(remote.getId())).getOrDefault(remote.getId(), List.of()));
    throw new VersionConflictException(new ConflictResp(
            "ledger",
            remote.getUuid(),
            submittedVersion,
            remote.getVersion(),
            remote.getDeletedAt() != null,
            snapshot));
}

private int updateActiveLedger(Ledger ledger, LedgerUpdateReq req) {
    return baseMapper.update(null, Wrappers.<Ledger>lambdaUpdate()
            .eq(Ledger::getId, ledger.getId())
            .eq(Ledger::getVersion, req.getVersion())
            .isNull(Ledger::getDeletedAt)
            .set(Ledger::getName, req.getName().trim())
            .set(Ledger::getBaseCurrencyCode, req.getBaseCurrencyCode().trim().toUpperCase())
            .set(Ledger::getExchangeRateToCny, req.getExchangeRateToCny())
            .set(Ledger::getVersion, req.getVersion() + 1)
            .set(Ledger::getUpdatedAt, LocalDateTime.now()));
}

private int softDeleteActiveLedger(Ledger ledger, Integer submittedVersion) {
    LocalDateTime now = LocalDateTime.now();
    return baseMapper.update(null, Wrappers.<Ledger>lambdaUpdate()
            .eq(Ledger::getId, ledger.getId())
            .eq(Ledger::getVersion, submittedVersion)
            .isNull(Ledger::getDeletedAt)
            .set(Ledger::getDeletedAt, now)
            .set(Ledger::getVersion, submittedVersion + 1)
            .set(Ledger::getUpdatedAt, now));
}

private int restoreDeletedLedger(Ledger ledger, LedgerUpdateReq req) {
    return baseMapper.update(null, Wrappers.<Ledger>lambdaUpdate()
            .eq(Ledger::getId, ledger.getId())
            .eq(Ledger::getVersion, req.getVersion())
            .isNotNull(Ledger::getDeletedAt)
            .set(Ledger::getName, req.getName().trim())
            .set(Ledger::getBaseCurrencyCode, req.getBaseCurrencyCode().trim().toUpperCase())
            .set(Ledger::getExchangeRateToCny, req.getExchangeRateToCny())
            .set(Ledger::getDeletedAt, null)
            .set(Ledger::getVersion, req.getVersion() + 1)
            .set(Ledger::getUpdatedAt, LocalDateTime.now()));
}
```

- [ ] **Step 5: Version member leave**

leave 实质是当前 `ledger_member` 的软删除，因此冲突 `entityType` 是 `member`，远端快照使用 `MemberResp`，而不是 ledger 快照。

```java
private int softDeleteMember(LedgerMember member, Integer submittedVersion) {
    return ledgerMemberMapper.update(null, Wrappers.<LedgerMember>lambdaUpdate()
            .eq(LedgerMember::getId, member.getId())
            .eq(LedgerMember::getVersion, submittedVersion)
            .isNull(LedgerMember::getDeletedAt)
            .set(LedgerMember::getDeletedAt, LocalDateTime.now())
            .set(LedgerMember::getVersion, submittedVersion + 1)
            .set(LedgerMember::getUpdatedAt, LocalDateTime.now()));
}
```

查询当前用户自己的 member 时不先过滤 `deletedAt`：不存在才 403；已经删除或版本变化则返回 member 409；active 且版本相同后再检查 owner 不可 leave，最后执行上述条件更新。

- [ ] **Step 6: Run and commit**

```powershell
mvn -Dtest=LedgerServiceConcurrencyTests,LedgerControllerContractTests test
mvn test
git add src/main/java src/test/java/com/simon/ledger/service/impl/LedgerServiceConcurrencyTests.java src/test/java/com/simon/ledger/controller/LedgerControllerContractTests.java
git commit -m "feat: version ledger lifecycle mutations"
```

## Task 5: Enforce member-role authority with versioned lifecycle APIs

**Files:**

- Modify: `simon-ledger-api/src/main/java/com/simon/ledger/common/LedgerRoles.java`
- Modify: `simon-ledger-api/src/main/java/com/simon/ledger/controller/MemberController.java`
- Modify: `simon-ledger-api/src/main/java/com/simon/ledger/service/MemberService.java`
- Modify: `simon-ledger-api/src/main/java/com/simon/ledger/service/impl/MemberServiceImpl.java`
- Modify: `simon-ledger-api/src/test/java/com/simon/ledger/common/LedgerRolesTests.java`
- Create: `simon-ledger-api/src/test/java/com/simon/ledger/service/impl/MemberServiceConcurrencyTests.java`

- [ ] **Step 1: Write failing role matrix tests**

明确逐项断言：

| Operator | Target | New role / action | Result |
|---|---|---|---|
| owner | editor | admin | allow |
| owner | admin | editor/remove | allow |
| admin | editor | viewer/remove | allow |
| admin | editor | admin | forbid |
| admin | admin | editor/remove | forbid |
| any | owner | change/remove | forbid |
| editor/viewer | any | change/remove | forbid |

同时覆盖 update/remove/restore 的成功版本递增、stale 409 和 soft-deleted 409。

角色矩阵使用单个参数化测试，避免各服务分支产生不同规则：

```java
@ParameterizedTest
@CsvSource({
        "owner,editor,admin,true",
        "owner,admin,editor,true",
        "admin,editor,viewer,true",
        "admin,editor,admin,false",
        "admin,admin,editor,false",
        "editor,viewer,editor,false",
        "viewer,editor,viewer,false",
        "owner,owner,viewer,false"
})
void roleAssignmentMatchesAuthorityMatrix(
        String operator,
        String target,
        String next,
        boolean expected) {
    assertEquals(expected, LedgerRoles.canAssignRole(operator, target, next));
}

@ParameterizedTest
@CsvSource({
        "owner,admin,true",
        "admin,editor,true",
        "admin,viewer,true",
        "admin,admin,false",
        "owner,owner,false",
        "editor,viewer,false"
})
void removalMatchesAuthorityMatrix(String operator, String target, boolean expected) {
    assertEquals(expected, LedgerRoles.canRemoveRole(operator, target));
}
```

- [ ] **Step 2: Run and confirm failure**

```powershell
mvn -Dtest=LedgerRolesTests,MemberServiceConcurrencyTests test
```

Expected: current code allows admin 把 editor 任命为 admin，且无版本/恢复支持。

- [ ] **Step 3: Centralize role authority**

在 `LedgerRoles` 增加命名清楚的判断方法，服务仍负责抛具体错误：

```java
public static boolean canAssignRole(String operatorRole, String targetRole, String newRole) {
    if (isOwner(targetRole) || !isValidJoinableRole(newRole)) {
        return false;
    }
    if (isOwner(operatorRole)) {
        return true;
    }
    return ADMIN.equals(operatorRole)
            && !ADMIN.equals(targetRole)
            && !ADMIN.equals(newRole);
}

public static boolean canRemoveRole(String operatorRole, String targetRole) {
    if (isOwner(targetRole)) {
        return false;
    }
    if (isOwner(operatorRole)) {
        return true;
    }
    return ADMIN.equals(operatorRole) && !ADMIN.equals(targetRole);
}
```

不要用角色字符串字典序或单一“等级数值”推断权限；admin 对 admin 的横向操作是明确禁止项。

- [ ] **Step 4: Add versioned member routes**

```java
MemberResp updateRole(String ledgerUuid, String memberUuid, MemberRoleUpdateReq req);
VersionMutationResp remove(String ledgerUuid, String memberUuid, VersionDeleteReq req);
MemberResp restore(String ledgerUuid, String memberUuid, MemberRoleUpdateReq req);
```

新增 `POST /{memberUuid}/restore`。update/remove 查找时包含 deleted，以便远端已删返回 409；列表仍只返回 active 成员。

```java
@PostMapping("/{memberUuid}/restore")
public Result<MemberResp> restore(
        @PathVariable String ledgerUuid,
        @PathVariable String memberUuid,
        @RequestHeader(value = "Idempotency-Key", required = false) String idempotencyKey,
        @Valid @RequestBody MemberRoleUpdateReq req) {
    return Result.ok(idempotencyService.execute(
            idempotencyKey,
            "POST",
            "/api/ledgers/" + ledgerUuid + "/members/" + memberUuid + "/restore",
            MemberResp.class,
            () -> memberService.restore(ledgerUuid, memberUuid, req)));
}
```

- [ ] **Step 5: Implement atomic updates and snapshots**

成员快照使用 `MemberResp`，必须带用户 UUID、昵称、头像、role、status、joinedAt、version。角色更新、删除、恢复各自记录一次 member change log。

```java
private int updateActiveMemberRole(LedgerMember target, String newRole, Integer submittedVersion) {
    return baseMapper.update(null, Wrappers.<LedgerMember>lambdaUpdate()
            .eq(LedgerMember::getId, target.getId())
            .eq(LedgerMember::getVersion, submittedVersion)
            .isNull(LedgerMember::getDeletedAt)
            .set(LedgerMember::getRole, newRole)
            .set(LedgerMember::getVersion, submittedVersion + 1)
            .set(LedgerMember::getUpdatedAt, LocalDateTime.now()));
}

private int removeActiveMember(LedgerMember target, Integer submittedVersion) {
    LocalDateTime now = LocalDateTime.now();
    return baseMapper.update(null, Wrappers.<LedgerMember>lambdaUpdate()
            .eq(LedgerMember::getId, target.getId())
            .eq(LedgerMember::getVersion, submittedVersion)
            .isNull(LedgerMember::getDeletedAt)
            .set(LedgerMember::getDeletedAt, now)
            .set(LedgerMember::getVersion, submittedVersion + 1)
            .set(LedgerMember::getUpdatedAt, now));
}

private int restoreDeletedMember(LedgerMember target, String newRole, Integer submittedVersion) {
    return baseMapper.update(null, Wrappers.<LedgerMember>lambdaUpdate()
            .eq(LedgerMember::getId, target.getId())
            .eq(LedgerMember::getVersion, submittedVersion)
            .isNotNull(LedgerMember::getDeletedAt)
            .set(LedgerMember::getRole, newRole)
            .set(LedgerMember::getDeletedAt, null)
            .set(LedgerMember::getVersion, submittedVersion + 1)
            .set(LedgerMember::getUpdatedAt, LocalDateTime.now()));
}
```

- [ ] **Step 6: Run and commit**

```powershell
mvn -Dtest=LedgerRolesTests,MemberServiceConcurrencyTests test
mvn test
git add src/main/java src/test/java
git commit -m "feat: enforce versioned member role lifecycle"
```

## Task 6: Version person update, delete, and restore

**Files:**

- Modify: `simon-ledger-api/src/main/java/com/simon/ledger/controller/PersonController.java`
- Modify: `simon-ledger-api/src/main/java/com/simon/ledger/service/PersonService.java`
- Modify: `simon-ledger-api/src/main/java/com/simon/ledger/service/impl/PersonServiceImpl.java`
- Create: `simon-ledger-api/src/test/java/com/simon/ledger/service/impl/PersonServiceConcurrencyTests.java`

- [ ] **Step 1: Write failing tests**

覆盖 owner/admin 成功更新、删除、恢复；editor/viewer 403；stale version 409；update/delete 遇到软删除返回 `remoteDeleted=true`；恢复时 linked user UUID/name/avatar 和 version 均正确返回。

额外覆盖：业务校验（重复绑定用户、重复手动名称）应在发出条件 update 前完成，但条件 update 仍是最终并发保护。

先写远端已删除样例，并以同一 fixture 添加 `ownerAndAdminCanUpdateDeleteRestore`、`editorAndViewerCannotMutatePerson`、`duplicateLinkedUserFailsBeforeUpdate`、`duplicateManualNameFailsBeforeUpdate`、`restoreReturnsLinkedUserAndNewVersion`：

```java
@Test
void activeUpdateAgainstDeletedRemoteReturnsConflict() {
    Ledger ledger = ledger(11L, "l-1");
    LedgerPerson deleted = person(21L, "p-1", 4, LocalDateTime.now());
    when(ledgerMapper.selectOne(any())).thenReturn(ledger);
    when(ledgerMemberMapper.selectOne(any())).thenReturn(adminMember(11L, 7L));
    when(personMapper.selectOne(any())).thenReturn(deleted);
    PersonUpdateReq req = personReq("本机名称", 3);

    try (MockedStatic<StpUtil> stp = mockStatic(StpUtil.class)) {
        stp.when(StpUtil::getLoginIdAsLong).thenReturn(7L);
        VersionConflictException ex = assertThrows(
                VersionConflictException.class,
                () -> service.update("l-1", "p-1", req));
        ConflictResp conflict = (ConflictResp) ex.getData();
        assertAll(
                () -> assertEquals("person", conflict.getEntityType()),
                () -> assertEquals(4, conflict.getRemoteVersion()),
                () -> assertTrue(conflict.getRemoteDeleted()));
        verify(personMapper, never()).update(any(), any());
    }
}
```

- [ ] **Step 2: Run and confirm failure**

```powershell
mvn -Dtest=PersonServiceConcurrencyTests test
```

- [ ] **Step 3: Change lifecycle signatures and controller**

```java
PersonResp update(String ledgerUuid, String personUuid, PersonUpdateReq req);
VersionMutationResp delete(String ledgerUuid, String personUuid, VersionDeleteReq req);
PersonResp restore(String ledgerUuid, String personUuid, PersonUpdateReq req);
```

新增 `POST /{personUuid}/restore`，成功删除使用 `idempotencyService.execute` 返回版本结果。

- [ ] **Step 4: Implement conditional mutation**

update/delete 条件带 `deleted_at IS NULL`；restore 带 `deleted_at IS NOT NULL` 并设置 `deleted_at = NULL`。条件更新 0 行必须重载远端 person 和 linked user，构造完整 `PersonResp` 冲突快照。

```java
private int updateActivePerson(
        LedgerPerson person,
        PersonUpdateReq req,
        UserAccount linkedUser) {
    return baseMapper.update(null, Wrappers.<LedgerPerson>lambdaUpdate()
            .eq(LedgerPerson::getId, person.getId())
            .eq(LedgerPerson::getVersion, req.getVersion())
            .isNull(LedgerPerson::getDeletedAt)
            .set(LedgerPerson::getLinkedUserId, linkedUser == null ? null : linkedUser.getId())
            .set(LedgerPerson::getName, req.getName().trim())
            .set(LedgerPerson::getAvatar, normalizeAvatar(req.getAvatar()))
            .set(LedgerPerson::getVersion, req.getVersion() + 1)
            .set(LedgerPerson::getUpdatedAt, LocalDateTime.now()));
}

private int deleteActivePerson(LedgerPerson person, Integer submittedVersion) {
    LocalDateTime now = LocalDateTime.now();
    return baseMapper.update(null, Wrappers.<LedgerPerson>lambdaUpdate()
            .eq(LedgerPerson::getId, person.getId())
            .eq(LedgerPerson::getVersion, submittedVersion)
            .isNull(LedgerPerson::getDeletedAt)
            .set(LedgerPerson::getDeletedAt, now)
            .set(LedgerPerson::getVersion, submittedVersion + 1)
            .set(LedgerPerson::getUpdatedAt, now));
}

private int restoreDeletedPerson(
        LedgerPerson person,
        PersonUpdateReq req,
        UserAccount linkedUser) {
    return baseMapper.update(null, Wrappers.<LedgerPerson>lambdaUpdate()
            .eq(LedgerPerson::getId, person.getId())
            .eq(LedgerPerson::getVersion, req.getVersion())
            .isNotNull(LedgerPerson::getDeletedAt)
            .set(LedgerPerson::getLinkedUserId, linkedUser == null ? null : linkedUser.getId())
            .set(LedgerPerson::getName, req.getName().trim())
            .set(LedgerPerson::getAvatar, normalizeAvatar(req.getAvatar()))
            .set(LedgerPerson::getDeletedAt, null)
            .set(LedgerPerson::getVersion, req.getVersion() + 1)
            .set(LedgerPerson::getUpdatedAt, LocalDateTime.now()));
}

private void throwPersonConflict(
        Ledger ledger,
        LedgerPerson remote,
        Integer submittedVersion) {
    UserAccount linkedUser = remote.getLinkedUserId() == null
            ? null
            : userAccountMapper.selectById(remote.getLinkedUserId());
    throw new VersionConflictException(new ConflictResp(
            "person",
            remote.getUuid(),
            submittedVersion,
            remote.getVersion(),
            remote.getDeletedAt() != null,
            toResp(ledger, remote, linkedUser)));
}
```

- [ ] **Step 5: Run and commit**

```powershell
mvn -Dtest=PersonServiceConcurrencyTests test
mvn test
git add src/main/java src/test/java/com/simon/ledger/service/impl/PersonServiceConcurrencyTests.java
git commit -m "feat: version person lifecycle mutations"
```

## Task 7: Make transaction concurrency atomic and allow editor-owned deletes

**Files:**

- Modify: `simon-ledger-api/src/main/java/com/simon/ledger/controller/TransactionController.java`
- Modify: `simon-ledger-api/src/main/java/com/simon/ledger/service/TransactionService.java`
- Modify: `simon-ledger-api/src/main/java/com/simon/ledger/service/impl/TransactionServiceImpl.java`
- Delete: `simon-ledger-api/src/main/java/com/simon/ledger/dto/req/TransactionDeleteReq.java`
- Create: `simon-ledger-api/src/test/java/com/simon/ledger/service/impl/TransactionServiceConcurrencyTests.java`

- [ ] **Step 1: Write failing permission and concurrency tests**

覆盖：

- owner/admin 可更新、删除、恢复任意流水。
- editor 可更新、删除、恢复自己创建的流水。
- editor 对他人流水以及 viewer 对任何流水返回 403。
- 两个相同 base version 的更新只有第一个条件 update 成功；第二个返回 409 和最新完整流水快照。
- update/delete 遇到软删除返回 409 `remoteDeleted=true`。
- restore 只命中 deleted 行并返回新版本。
- 条件 update 失败时，流水参与人和 change log 均不写入。
- 成功 update/restore 后，参与人关系和 change log 与版本更新处在同一事务。

先写 editor-own 权限样例，并以同一 fixture 添加 `ownerAndAdminCanMutateAnyTransaction`、`editorCannotMutateOthersTransaction`、`viewerCannotMutateTransaction`、`secondWriterGetsLatestSnapshot`、`remoteDeletedMutationReturnsConflict`、`restoreRequiresDeletedVersion`、`failedConditionalUpdateDoesNotReplacePeopleOrLog`：

```java
@Test
void editorCanDeleteOwnTransaction() {
    Ledger ledger = ledger(11L, "l-1");
    LedgerMember editor = member(11L, 7L, LedgerRoles.EDITOR);
    LedgerTransaction transaction = transaction(31L, "t-1", 7L, 2, null);
    when(ledgerMapper.selectOne(any())).thenReturn(ledger);
    when(ledgerMemberMapper.selectOne(any())).thenReturn(editor);
    when(transactionMapper.selectOne(any())).thenReturn(transaction);
    when(transactionMapper.update(isNull(), any())).thenReturn(1);

    try (MockedStatic<StpUtil> stp = mockStatic(StpUtil.class)) {
        stp.when(StpUtil::getLoginIdAsLong).thenReturn(7L);
        VersionMutationResp result = service.delete("l-1", "t-1", deleteReq(2));
        assertAll(
                () -> assertEquals("t-1", result.getUuid()),
                () -> assertEquals(3, result.getVersion()),
                () -> assertTrue(result.getDeleted()));
        verify(changeLogService).record(11L, "transaction", "t-1", "delete", 7L);
    }
}
```

- [ ] **Step 2: Run and confirm failure**

```powershell
mvn -Dtest=TransactionServiceConcurrencyTests test
```

Expected: current update 先比较再 `updateById`，delete 拒绝所有 editor，且没有 restore。

- [ ] **Step 3: Reuse edit permission for delete/restore**

删除当前仅调用 `canEditAnyTransaction`；改为复用 `requireEditPermission(member, transaction, userId)`，确保 editor-own 规则与编辑完全一致。

```java
private void requireEditPermission(
        LedgerMember member,
        LedgerTransaction transaction,
        Long userId) {
    if (LedgerRoles.canEditAnyTransaction(member.getRole())) {
        return;
    }
    if (LedgerRoles.EDITOR.equals(member.getRole())
            && Objects.equals(transaction.getCreatedByUserId(), userId)) {
        return;
    }
    throw new BusinessException(ErrorCode.FORBIDDEN);
}

// update, delete and restore all call this before their conditional write.
requireEditPermission(member, transaction, userId);
```

- [ ] **Step 4: Replace manual check plus unconditional update**

移除 `requireCurrentVersion()` 和内存 `version + 1` 后 `updateById` 的组合。单条 SQL 同时设置全部流水字段、`lastModifiedByUserId`、`updatedAt`、新版本，并约束 active/version：

```java
int affected = baseMapper.update(null, Wrappers.<LedgerTransaction>lambdaUpdate()
        .eq(LedgerTransaction::getId, transaction.getId())
        .eq(LedgerTransaction::getVersion, req.getVersion())
        .isNull(LedgerTransaction::getDeletedAt)
        .set(LedgerTransaction::getType, req.getType())
        .set(LedgerTransaction::getPayerPersonId, payer == null ? null : payer.getId())
        .set(LedgerTransaction::getAmount, req.getAmount())
        .set(LedgerTransaction::getCurrencyCode, currencyCode)
        .set(LedgerTransaction::getCategory, category)
        .set(LedgerTransaction::getNote, note)
        .set(LedgerTransaction::getHappenedAt, req.getHappenedAt())
        .set(LedgerTransaction::getLastModifiedByUserId, userId)
        .set(LedgerTransaction::getUpdatedAt, LocalDateTime.now())
        .set(LedgerTransaction::getVersion, req.getVersion() + 1));
```

只有 `affected == 1` 后才调用 `replacePeople` 和 `changeLogService.record`。

- [ ] **Step 5: Add delete response and restore endpoint**

```java
VersionMutationResp delete(String ledgerUuid, String transactionUuid, VersionDeleteReq req);
TransactionResp restore(String ledgerUuid, String transactionUuid, TransactionUpdateReq req);
```

新增 `POST /{transactionUuid}/restore`；删除改用 `idempotencyService.execute`。冲突快照加载软删除流水仍保留的参与人关系、付款人和创建/修改用户展示信息。

```java
@PostMapping("/{transactionUuid}/restore")
public Result<TransactionResp> restore(
        @PathVariable String ledgerUuid,
        @PathVariable String transactionUuid,
        @RequestHeader(value = "Idempotency-Key", required = false) String idempotencyKey,
        @Valid @RequestBody TransactionUpdateReq req) {
    return Result.ok(idempotencyService.execute(
            idempotencyKey,
            "POST",
            "/api/ledgers/" + ledgerUuid + "/transactions/" + transactionUuid + "/restore",
            TransactionResp.class,
            () -> transactionService.restore(ledgerUuid, transactionUuid, req)));
}

private int deleteActiveTransaction(
        LedgerTransaction transaction,
        Integer submittedVersion,
        Long userId) {
    LocalDateTime now = LocalDateTime.now();
    return baseMapper.update(null, Wrappers.<LedgerTransaction>lambdaUpdate()
            .eq(LedgerTransaction::getId, transaction.getId())
            .eq(LedgerTransaction::getVersion, submittedVersion)
            .isNull(LedgerTransaction::getDeletedAt)
            .set(LedgerTransaction::getDeletedAt, now)
            .set(LedgerTransaction::getLastModifiedByUserId, userId)
            .set(LedgerTransaction::getVersion, submittedVersion + 1)
            .set(LedgerTransaction::getUpdatedAt, now));
}

private int restoreDeletedTransaction(
        LedgerTransaction transaction,
        TransactionUpdateReq req,
        LedgerPerson payer,
        Long userId) {
    return baseMapper.update(null, Wrappers.<LedgerTransaction>lambdaUpdate()
            .eq(LedgerTransaction::getId, transaction.getId())
            .eq(LedgerTransaction::getVersion, req.getVersion())
            .isNotNull(LedgerTransaction::getDeletedAt)
            .set(LedgerTransaction::getType, req.getType())
            .set(LedgerTransaction::getPayerPersonId, payer == null ? null : payer.getId())
            .set(LedgerTransaction::getAmount, req.getAmount())
            .set(LedgerTransaction::getCurrencyCode, req.getCurrencyCode().trim().toUpperCase())
            .set(LedgerTransaction::getCategory, req.getCategory().trim())
            .set(LedgerTransaction::getNote, normalize(req.getNote()))
            .set(LedgerTransaction::getHappenedAt, req.getHappenedAt())
            .set(LedgerTransaction::getLastModifiedByUserId, userId)
            .set(LedgerTransaction::getDeletedAt, null)
            .set(LedgerTransaction::getVersion, req.getVersion() + 1)
            .set(LedgerTransaction::getUpdatedAt, LocalDateTime.now()));
}
```

- [ ] **Step 6: Run and commit**

```powershell
mvn -Dtest=TransactionServiceConcurrencyTests test
mvn test
git add src/main/java src/test/java/com/simon/ledger/service/impl/TransactionServiceConcurrencyTests.java
git commit -m "feat: make transaction lifecycle concurrency-safe"
```

## Task 8: Verify the complete API contract and migration safety

**Files:**

- Create: `simon-ledger-api/src/test/java/com/simon/ledger/concurrency/ConflictResponseContractTests.java`
- Modify: `simon-ledger-api/README.md`

- [ ] **Step 1: Add serialized JSON contract tests**

使用项目 ObjectMapper 序列化成功/冲突响应，锁定 Flutter 依赖的字段名和类型：

```java
JsonNode root = objectMapper.readTree(json);
assertEquals(409001, root.path("code").asInt());
assertEquals("transaction", root.path("data").path("entityType").asText());
assertEquals(4, root.path("data").path("remoteVersion").asInt());
assertFalse(root.path("data").path("remoteDeleted").asBoolean());
assertFalse(json.contains("passwordHash"));
```

ledger/member/person/transaction 使用真实公开响应 DTO 作为 remoteSnapshot；profile 使用专用 `ProfileConflictSnapshotResp`。避免只测试空 Map。

- [ ] **Step 2: Run focused and full verification**

Run from `D:/workplace/projects/simon-ledger/simon-ledger-api`:

```powershell
mvn -Dtest=VersionContractTests,RestExceptionHandlerTests,ConflictResponseContractTests test
mvn clean test
```

Expected: Maven `BUILD SUCCESS`，所有新增及原有测试 0 failures / 0 errors。

- [ ] **Step 3: Inspect every write path for unconditional updates**

```powershell
rg -n "updateById\(|\.update\(" src/main/java/com/simon/ledger/service/impl
rg -n "setVersion\(|getVersion\(\) \+ 1" src/main/java/com/simon/ledger/service/impl
```

逐项确认 profile、ledger、member、person、transaction 的客户端触发更新/删除/恢复没有残留无条件 `updateById`。允许的例外必须是有注释和测试的服务端派生更新（例如 profile 同步 linked person），且仍递增被更新实体版本。

- [ ] **Step 4: Validate SQL against a disposable MySQL 8 database**

按环境配置先执行 `001_init_schema.sql` 验证全新安装；再在只执行到 `003` 的现有结构上执行 `004_add_optimistic_versions.sql` 验证升级。两条路径都执行：

```sql
SHOW COLUMNS FROM user_account LIKE 'version';
SHOW COLUMNS FROM ledger LIKE 'version';
SHOW COLUMNS FROM ledger_member LIKE 'version';
SHOW COLUMNS FROM ledger_person LIKE 'version';
SHOW COLUMNS FROM ledger_transaction LIKE 'version';
```

Expected: 五张表均为 `INT NOT NULL DEFAULT 1`。不要在未知共享数据库上直接运行迁移。

- [ ] **Step 5: Update API README only where operationally useful**

记录 `004` 的执行顺序、HTTP 409 合约以及调用方必须保存成功响应新版本。不要复制整份设计稿。

在“响应和认证”末尾加入：

```markdown
账户资料、账本、成员、参与人和流水的更新、软删除与恢复都需要携带当前 `version`。成功后服务端返回递增的新版本，调用方必须立即保存。版本不一致返回 HTTP 409 / 业务码 `409001`，`data` 包含实体类型、提交版本、远端版本、远端删除状态和安全业务快照。
```

在数据库迁移列表追加：

```text
sql/004_add_optimistic_versions.sql
```

- [ ] **Step 6: Final commit**

```powershell
git add src/test/java/com/simon/ledger/concurrency/ConflictResponseContractTests.java README.md
git commit -m "test: verify full optimistic conflict contract"
git status --short --branch
```

Expected: API 工作树 clean；分支只包含本计划的原子版本、冲突和权限提交。

## Implementation handoff checklist

- [ ] 五类实体和所有公开更新/响应 DTO 都有 version。
- [ ] 所有客户端触发写入都由单条条件 SQL 保护。
- [ ] stale、remote-deleted、restore-raced 三类情况都返回结构化 HTTP 409。
- [ ] delete/leave 成功响应提供新版本并受幂等缓存保护。
- [ ] 冲突快照完整且无敏感字段。
- [ ] owner/admin/editor/viewer 权限矩阵逐项有测试。
- [ ] editor 自有流水 update/delete/restore 行为一致。
- [ ] profile 派生同步也递增 person version。
- [ ] `mvn clean test` 为最新一次真实成功输出。
- [ ] 迁移只在 disposable MySQL 8 验证后再交付部署。
