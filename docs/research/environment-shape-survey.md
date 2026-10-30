# 测试环境形态调研与登记方向

> Status: snapshot
> Scope: env_viewer + backend 产品方向；真实测试环境的数据与磁盘形态
> Recorded: 2026-10-29

本文记录一次对线上目录数据和一台测试服务器的只读调研，以及由此讨论出的产品方向。
数字和进程状态是当天快照，不会自动更新；方向部分是讨论结论，不是已排期的实施清单。
已实施的部分（运行状态检测）以[上下文地图](../../CONTEXT-MAP.md)和代码为准。

## 来源

- 部署中的后端（`prod` profile，10.20.158.64:20260）：只读调用 `GET /api/environments`、
  `/api/servers`、`/api/databases`。
- 10.20.158.64 的 `ta66` 账号：只读 `ls`/`find`、读取配置文件（输出中脱敏密码）、
  `/proc/<pid>/cwd` 与 `ss -ltnp`。未修改任何文件，未调用凭证接口。
- 从开发机对 57 个组件 URL 发起不跟随重定向的 GET。

## 产品定位（与使用者确认）

- 本工具替代此前开发与 QA 共同编辑的 Excel 表。机器和服务器是大家共享的，**默认所有人都是善意的**：
  目标是防止误操作，而不是防范破坏。因此不引入登录/权限体系，优先做修改留痕、可恢复删除、
  并发编辑冲突提示，扫描结果永不自动删除或覆盖人工字段。
- “booking” 指**把服务登记进系统**，不是预约占用。核心诉求是让登记变轻。
- 三个目标：便捷访问每个环境；便捷登记环境；审视现有工具。运行状态检测是使用者长期想要的能力。

## 目录数据快照

| 事实 | 数量 |
| --- | --- |
| Environment / Server / Database | 57 / 21 / 104 |
| 每个 Environment 的 Component | 全部恰好 1 个 |
| 角色 / 版本探测 | 全部 `APP` / 全部 `DB`；GATEWAY、UI、PRIVATE_PROTO 与 HTTP、SSH_FILE、COMMAND 从未使用 |
| `listenPort` / `protocol` | 从未填写（端口只出现在 URL 中） |
| 日志位置 | 52 个均为 `/home/<login>/<目录>/…dtl-web-starter…/dtl-web.log`；5 个为空 |
| URL | 54 个为 `http://host:port/frame-layout…`，通常是 nginx 入口端口 |
| Database | 每个环境 1 个业务库 + 0–1 个中间库；104 个中 103 个只被引用一次（两套 4.0 环境共享一个中间库） |
| 版本线 | `TA6.0-TRUST` 53 个（其中 V202601 41 个），`TMS4.0` 4 个 |
| 命名 | 客户 + 主干/分支，例如 山东主干 / 山东分支 |

数据质量问题：9 个组件的 URL 主机与其运行主机不一致；“Server” 实际是“主机 + 登录账号”，
同一主机的不同账号以 `10.20.155.174-ta6` 这样的后缀挤进 host 字段；
部分环境备注里以明文记录了其他系统的账号密码（本文不复录）。

## 磁盘上的环境形态（10.20.158.64）

一个 Environment 实际是一个目录 `/home/<login>/<CODE>/`，例如 `SDZG` = 山东主干，
`JYDMZG`/`JYOBFZ` = 建元 + 达梦/OceanBase + 主干/分支。目录内有多个服务，结构统一：

```
<CODE>/<svc>/<svc>/
├── bin/start.sh  stop.sh  setenv.sh
├── config/application-prod.properties  logback-spring.xml …
├── logs/
├── <svc>.jar  <svc>.pid
```

外层目录有时带前缀，如 `dm_dtl-web-starter/dtl-web-starter`；`tmp/dtl-web-starter` 这类副本没有
`bin/start.sh`，不是服务。

| 服务 | 对应角色 |
| --- | --- |
| `trust-nginx`/`nginx` | 网关；目录 URL 通常指向它 |
| `dtl-ui-starter` | 界面 |
| `dtl-web-starter`（有时以 `zoa-bootstrap-*.jar` 运行） | 主服务；目录目前只登记它 |
| `trust-ta-local-starter`、`trust-ta-exchange-starter`、`trust-ht2p-gateway` | 专有协议 / TA 服务 |
| `trust-ops`、`trust-log-viewer-starter`、`baoguan` | 运维与辅助服务 |

结论：领域模型原本的四种角色是对的，只是手工登记成本太高，目录只记录了主服务。

### 配置即连接关系

`application-prod.properties` 记录了服务的全部对外关系：

- `server.port`；
- `spring.datasource.*`：业务库（host、service、业务用户）；
- `spring.datasource.dynamic.datasource.mid-*`：中间库（`*_view` 用户）；
- `spring.data.redis.*`；
- `spring.cloud.discovery.client.simple.instances.*.host/port`：服务之间的调用（web ↔ exchange）；
- `otel.resource.attributes.deployment.environment`：环境标签；OTel collector 位于 10.20.154.151:8081。

nginx 的 `conf/sites-available/<name>` 用 upstream 指明后端，例如山东主干：

```
upstream dtl            { server 10.20.158.64:8334; }   # dtl-web-starter
upstream dtl-ui         { server 10.20.158.64:8333; }   # dtl-ui-starter
upstream trust-ta-local { server 10.20.158.64:8069; }
listen 8092;                                            # 目录中的 URL
```

### 运行状态快照

通过 `/proc/<pid>/cwd` 可以把进程对应到安装目录。当天：KLZG 只运行界面；ZHZG、ZJZG、JYDMFZ
有安装但没有运行的服务；JYOBZG/JYOBFZ 运行的 `trust-ht2p-gateway`、JYDMZG 的 exchange 等均未登记。

对 57 个 URL 的 GET：48 个 200、2 个 401、英大主干 502（nginx 在、后端不在），
10.20.155.175 上 3 个无响应（重复测试时 3–6 个）。同一时刻目录全部显示“正常”——
那只代表版本查询成功。这促成了运行状态检测的实现。

## 讨论出的方向

### 运行状态（已实施第一步）

第一步不依赖 SSH：后端每分钟对每个组件 URL 发 GET，不跟随重定向；
<500 为运行中，5xx/拒绝连接/无响应为已停止，连接超时/无路由/未知主机为不可达。
第二步在扫描能力之后：按服务读取端口与 pid，给出“nginx 在、dtl-web 停”的粒度。

### 扫描式登记

1. 后端通过 SSH 只读扫描每个已登记的服务器账号：找出 `~/*/*/bin/start.sh` 且有 `config/` 的服务，
   读取配置、监听端口和 pid。
2. **跨服务器**：先扫描所有主机，建立 `host:port → 服务` 索引，再把 nginx upstream、discovery
   instances、datasource 解析为边；连通的服务构成候选环境，目录名只作为显示名提示。
   引用到无登录账号的主机时显示为“未登记服务器”。Windows/WebLogic 的 4.0 环境不在此形态内，保持手工。
3. 人工审阅差异后登记；之后定期重扫，发现漂移（端口变化、新增或停止的服务、换库）。

### 扫描结果的身份识别

- **服务身份 = 主机 + 安装目录**（如 `10.20.158.64:/home/ta66/SDZG/dtl-web-starter/dtl-web-starter`），
  跨重启和端口变化保持稳定；端口是属性，pid 是瞬时值。
- **环境身份由人命名**；扫描只提议、不发明。匹配信号由强到弱：已绑定的服务键 → 现有目录数据
  （日志路径前缀推出安装目录，URL 端口对上 nginx listen）→ 业务库用户（57 个业务库各用一次，
  近乎唯一；中间库会共享，不能作为键）→ 目录代码、OTel 环境标签（仅提示）。
- 重扫结果：已匹配则只更新扫描拥有的字段并展示差异；新增进入“待登记”收件箱，可指派或忽略（记住）；
  消失标记“未找到”，**从不删除**；同业务库但目录/主机不同则询问“迁移还是复制”。
- 字段归属：扫描拥有端口、库关联、运行状态、日志路径；人拥有名称、备注、服务归属哪个环境。
  扫描只写自己的字段。

### 其他待议

- 后端为扫描新增 SSH 能力，超出 ADR-0009（桌面端会话）的范围，实施前需要新 ADR。
- 单组件环境下组件表格 + 展开的交互偏重；资源清单应按数据库实例而不是登录档案组织。
- 客户 × 主干/分支 的版本矩阵、Ctrl+K 快速切换、每个环境的固定动作（打开、日志、配置、库）。
- 防误操作：修改人（设置中填写姓名，无需登录）、环境修改历史与恢复、回收站、并发编辑冲突提示。
