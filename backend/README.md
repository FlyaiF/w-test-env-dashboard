# env-dashboard backend

> Status: current
> Scope: Spring Boot backend

后端保存共享目录、资源与加密凭证，执行版本采集，提供 HTTP 接口和客户端更新分发。
领域和代码归属见[上下文地图](../CONTEXT-MAP.md)。客户端与后端分别部署。

## 运行与验证

需要 Java 21 和 Maven；以下命令在仓库根目录执行：

```bash
./scripts/dev_backend.sh run
mvn -f backend/pom.xml verify
mvn -f backend/pom.xml -Pprobe-drivers verify
```

本地脚本使用 `local` profile（H2、Oracle 兼容模式和示例数据）。健康检查为
`http://localhost:8080/actuator/health`。完整验证范围见[开发指南](../docs/guides/development.md)。

生产使用 `prod` profile，必须设置 `ORACLE_JDBC_URL`、`ORACLE_USERNAME`、
`ORACLE_PASSWORD`、`ACCESS_SECRET_KEY`；配置定义见
[application-prod.yml](src/main/resources/application-prod.yml)。发布 jar 必须启用
`probe-drivers`，以包含采集所需的 Oracle、Dameng、OceanBase 驱动。

```bash
java -jar backend/target/env-dashboard-backend-<version>.jar --spring.profiles.active=prod
```

先将 `<version>` 替换为实际产物版本，并在环境中设置上述变量。该命令说明启动入口，
不代表已完成目标生产环境的切换验收。

## 维护入口

- 通用配置：[application.yml](src/main/resources/application.yml)、[本地配置](src/main/resources/application-local.yml)。
- Schema：[Flyway migrations](src/main/resources/db/migration)；已应用的迁移保留，新变化添加后续迁移。
- 旧数据导入：[脚本](../scripts/import_tenvinfo.sh)，默认 dry-run，`--apply` 才写入；规则见
  [ADR-0004](../docs/adr/0004-greenfield-schema-retire-tenvinfo.md)、[ADR-0007 修订](../docs/adr/0007-migration-leaves-role-unspecified.md)、[ADR-0008](../docs/adr/0008-migrate-and-surface-brokered-credentials.md)。
- 更新包配置与发布：[客户端更新指南](../docs/guides/client-update.md)。
