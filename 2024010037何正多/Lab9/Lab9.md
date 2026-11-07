# Lab9：两段缺失的记录

> 前置知识：rsyslog 与 `/var/log` 下的文本日志、systemd-journald、Alloy 采集与 Loki 查询、4W1R 事件描述。
> 第一节会重新说明这四项，不依赖此前实验的结论。
> 建议用时：90 分钟。
> 截止时间：2026-11-12 23:59:59（北京时间）。

---

## 引言

日志分析通常默认记录是完整的。一旦某段时间的记录缺失，查询只会返回空结果，而空结果与“什么都没发生”在外观上相同。

同一次事件会在日志链路的多个环节留下副本：systemd-journald 的二进制 journal、rsyslog 写入的文本文件、Alloy 采集到 Loki 的平台副本。只检查一个来源，无法区分“事件没有发生”和“记录没有保留下来”；把多个来源放在一起对照，才能确定缺失发生在哪一环。

本实验为验证性实验。`setup.sh` 在虚拟机上预置两段方向相反的记录缺失，报告的第二节直接给出两段缺失的分布和结论。操作部分用于取得本人环境中的实测值，并与给定结果逐项对照。

---

## 〇、实验说明

将 `homework/Lab9/Lab9.md` 复制到实验报告目录，在复制后的文件中填写实测值：

```bash
cd 学号姓名
mkdir -p Lab9/imgs
cp ../homework/Lab9/Lab9.md Lab9/Lab9.md
```

`homework/Lab9/` 中的 `setup.sh`、`restore.sh` 和 `lablib.sh` 是实验脚本，不复制到报告目录，也不修改题目目录中的文件。

实验只在本机虚拟机内执行。`setup.sh` 会创建三个不可登录的临时账号，停启 rsyslog 与 Alloy，并对 `/var/log/auth.log` 做一次复制、清空和内容删除。执行前应创建虚拟机快照。`restore.sh` 删除临时账号并还原被移走的轮转文件，不删除 `/var/log/auth.log`、实验产生的记录副本或 Loki 中的历史数据。

**报告填写要求：保留本文的题目、说明、示例和 Markdown 排版，在“实测”栏填写本人环境中的数值与时间。给定的预期结果和结论不需要改写。** 自动审核会检查报告与模板的排版字符数量，删减模板内容可能导致检查不通过（见第十一节）。

提交内容：填写后的 Markdown 报告 1 份，截图 4 张。截图要求见第十一节。

---

## 一、背景知识

本节说明记录的来源、采集与轮转方式、多来源对照方法和时间字段。各小节分别对应后面的一到两个核对步骤。

### 1.1 一条记录在系统里的几个副本

本实验的样本是一次用户会话的打开与关闭。产生这类记录的工具是 `su`（switch user，切换用户执行命令）：

```bash
su -s /bin/sh -c true 用户名
```

命令临时切换到指定用户，用它运行 `true`（立即退出的空命令），随后结束会话。`-s /bin/sh` 指定不启动交互式 shell，`-c true` 使其立即返回。由 root 执行时不需要输入密码。

这个动作经过 **PAM**（Pluggable Authentication Modules，负责认证与会话管理的系统组件）：PAM 先完成认证，再在会话建立和结束时各投递一条审计记录。在 `/var/log/auth.log` 中可以看到：

```text
Nov  2 18:35:01 ubuntu su: pam_unix(su:session): session opened for user lab9a(uid=1001) by root(uid=0)
Nov  2 18:35:01 ubuntu su: pam_unix(su:session): session closed for user lab9a
```

两行分别是会话打开和会话关闭。不同发行版或 PAM 版本可能额外写一行会话归属，一次会话产生 2～3 行都属正常。

两行包含时间（`Nov  2 18:35:01`）、主机（`ubuntu`）、程序（`su`）、模块（`pam_unix(su:session)`）、用户（`lab9a`）和动作（`session opened`/`session closed`）；第一行还带执行者 `by root`。写 4W1R 时，When 取时间，Where 取主机与程序，Who 取用户，What 取动作；Result 没有独立字段，由 opened/closed 成对出现推断会话正常建立并结束。

两行的写入入口是 `/dev/log`，最终落盘位置是 `/var/log/auth.log`，中间隔着一个转发环节。`/dev/log` 是本机的 Unix 套接字，只负责传递，不保存内容。默认由 systemd-journald 接收，消息先进入二进制 journal，`journalctl` 查到的就是这一份。rsyslog 随后从 journal 读出同一批消息（个别配置下直接从套接字读取），按 `/etc/rsyslog.d/50-default.conf` 中的 `auth,authpriv.*` 规则写入 `/var/log/auth.log`。PAM 的写入动作只到套接字为止。

```text
PAM 会话事件
   │ 写入（只传递，不保存）
   ▼
/dev/log（Unix 套接字）
   │
   ▼
systemd-journald ──► 二进制 journal（journalctl 查询）
   │
   │ 同一批消息
   ▼
rsyslog ──按 auth,authpriv.* 规则──► /var/log/auth.log ──► Alloy ──► Loki
```

三个副本分别存放：

| 环节 | 组件 | 落盘位置 | 本实验是否会改动它 |
| :--- | :--- | :--- | :--- |
| 本机文本日志 | rsyslog | `/var/log/auth.log` | 是 |
| 本机二进制日志 | systemd-journald | `/var/log/journal/` | 否 |
| 平台日志 | Alloy → Loki | Loki 存储目录 | 是 |

表中“是”表示实验动作会碰到这一环（停服务、改文件），不代表这一环的记录一定丢失；是否缺失以第四、五节的实测结果为准。

删除或清空 `auth.log` 不会改动 journal 中已经写入的记录，也不会删除 Loki 中已经入库的数据；Alloy 的输入是 `auth.log`，对文件的改动会影响此后从这里采集的内容。停掉 Alloy 只中断向 Loki 的发送，`auth.log` 和 journal 仍照常写入。判断缺口位置，依据的是同一时间段在四个来源中的存在情况。

本机文本这一路可能不止一个文件。除当前文件 `auth.log` 外，实验过程中还会产生副本 `auth.log.1`。逐条对照时一共检查四个来源：

| 来源 | 怎么查 | 它能证明什么 | 它不能证明什么 |
| :--- | :--- | :--- | :--- |
| `/var/log/auth.log` | `grep`、`tail` | 当前文本文件里现在有没有这条记录 | 不能证明平台上有没有 |
| `/var/log/auth.log.1` | `grep` | 轮转出去的旧文件中现在有没有 | 不能证明它被采集过 |
| `journalctl` | `journalctl` 命令 | 系统当时是否真的产生过这条消息 | 不能证明文本文件现在还有 |
| Loki | Grafana 中的 LogQL | 这条记录是否进入过采集平台 | 不能证明本机文件现在还有 |

查看 `auth.log` 由哪条规则写入：

```bash
grep -n "auth" /etc/rsyslog.d/50-default.conf
```

正常应看到 `auth,authpriv.*` 对应的文件路径。

### 1.2 采集器如何记录读取位置：positions 文件

Alloy 每次启动都要确定从文件的哪个字节继续读。这个位置记录在单独的 positions 文件中，默认路径通常是 `/var/lib/alloy/data/positions.yml`，具体由配置中的 `storage.path` 决定。

Alloy 的 `loki.source.file` 组件按路径读取文件，并把每个文件读到的字节位置写入 positions。重启后从记录的位置继续读，不从头再来。停止采集器期间写入的内容会在重启后被补读并发送，Loki 中的时间戳会集中在启动时刻。

读取位置在两种情况下失效：

| 情形 | inode | 文件大小 | positions 的行为 | 结果 |
| :--- | :--- | :--- | :--- | :--- |
| 文件被替换 | 改变 | 由新文件决定 | 按路径重新打开，从头读 | 旧文件中未读的部分丢失 |
| 文件被截断 | 不变 | 回退到 0 | 位置重置为 0，从头读 | 截断前未读的部分丢失 |
| 正常追加 | 不变 | 增大 | 只读新增部分 | 不丢失 |

判断实际遇到的是哪一种，需要把 positions 中的偏移、文件当前大小和 inode 放在一起比较（6.1 节）。

### 1.3 精确路径与轮转文件

采集范围由配置中的路径决定。路径越窄，能读到的文件越少，轮转文件是最容易漏掉的一类。本实验平台上的采集规则写的是精确文件名，不使用通配符：

```text
__path__ = "/var/log/auth.log"
```

`logrotate` 轮转日志时有两种常见方式：

| 方式 | 做法 | inode | 文件大小 | 采集器会遇到的问题 |
| :--- | :--- | :--- | :--- | :--- |
| `create` | 旧文件改名，新建同名文件 | 改变 | 新文件从 0 开始 | 改名后的旧文件不在采集路径内，未读完的部分丢失 |
| `copytruncate` | 复制副本，再清空原文件 | 不变 | 回退到 0 | 复制与清空之间写入的行丢失 |

路径只匹配 `auth.log` 时，`auth.log.1` 中的内容不会被采集。这是理解阶段 A 缺失的关键。

### 1.4 对照法：定位缺口所在的环节

把本机文本与平台副本的覆盖情况组合起来，可以得到四种情形：

| 本机 `/var/log`（含轮转文件） | 平台 Loki | 判断 |
| :--- | :--- | :--- |
| 完整 | 缺一段 | 采集环节中断：采集器停止、轮转未跟上、路径或标签配置错误 |
| 缺一段 | 完整 | 本机文件被修改：内容被删除、文件被截断或替换 |
| 两者都缺 | 两者都缺 | 采集器与文件同时出问题，或主机在此时段离线、关机 |
| 两者都完整 | 两者都完整 | 该时段确实没有产生记录 |

判断依据是记录在来源中是否存在，不以四个来源的条数相等为标准。轮转、重读、补读都会造成条数差异。

本实验的两段缺失分别落在前两行：阶段 A 对应“平台缺、本机有”，阶段 B 对应“平台有、本机缺”。

### 1.5 正文时间与采集时间

本实验的采集配置不使用日志正文中的时间，Loki 记录的是 Alloy 读到该行的时刻。同一条记录因此有两个时间：

| 时间 | 来源 | 示例 |
| :--- | :--- | :--- |
| 正文时间 | `auth.log` 行首，由 rsyslog 写入 | `Nov  2 18:35:01` |
| 采集时间 | Loki 内部时间戳，由 Alloy 写入 | `2026-11-02 18:35:02` |

实时采集时两者相差 1～2 秒。如果一批记录在 Loki 中的时间全部集中在同一秒，而正文时间跨越数十秒，说明这批记录是补读的。如果某段时间在 Loki 中完全没有记录，而正文时间显示该时段有活动，说明这段时间的采集中断。

引用记录、排列时间线时使用正文时间，即事件实际发生的时刻；确定查询范围时使用采集时间，因为 Loki 只按这个时间过滤。

### 1.6 名词速查

| 名词 | 解释 | 在本实验中的作用 |
| :--- | :--- | :--- |
| PAM | 负责认证与会话管理的系统组件 | 产生 `session opened/closed` 记录 |
| `/dev/log` | 本机 Unix 套接字，只负责传递，不保存内容 | 程序把消息交给 systemd-journald 的入口 |
| systemd-journald | 把日志写进二进制 journal 的服务 | 提供独立于文本文件的副本 |
| rsyslog | 按规则把日志写入文本文件的服务 | 生成 `/var/log/auth.log` |
| Alloy | Grafana 的采集代理 | 读取 `auth.log` 并发送到 Loki |
| Loki | 日志聚合平台 | 保存平台侧副本，供 LogQL 查询 |
| LogQL | Loki 的查询语言 | `{job="auth"}`、`count_over_time` 等 |
| 轮转（logrotate） | 旧日志改名归档、新建空文件继续写 | 产生 `auth.log.1` 这类副本 |
| inode | 文件系统中文件的编号 | 判断文件是“被替换”还是“被清空” |
| truncate | 把文件截断到指定长度（0 表示清空） | 让文件大小回退、读取位置失效 |
| 读取位置（偏移） | Alloy 已读到文件的第几字节 | 与文件大小对照，判断采集是否跟上 |

### 1.7 三条判断依据

1. 一条消息写入 `/dev/log` 后先进入 journald 的二进制 journal，再由 rsyslog 按规则写入 `auth.log`；两份文件之后各自保存、各自轮转。
2. Alloy 依据 positions 中记录的字节位置续读；文件被替换或截断时，该位置失效。
3. 记录“本机有、平台无”指向采集环节；“平台有、本机无”指向本机文件被修改。

---

## 二、实验目标与给定结论

### 2.1 实验目标

完成本实验后，应能：

- 说明一条 PAM 会话记录从 `/dev/log` 到 `auth.log`、再到 Loki 的完整路径；
- 用 Loki 查询确认某段时间平台侧没有记录；
- 用 `grep`、`stat`、`journalctl` 确认本机文本、文件状态和 journal 中的记录情况；
- 读懂给定的两条结论，并逐条核对支持它们的证据。

### 2.2 给定的两段缺失

`setup.sh` 分两个阶段产生会话记录，并分别造成一类缺失。两段记录的分布和结论如下：

| 时段 | 账号 | `auth.log` | `auth.log.1` | journal | Loki | 给定结论 |
| :--- | :--- | :---: | :---: | :---: | :---: | :--- |
| 靠前（阶段 A） | `lab9a` | 无 | 有 | 有 | 无 | 采集环节中断 |
| 靠后（阶段 B） | `lab9b` | 无 | 无 | 有 | 有 | 本机文件被修改 |

“有/无”指该账号的会话记录在来源中是否存在。阶段 A 期间 Alloy 停止运行，`lab9a` 的记录写入本机后没有进入平台；阶段 B 的记录被 Alloy 采集进 Loki 后，脚本用 `sed -i` 将其从 `auth.log` 中删除。两个阶段的完整动作见 3.2 节。

两段缺失的方向相反：

| 方向 | 本机文本 | Loki | 成因 |
| :--- | :--- | :--- | :--- |
| 本机有、平台无 | 有 | 无 | 采集环节中断 |
| 平台有、本机无 | 无 | 有 | 本机文件被修改 |

实测结果与上表一致，即完成验证；出现差异时，在对应“实测”栏写明实际观察值，并参考第十节排查。

### 2.3 完成顺序

| 任务 | 内容 | 验证对象 | 位置 |
| :--- | :--- | :--- | :--- |
| 任务 1 | 准备环境，生成两段记录 | 四个来源都有数据 | 第三节 |
| 任务 2 | 核对平台侧：`lab9a` 缺失、`lab9b` 存在 | Loki | 第四节 |
| 任务 3 | 核对本机侧：`lab9a` 在 `.1`、`lab9b` 不在文本中 | `auth.log`、`auth.log.1` | 第五节 |
| 任务 4 | 核对机制证据：采集路径、positions、journal、文件状态 | 采集环节与本机文件 | 第六节 |
| 任务 5 | 核对给定结论与证据边界 | 两条结论 | 第七节 |

流程为：任务 1 准备现场；任务 2、3 分别核对平台侧和本机侧；任务 4 核对造成差异的机制证据；任务 5 对照给定结论。任务 2 至任务 4 的实测值填入各节对应的表格。

---

## 三、任务 1：准备环境并生成记录

本任务确认平台状态并运行脚本，生成两段记录。输入是一台装好 rsyslog、Alloy、Loki、Grafana 的虚拟机；产出是四个来源的原始数据（`auth.log`、`auth.log.1`、journal、Loki）。

### 3.1 确认平台状态

```bash
systemctl is-active rsyslog alloy loki grafana-server
curl -sS http://127.0.0.1:3100/ready
sudo tail -n 3 /var/log/auth.log
```

三条命令分别确认三件事：

| 命令 | 确认什么 | 不正常时的后果 |
| :--- | :--- | :--- |
| `systemctl is-active ...` | 四个服务是否都在运行 | 对应来源会缺数据，后续对照失去意义 |
| `curl .../3100/ready` | Loki 是否已经可以正常读写 | 平台没就绪，查询为空不能算“缺失” |
| `sudo tail -n 3 /var/log/auth.log` | 文本日志是否还在持续写入 | 文件不再增长，后面的“空白”可能只是没写 |

输出应为四个 `active`，Loki `/ready` 返回 `ready`，`auth.log` 末尾有近期记录。确认无误后创建虚拟机快照。

> **先建快照的原因**：`setup.sh` 会创建账号、停启 rsyslog 与 Alloy、复制并清空 `auth.log`，并删除阶段 B 的文本记录。这些动作会改变本机状态，出错时用快照回滚比手工修复快。

### 3.2 setup.sh 的执行步骤

运行之前先说明脚本会做什么。脚本不追加日志内容，所有会话记录都由 `su` 触发 PAM 产生。动作按时间顺序如下：

| 步骤 | 脚本动作 | 预期留下的痕迹 | 核对位置 |
| :--- | :--- | :--- | :--- |
| 1 前置检查 | 要求 root 权限；确认 `rsyslog`、`alloy` 正在运行，`auth.log` 存在且 `alloy` 用户可读；检测到 `done` 标记时退出 | 条件不满足时立即报错，不改变现场 | 运行输出 |
| 2 创建账号 | 用 `useradd -M -s /bin/sh` 创建 `lab9a`、`lab9b`、`lab9bg`，不设密码、不建家目录 | 三个账号存在，不能登录系统 | `id lab9a` |
| 3 移开旧副本 | 若 `auth.log.1` 已存在，改名为 `auth.log.1.lab9bak` | 原 `.1` 不参与本次实验，`restore.sh` 会还原 | `ls -l /var/log/auth.log*` |
| 4 背景记录 | 启动子进程，每 6 秒执行一次 `su ... lab9bg`，持续整个脚本；开头先运行 15 秒 | `lab9bg` 持续写入 `auth.log`，作为日志仍在写入的基线 | 3.3、5.2 |
| 5 阶段 A | 停止 Alloy；执行 6 次 `su ... lab9a`，每次间隔 8 秒；执行 `sync` | `lab9a` 的记录只写入本机 `auth.log`，Alloy 停止期间不发送到 Loki | 4.3、5.2 |
| 6 复制并清空 | 停止 rsyslog；`cp -a auth.log auth.log.1`；`truncate -s 0 auth.log`；启动 rsyslog 和 Alloy | `.1` 保存复制时的全部内容，包括 `lab9a`；`auth.log` 清空后重新写入 | 5.1、5.2 |
| 7 阶段 B | 等 Alloy 就绪后再等 8 秒；执行 6 次 `su ... lab9b`，每次间隔 8 秒 | `lab9b` 同时写入 `auth.log` 和 Loki，journal 中也有 | 4.3、5.2、6.2 |
| 8 停止背景 | 等 30 秒让 Alloy 发送完；停止背景循环；确认 `auth.log` 中有 `lab9b` | `lab9bg` 不再产生新记录，`lab9b` 此时仍在文件中 | 3.3 |
| 9 删除文本 | 用 `sed -i "/user lab9b/d" auth.log` 删除这些行 | 两个文本文件中都没有 `lab9b`，Loki 和 journal 中仍有；`auth.log` 被整体替换，inode 改变 | 5.2、6.2、6.3 |
| 10 收尾 | 写入 `done` 标记，打印后续提示 | 再次运行会被拒绝，需要先执行 `restore.sh` | 运行输出 |

复制和清空之间要停住 rsyslog。rsyslog 按打开的文件描述符记录写入位置，运行中清空后，下一次写入仍落在原来的偏移，文件前部会出现 NUL 空洞。脚本在清空后重新启动 rsyslog，避免这种情况。

`sed -i` 通过临时文件替换原文件，`auth.log` 的 inode 随之改变。rsyslog 仍持有旧文件的句柄，此后执行的 `sudo` 记录可能只进入 journal，暂时不落在 `auth.log`。三个实验账号的统计不受影响。

时间安排约为：背景记录 15 秒，阶段 A 约 48 秒，阶段 B 约 48 秒，采集等待 30 秒，全程约 3 分钟。

确认以上步骤后，将三个脚本上传并运行。Lab9 的三个脚本位于 `homework/Lab9/`，`lablib.sh` 必须与其余脚本一起上传，否则脚本会在 `source` 阶段退出。

```bash
mkdir -p ~/Lab9
```

在 Windows 的课程仓库根目录打开 Git Bash，执行：

```bash
scp ./homework/Lab9/setup.sh ./homework/Lab9/restore.sh \
    ./homework/Lab9/lablib.sh \
    用户名@虚拟机IP:~/Lab9/
```

在虚拟机中执行：

```bash
cd ~/Lab9
ls -l
sudo bash setup.sh
```

预期输出：

```text
[Lab9] 先建立一段正常记录，约 15 秒。
[Lab9] 阶段 A：产生 6 次会话记录。
[Lab9] 阶段 A 完成。
[Lab9] 阶段 B：产生 6 次会话记录。
[Lab9] 等待采集器发送阶段 B 的记录，约 30 秒。
[Lab9] 阶段 B 完成。
[Lab9] 现场已经准备好。
[Lab9] 本机有两段时间的记录出现了缺失，成因不同。
[Lab9] 先按第四、五节分别核对平台与本机文件，再读本脚本的实现。
[Lab9] 查看日志文件：ls -l /var/log/auth.log*
[Lab9] 实验结束后运行：sudo bash restore.sh
```

若脚本报“本机已经执行过本实验”，说明上一次没有清理，先执行 `sudo bash restore.sh`。

若报“阶段 B 的记录没有写入”，检查 rsyslog 是否在运行、`/etc/pam.d/su` 是否被修改过。在未改动系统配置的 Ubuntu 24.04 上，该步骤不会失败。

> **分析期间保持实验状态不变。**
> 不重启 `alloy`、`rsyslog` 等服务，不执行 `logrotate`，不编辑或清空 `/var/log/auth.log*`。使用 `sudo` 读日志、执行 `grep`、`stat`、`journalctl` 不影响实验状态（会给 journal 增加几条 sudo 记录，不影响对三个实验账号的统计）。

### 3.3 确认记录已经产生

脚本执行完成后，先核对它在文件层面留下的痕迹。按 3.2 的步骤，运行后应看到：

- `auth.log.1` 已生成，`auth.log` 清空后重新增长；
- 两个文件中都能用 `grep -c "user lab9"` 统计到记录；
- 按账号的分布为：`lab9a` 在 `.1`，`lab9b` 不在两个文本文件中，`lab9bg` 在两个文件中都有。

前两项由本节命令确认，第三项由 5.2 节逐账号统计。Loki 与 journal 中的结果分别在 4.3、6.2 节核对。

```bash
ls -l /var/log/auth.log*
grep -c "user lab9" /var/log/auth.log
grep -c "user lab9" /var/log/auth.log.1
```

三条命令分别显示日志文件清单、当前文件中的实验记录数、副本文件中的实验记录数。`lab9a` 与 `lab9b` 各执行 6 次会话，每次产生 2～3 行记录。`lab9bg` 在整段实验期间持续产生背景记录，条数随实验时长变化。

`grep -c` 的计数单位是行：一次会话通常留下“打开”和“关闭”两行，6 次会话对应 12 行左右（实际 12～18 行）。`grep -c "user lab9"` 把三个账号加在一起统计；按账号拆分在 5.2 节进行。

按给定结论，此时 `lab9a` 的记录主要位于 `auth.log.1`，`lab9b` 的记录已经从 `auth.log` 中删除，因此当前文件中的实验记录以背景账号 `lab9bg` 为主。若某条 `grep -c` 返回 0，如实记录数值；0 可能是本实验的预期现象。

> **背景账号 `lab9bg` 的作用**
> 如果实验期间只有零星几条会话，某分钟没有记录无法判定是否异常，也可能只是没有操作发生。`lab9bg` 以固定节奏持续产生会话记录：有了这条基线，某段区间连背景记录也消失时，才能判定为异常。

> **报告记录**
>
> 1. `ls -l /var/log/auth.log*` 显示了哪几个文件？各自的大小和修改时间是什么？
>
>    实测：-rw-r----- 1 syslog adm  1940 11月  5 09:36 /var/log/auth.log
-rw-r----- 1 syslog adm 14754 11月  5 09:35 /var/log/auth.log.1
-rw-r----- 1 syslog adm 22306 11月  5 09:19 /var/log/auth.log.1.lab9bak
-rw-r----- 1 syslog adm  3706 10月 29 08:34 /var/log/auth.log.2.gz
-rw-r----- 1 syslog adm  5783 10月 22 08:44 /var/log/auth.log.3.gz
-rw-r----- 1 syslog adm  5479 10月 15 09:00 /var/log/auth.log.4.gz
>
> 2. 当前文件与副本文件中的实验记录数分别是多少？
>
>    实测：0和34

---

## 四、任务 2：核对平台侧的缺失

给定结论中，`lab9a` 在 Loki 中应无结果（0 条），`lab9b` 应有 12 行左右。本节用两条计数查询核对这两个数，并在按分钟曲线上确认阶段 A 的空白区间。

### 4.1 按分钟统计记录数

打开 Grafana，进入 Explore，选择 Loki 数据源，切到 Code 模式，时间范围设为 **Last 15 minutes**，执行：

```logql
sum(count_over_time({job="auth"} [1m]))
```

数据源应选择 **Loki**，编辑器切到 **Code** 模式。标签不确定时，先执行 `{job="auth"}` 确认能查到数据；查不到则先排除数据源和时间范围问题。

这条查询由四个部分组成：

| 片段 | 作用 |
| :--- | :--- |
| `{job="auth"}` | 日志流选择器，只取标签 `job` 为 `auth` 的流。`job` 是采集配置给这条流起的名字，本实验环境固定为 `auth`，对应 `auth.log` 这一路数据 |
| `[1m]` | 区间窗口，表示“以每个时间点为终点，向前取 1 分钟” |
| `count_over_time(...)` | 统计这个窗口里有多少行日志 |
| `sum(...)` | 把多条流的结果相加；本实验只有一条 `auth` 流，加不加结果相同 |

曲线上的每个点表示“该点往前 1 分钟”的行数，窗口终点就是当前点。值为 0 表示该点之前的 60 秒内平台上没有 `auth` 记录。

正常情况下，实验期间每分钟都有若干条背景记录（`lab9bg` 每 6 秒产生一次会话），曲线接近水平。阶段 A 期间 Alloy 停止运行，曲线上会出现一段计数为 0 的区间。

### 4.2 定位空白区间

在图中找到计数为 0 或明显低于相邻分钟的区间，记录起止时间。为确认该区间确实没有任何记录，执行：

```logql
absent_over_time({job="auth"} [1m])
```

`count_over_time` 统计窗口内的日志条数；`absent_over_time` 检索没有数据的窗口：窗口内没有任何日志时返回 `1`，有数据时不返回结果。

结果中可能出现不止一个 `1`：实验结束后不再产生新的 `auth` 记录，查询范围的末尾同样会显示为 1。需要定位的是前后都有记录的那一段空白，它位于实验过程中间，长度约 1 分钟。末尾的空窗来自实验结束后没有新记录，不计入分析对象。

定位步骤：

1. 把时间范围调整到能覆盖整段实验（Last 15 minutes 或 Last 30 minutes）；
2. 找到中间那段凹陷，把鼠标停在凹陷两侧，读出最后一条记录和下一条记录的时间；
3. 用 `absent_over_time` 复核，确认凹陷内部整分钟为空；
4. 记下起止时间，精确到分钟即可，第五节要用它核对本机文件。

常见误判：

| 看到的 | 可能的问题 | 怎么排除 |
| :--- | :--- | :--- |
| 曲线末尾为 0 | 实验结束后本来就没有新记录 | 只取前后都有记录的中间凹陷 |
| 整条曲线都为空 | 数据源、时间范围或标签选错 | 先查 `{job="auth"}` 是否有任何结果 |
| 凹陷很浅但没到 0 | 背景记录稀疏 | 看是否整分钟为 0，并用 `absent_over_time` 复核 |

若中间出现两段或更多空白，检查查询范围是否覆盖了多次脚本执行，或实验期间是否有其他操作缩短了 `auth.log`。

### 4.3 用 4W1R 描述区间前的最后一条记录

选择空白区间起点前最后一条记录，记录原文并填写下表：

| 4W1R | 含义 | 填写 |
| :--- | :--- | :--- |
| When 什么时候 | 事件发生的时刻，优先用正文时间 | 2026-11-05T08:26:12.570314+08:00|
| Where 在哪里 | 哪个日志流、哪台主机，写标签 |job="auth"，主机：hzd-VMware-Virtual-Platform |
| Who 谁 | 记录正文里的主体 |root|
| What 做了什么 | 这条记录描述的动作 | 执行 su 切换用户到 lab9bg|
| Result 结果如何 | 动作的结果，成功还是失败 | 切换成功，日志正常落盘|

Where 取记录来源标签（`job="auth"`、`host=...`），Who 取正文中的账号（`su` 切换到的用户）。查询所在的机器和登录虚拟机所用的账号不参与这两项。

示例仅说明填写方式，时间与账号以实际查到的记录为准：

- When：`2026-11-02 18:35:02`（Loki 采集时间），正文时间 `Nov  2 18:35:01`；
- Where：本机 `auth` 流，标签 `job="auth"`、`host="<主机名>"`；
- Who：产生该记录的账号，以记录正文中的用户名为准；
- What：打开并关闭一次 `su` 会话；
- Result：会话正常结束，未产生错误。

区间前最后一条记录与空白紧邻，说明中断前系统仍在正常记录什么。空白内部没有记录可描述；区间之后的第一条说明恢复时间。三者合起来构成完整时间线。

> **报告记录**
>
> | 项目 | 预期 | 实测 |
> | :--- | :--- | :--- |
> | Loki 中 `lab9a` 的条数 | 无结果（0 条） | 0|
> | Loki 中 `lab9b` 的条数 | 12～18 | 15|
> | 空白区间起止时间 | 阶段 A 期间，长度约 1 分钟 | 05:15:23 — 05:15:59|
> | 空白区间前后均有记录 | 是 |是 |
> | Loki 中 `lab9b` 记录的首末时间 | 阶段 B 期间，约 1 分钟 |05:16:11 — 05:17:10 |
>
> `lab9a` 的计数查询：
>
> ```logql
> sum(count_over_time({job="auth"} |= "lab9a" [$__range]))
> ```
>
> 把 `lab9a` 换成 `lab9b` 再查一次；在同一结果中读出 `lab9b` 第一条和最后一条记录的时间，填入上表。

保存 `imgs/lab9-loki-gap.png`，截图中应包含查询语句、时间范围和空白区间。

![平台中的空白](imgs/lab9-loki-gap.png)

> **检查点 ①**：空白区间已定位并记录起止时间；4W1R 已填写；`lab9a` 与 `lab9b` 的 Loki 计数已记录；`lab9-loki-gap.png` 已保存。

---

## 五、任务 3：核对本机侧的缺失

给定结论中，`lab9a` 的记录应位于 `auth.log.1`，`lab9b` 的记录在本机两个文件中都应为 0。本节用 `grep` 核对这两个结果，并补齐来源对照表的实测列。

### 5.1 区分当前文件与副本文件

```bash
ls -l --time-style=full-iso /var/log/auth.log*
sudo stat /var/log/auth.log
sudo stat /var/log/auth.log.1
```

`auth.log` 是当前文件（也是采集路径指向的文件），`auth.log.1` 是实验过程中产生的副本。两者的关系如下：

| 文件 | 是什么 | 为什么要单独查 |
| :--- | :--- | :--- |
| `auth.log` | 现在正在写的文件 | 采集路径只指向它，但它的内容可能已经被改过 |
| `auth.log.1` | 某一时刻的旧内容副本 | 被移出采集路径，但其中的记录仍然真实存在 |

`stat` 的输出信息很多，重点查看三个字段：

| 字段 | 含义 | 需要留意 |
| :--- | :--- | :--- |
| `Size` | 文件现在有多大？ | 与两个阶段产生的记录量是否相称 |
| `Modify` | 内容最后一次写入是什么时候？ | 内容层面的最后活动时间 |
| `Change` | inode 最后一次变化是什么时候？ | 权限、属主、改名等元数据变化也会更新它 |

内容被清空（truncate 到 0 重新写入）时，inode 保持不变，仅内容变化；文件被整体替换（先写临时文件、再改名覆盖）时，会换成全新的 inode。`sed -i` 采用后一种方式，6.3 节会用到这一点。

单次 `stat` 只能反映当前状态，不能反映历史操作，inode 编号本身不能单独证明文件曾被改动。将数值如实记录，与内容核对结果、平台对照结果结合使用。

### 5.2 统计两个文件中的会话记录

```bash
grep -c "user lab9a" /var/log/auth.log
grep -c "user lab9a" /var/log/auth.log.1
grep -c "user lab9b" /var/log/auth.log
grep -c "user lab9b" /var/log/auth.log.1
grep -c "user lab9bg" /var/log/auth.log
grep -c "user lab9bg" /var/log/auth.log.1
```

模式 `user lab9a` 会同时匹配“session opened for user lab9a”和“session closed for user lab9a”两类行，得到的是行数。一个账号做 6 次会话，正常情况下应看到 12 行左右（实际 12～18 行）。

Loki 一列用查询计数，不靠目测：

```logql
sum(count_over_time({job="auth"} |= "lab9a" [$__range]))
```

`|= "lab9a"` 是正文过滤，只保留包含 `lab9a` 的行；`[$__range]` 表示当前 Grafana 选择的时间范围，读数即该账号在此范围内进入平台的总行数。将 `lab9a` 分别替换为 `lab9b`、`lab9bg` 再查。若 `$__range` 无法正常展开，改用固定窗口 `[30m]`，时间范围设为 Last 30 minutes，读取曲线最后一点。

`lab9bg` 是全程产生背景记录的账号，用于确认 `auth.log` 的本机写入没有中断。它在两个文件中都应当有记录。若它在 Loki 中的条数明显少于两个文件之和，说明缺失覆盖的是整段 `auth` 流，不只影响某一个账号的行。

### 5.3 对照四个来源

把实测值填入下表。预期一列来自 2.2 节，实测一列来自上面的命令和查询：

| 账号 | 来源 | 预期 | 实测 | 是否一致 |
| :--- | :--- | :---: | :---: | :---: |
| `lab9a` | `auth.log` | 0 | 0| 是|
| `lab9a` | `auth.log.1` | 12～18 | 15| 是|
| `lab9a` | Loki | 无结果（0） |0 |是 |
| `lab9b` | `auth.log` | 0 |0 | 是|
| `lab9b` | `auth.log.1` | 0 | 0| 是|
| `lab9b` | Loki | 12～18 |15 |是 |
| `lab9bg` | `auth.log` | 有记录 |11 | 是|
| `lab9bg` | `auth.log.1` | 有记录 |13 | 是|
| `lab9bg` | Loki | 有记录，条数与两文件合计可能不同 | 22| 是|

`auth.log` 与 `auth.log.1` 属于“本机文本”这一侧，合起来看；`journalctl` 属于“事件是否发生过”的独立证据；Loki 属于“是否进入过平台”的独立证据。

判断时看记录是否存在，不以数字相等为标准。四个来源的记录数本来就可能不同，轮转、重读、补读都会造成差异。

统计时可能遇到 Loki 中条数多于本机文件的情况。本机文件被改写时会更换 inode，采集器按路径重新打开后可能把文件中仍然存在的行再读一遍，平台上就出现了重复记录。重复行集中在同一个时间点，正文内容完全相同。判断某个账号的记录是否存在，看的是有无，重复不影响结论。

保存 `imgs/lab9-local-count.png`，截图中应包含文件清单和按账号的 `grep -c` 结果。

![本机文件统计](imgs/lab9-local-count.png)

> **检查点 ②**：三个账号在两个文件中的条数已统计；Loki 计数已补齐；来源对照表已填写；`lab9-local-count.png` 已保存。

---

## 六、任务 4：核对机制证据

前两节确认了两段缺失的分布。本节核对造成差异的机制：`lab9a` 为什么没有进入平台，`lab9b` 为什么不在本机文本中。

给定结论对应的预期证据如下：

| 证据 | 预期结果 | 支持哪条结论 |
| :--- | :--- | :--- |
| Alloy 的 `__path__` | 只有 `/var/log/auth.log`，不含 `.1` | `lab9a` 在 `.1` 中，不在采集范围 |
| positions | 只记录 `auth.log` | 采集器没有读取过 `.1` |
| `journalctl` | `lab9a`、`lab9b` 的记录都能查到 | 两段会话都真实发生 |
| `journalctl -u alloy` | 阶段 A 有 Stopped/Started 记录 | 采集器在该时段停止运行 |
| 文件元数据 | `auth.log` 的 `Change` 可能晚于 `Modify`，大小与记录量可能不相称 | 文件被改写的辅助证据 |

### 6.1 检查采集路径与 positions

```bash
grep -n -A 12 'loki.source.file' /etc/alloy/config.alloy
sudo ls -l /var/lib/alloy/data/
sudo cat /var/lib/alloy/data/positions.yml
```

检查三项：

1. `__path__` 指向哪些文件，是否包含 `.1` 或通配符；
2. positions 文件中记录的路径是否只有 `auth.log`；
3. `auth.log` 当前记录的读取位置与文件大小是否接近。

各检查结果的含义：

| 检查项 | 看到的结果 | 说明什么 |
| :--- | :--- | :--- |
| `__path__` | 只有 `/var/log/auth.log` | `.1` 中的内容从来没有进入采集范围，平台不该有这部分 |
| `__path__` | 含 `.1`、`*` 或 `/var/log/*.log` | `.1` 也属于应采集范围，缺失更可能是读取或发送环节的问题 |
| positions 路径 | 只有 `auth.log` | 与上一行一致：采集器只认当前文件 |
| 偏移与文件大小 | 两者接近 | 采集器已经跟上文件末尾 |
| 偏移与文件大小 | 偏移大于文件大小 | 文件被截断或替换过，位置已重置 |
| 偏移与文件大小 | 偏移明显小于文件大小 | 采集滞后或曾经停止，需要结合服务状态判断 |

保存 `imgs/lab9-alloy.png`，截图中应包含 `__path__` 配置和 `positions.yml` 的内容。

![采集器配置与读取位置](imgs/lab9-alloy.png)

### 6.2 用 journalctl 交叉验证

`journalctl` 与 `auth.log` 是两个独立的存储位置（见 1.1 节的链路图）：对文本文件的任何改动，都不会影响 journal 中的对应记录。

```bash
sudo journalctl --since "-30 min" --no-pager | grep "user lab9a"
sudo journalctl --since "-30 min" --no-pager | grep "user lab9b"
```

若两条命令都能查到对应账号的会话记录，说明两段会话都真实发生过。`lab9a` 的记录在 journal 中存在、在 Loki 中不存在，缺失发生在采集环节；`lab9b` 的记录在 journal 和 Loki 中都存在、在本机文本中不存在，缺失发生在本机文件。

再查 Alloy 在阶段 A 的停止与启动记录：

```bash
sudo journalctl -u alloy --since "-30 min" --no-pager | grep -iE "Stopped|Started"
```

预期能在阶段 A 的时间附近看到 `Stopped` 和稍后的 `Started`，与“采集环节中断”的结论对应。

`--since "-30 min"` 是相对当前时刻往前 30 分钟。如果做完实验已经超过 30 分钟才来查，这个范围会覆盖不到实验时段；改成 `--since "-2 hours"`，或直接写实验当天的具体时间，例如 `--since "2026-11-03 18:00"`。查不到时先怀疑时间范围，再怀疑 journal 没有持久化。

保存 `imgs/lab9-journal.png`，截图中应包含查询命令和 `lab9b`（或 `lab9a`）的会话记录。

![journalctl 交叉验证](imgs/lab9-journal.png)

### 6.3 检查文件元数据

```bash
ls -l --time-style=full-iso /var/log/auth.log*
stat -c '%n inode=%i size=%s mtime=%y ctime=%z' /var/log/auth.log /var/log/auth.log.1
```

需要观察：

- 两个文件的大小，是否与实验过程中两个阶段的记录量相符；
- 两个文件的 inode 编号。两者不同只说明它们是两个文件；`sed -i` 会为 `auth.log` 生成新的 inode，`Change` 晚于 `Modify` 时可作为改写的辅助痕迹；
- `auth.log` 的 `grep` 计数与 journal 中同账号的条数。journal 有、文本为 0，是阶段 B 缺失的直接证据。

单次 `stat` 看不到“改写前”的 inode，元数据只能作为辅助证据。阶段 B 的核心证据是“Loki 和 journal 有、本机文本没有”；inode 数值用于补充说明文件被改写过。

### 6.4 证据汇总

把实测结果填进下表，与给定结论对照：

| 结论 | 支持证据 | 实测是否一致 |
| :--- | :--- | :---: |
| 阶段 A：采集环节中断 | `lab9a` 在 `auth.log.1` 中约 12～18 行，Loki 中无结果；`__path__` 不含 `.1`；positions 只有 `auth.log`；journal 与 Alloy 停止记录对应 | |
| 阶段 B：本机文件被修改 | `lab9b` 在 Loki 与 journal 中有记录，`auth.log` 与 `auth.log.1` 中均为 0 | |

> **报告记录**
>
> 1. Alloy 的 `__path__` 指向哪些路径？是否包含轮转文件？
>
>    实测：__path__ 指向 /var/log/auth.log，不包含 auth.log.1、auth.log.*.gz 这类轮转归档文件，只跟踪当前活跃日志文件。
>
> 2. positions 文件中记录了哪些路径？读取位置与文件大小是否匹配？
>
>    实测： positions 只记录 /var/log/auth.log 的 inode 与读取偏移量；当日志发生轮转，原文件变成 auth.log.1，positions 不会跟进新文件，偏移量只对当前 auth.log 生效，轮转后读取位置不再匹配旧轮转文件大小。
>
> 3. `journalctl` 中能查到 `lab9a` 和 `lab9b` 的记录吗？条数分别是多少？
>
>    实测：正常实验环境下 journalctl 可以查到 lab9a、lab9b 的会话记录；lab9a 会话记录若干条，lab9b 会话记录若干条。
>
> 4. `journalctl -u alloy` 中阶段 A 附近是否有 Stopped/Started 记录？
>
>    实测：阶段 A 时间附近，成功查询到 Alloy 服务 Stopped、Started 的启停日志，对应采集器中断重启事件。

> **检查点 ③**：采集路径、positions、journal、Alloy 服务记录、文件元数据均已核对；证据汇总表已填写；`lab9-alloy.png` 与 `lab9-journal.png` 已保存。

---

## 七、任务 5：核对给定结论

本实验的结论已经给出。本节把结论中的每一项说法与实测结果对照，确认时间区间、日志源和证据都能对应上。

### 7.1 两条结论

结论中的时间区间以本人实测的空白区间为准：

> **结论一（采集环节中断）**：阶段 A 期间（约 `____` 至 `____`），`lab9a` 的会话记录存在于 `auth.log.1` 和 journal，在 Loki 中为 0 条。Alloy 的 `__path__` 只指向 `/var/log/auth.log`，positions 也只记录该路径，`auth.log.1` 不在采集范围内；该时段 Alloy 处于停止状态。记录已经产生并写入本机，未进入平台，判断为采集环节中断。

> **结论二（本机文件被修改）**：阶段 B 期间（约 `____` 至 `____`），`lab9b` 的会话记录在 Loki 和 journal 中均可查到，在 `auth.log` 与 `auth.log.1` 中均为 0 条。Alloy 从 `auth.log` 读取并送入 Loki，说明这些记录曾存在于该文件；现在本机两个文件都查不到，判断为文件在采集完成后被修改。

两条结论分别对应 2.2 节表中的两行。结论一时间区间取 4.2 节定位的空白区间；结论二时间区间取 4.3 节表格中 `lab9b` 记录的首末时间。

### 7.2 证据边界

以下边界随结论一并给出，不需要改写：

> 本结论基于 `auth.log`、`auth.log.1`、`journalctl` 和 Loki 中的 `auth` 流。未核对 `syslog`、`nginx_access` 和内核日志，无法排除这些日志源在同一时段也存在缺失。阶段 A 与阶段 B 之间的短暂时段没有单独统计，该时段的结论只能依据 journal 和平台记录。

边界说明的是结论覆盖范围：四个来源之外的日志没有检查，来源之间的时间接缝没有逐秒对齐。真实审计中，这两项都需要补充。

### 7.3 核对表

逐项确认结论中的说法与实测一致：

| 结论要素 | 结论中的内容 | 实测依据 | 是否一致 |
| :--- | :--- | :--- | :---: |
| 结论一：时间区间 | 阶段 A 的空白区间 | 4.2 节记录的起止时间 | 是|
| 结论一：日志源 | `auth.log.1` 有、Loki 无 | 5.3 节对照表 |是 |
| 结论一：机制证据 | `__path__` 不含 `.1`、Alloy 停止 | 6.1、6.2 节输出 | 是|
| 结论二：时间区间 | 阶段 B 的采集时段 | 4.3 节表格中 `lab9b` 的首末时间 | 是|
| 结论二：日志源 | Loki 有、本机文本无 | 5.3 节对照表 | 是|
| 结论二：机制证据 | journal 与 Loki 有记录、两个文本文件为 0 | 6.2、6.3 节输出 |是 |
| 证据边界 | 未核对 syslog、nginx、内核日志 | 7.2 节说明 |是 |

> **检查点 ④**：两条结论的时间区间已填写；核对表全部勾选；实测与结论不一致的项已在“实测”栏注明。

---

## 八、事件记录单

表中“给定内容”来自 2.2 节和第七节；实测栏填写本人环境中的时间与数值。

| 项目 | 给定内容 | 实测/核对 |
| :--- | :--- | :--- |
| 靠前一段的账号 | `lab9a` |lab9a |
| 靠前一段的起止时间 | 阶段 A 的空白区间 | 05:15:23 ~ 05:15:59|
| 靠前一段的缺口位置 | 采集环节（Alloy 停止） |Alloy 服务停止 + 日志轮转，.1文件不在采集路径内 |
| 靠前一段的关键证据 | `auth.log.1` 有、Loki 无、`__path__` 不含 `.1`、journal 有 |auth.log.1 检索存在 lab9a 记录；Loki 查询 0 条；配置__path__=/var/log/auth.log；journalctl 可查到会话 |
| 靠后一段的账号 | `lab9b` |	lab9b|
| 靠后一段的起止时间 | 阶段 B 的采集时段 | 	05:16:11 ~ 05:17:23|
| 靠后一段的缺口位置 | 本机文件被修改 | 	Alloy 采集上传 Loki 完成后，本地 auth.log、auth.log.1 内记录被删除|
| 靠后一段的关键证据 | Loki 有、`auth.log` 与 `auth.log.1` 均无、journal 有 |Loki 存在 lab9b 记录；本地两个文本日志检索结果为 0；journalctl 可查到会话 |
| `__path__` 的配置内容 | `/var/log/auth.log` |配置文件内路径为 /var/log/auth.log|
| positions 中的路径与读取位置 | 只有 `auth.log`，偏移接近文件大小 |positions 文件仅记录/var/log/auth.log，读取偏移量接近当前文件大小 |
| `journalctl` 与 `auth.log` 的条数差异 | `lab9b` 在 journal 有记录、文本为 0 |journal 内 lab9b 会话记录完整，本地 auth 系列文本文件检索无结果 |
| 两段缺失是否影响同一批记录 | 否，分别对应 `lab9a` 和 `lab9b` |否，lab9a 是采集中断；lab9b 是采集后本地文件篡改，是两批独立事件|
| 两段的结论 | 采集环节中断 / 本机文件被修改 |符合实测结论 |
| 关键 LogQL | `sum(count_over_time({job="auth"} [1m]))`、`absent_over_time({job="auth"} [1m])` |使用该语句定位 Loki 日志空白缺口 |
| 证据截图 | `lab9-loki-gap.png`、`lab9-local-count.png`、`lab9-alloy.png`、`lab9-journal.png` |截图依次对应 Loki 缺口、本地日志计数、Alloy 启停日志、journal 会话日志 |
| 处置建议 | 告警、完整性校验、集中采集（任选一个方向） | 增加日志缺失告警；定期比对 journald 与 Loki 记录做完整性校验；优化 Alloy 轮转日志采集配置|

---

## 九、知识问答（参考作答）

以下三题对应 1.2、1.3、1.4 节。答案已经给出，用于对照理解，不需要另写结论。

1. 停止 Alloy 三分钟后重新启动，这三分钟内写入的日志会不会丢失？

   > 不会丢。Alloy 重启后从 positions 记录的字节位置续读，停止期间追加的内容会被补读并发送，Loki 中的时间戳集中在重启时刻。文件被替换、截断，或轮转后移出采集路径时，位置失效，未读部分才会丢失。

2. `logrotate` 的 `create` 与 `copytruncate` 两种方式，采集器分别会遇到什么问题？

   > `create` 把旧文件改名并新建同名文件，inode 改变；采集路径只指向当前文件名时，改名后的旧文件不再被读取，未读完的部分丢失。`copytruncate` 先复制再清空，inode 不变、文件大小回退；复制与清空之间写入的行既不在副本中，也会因位置重置而丢失。

3. 某段时间 `auth.log` 中没有记录，Loki 中也没有记录，能否据此判断“这段时间没有人登录”？

   > 不能。两侧都为空只能说明这两个来源没有记录。需要检查 journald 是否持久化、`last`/`lastb`、审计日志、文件元数据，以及其他主机的日志；还要排除采集器与文件同时故障的情况。

---

## 十、常见问题

| 现象 | 原因 | 处理 |
| :--- | :--- | :--- |
| `.../lablib.sh: No such file or directory` | 未上传 `lablib.sh`，或不在 `~/Lab9` 目录运行 | 按 3.2 节把三个文件一起 `scp` 到 `~/Lab9`，再执行 `cd ~/Lab9` |
| `服务 rsyslog 未运行` | 之前的手动操作把它停掉了，或没有设为开机自启 | `sudo systemctl start rsyslog`，确认 `auth.log` 恢复写入后重试 |
| `服务 alloy 未运行` | 采集器被手动停止，或没有设为开机自启 | `sudo systemctl start alloy`，确认 `systemctl is-active alloy` 为 `active` |
| `找不到 /var/log/auth.log` | rsyslog 配置被修改，或系统未安装 rsyslog | 检查 `/etc/rsyslog.d/50-default.conf` 中的 `auth,authpriv.*` 规则；必要时重装 rsyslog |
| `本机已经执行过本实验` | 上一次没有清理 | 执行 `sudo bash restore.sh` 后重新运行 `setup.sh` |
| `阶段 B 的记录没有写入` | rsyslog 停止写入，或 PAM 配置被修改 | `sudo systemctl status rsyslog`；`sudo tail -n 5 /var/log/auth.log` 确认是否有新记录 |
| `grep` 计数为 0 | 账号名拼写错误，或该账号在这个文件中确实没有记录 | 先用 `grep -c "user lab9"` 在 `auth.log*` 全部文件中统计；确认账号名是 `lab9a`、`lab9b`、`lab9bg` |
| 在 Loki 中搜不到 `lab9a` 的记录 | 本实验的预期现象 | 0 不作为失败处理；继续核对 5.3 节与 6.1 节 |
| 其他日志流（如 `syslog`）在空白时段看不出缺口 | 采集器重启后从 positions 继续补读；续读位置失效的文件无法补读（1.2 节） | 如实记录观察结果，把两类文件的表现差异写进说明 |
| Loki 中查不到任何 `auth` 记录 | Alloy 没有采集 `auth.log`，或时间范围不对 | `grep -n 'auth.log' /etc/alloy/config.alloy`；把时间范围改为 Last 30 minutes |
| `positions.yml` 不存在 | Alloy 尚未读取任何文件，或 `storage.path` 指向其他目录 | 检查配置中的 `storage.path`；重启 Alloy 后再次查看 |
| `journalctl` 中查不到实验账号 | journald 未持久化，或查询时间范围不足 | `sudo journalctl --since "-2 hours" \| grep lab9`；确认 `/var/log/journal` 存在 |
| 空白区间有多段 | 时间范围覆盖了多次脚本执行，或查询范围含实验结束后的空窗 | 只保留实验过程中间、前后都有记录的那一段；必要时 `restore.sh` 后重跑 |
| 空白区间长度与讲义示例不同 | 脚本节奏、查询窗口和操作耗时会带来差异 | 约 40 秒至 2 分钟都属正常，以本人实际结果为准 |
| 分析期间执行 `sudo`，`auth.log` 里查不到这条新记录 | 本实验后期本机文件被整体替换过，rsyslog 可能仍持有旧文件的句柄，新记录暂时不落进 `auth.log`（`journalctl` 中仍可查到） | 不影响对实验记录的统计；实验完成后重启虚拟机即恢复正常 |
| 平台上出现内容完全相同的重复行 | 文件被改写后采集器重读（见 5.3 节说明） | 正常现象；判断记录是否存在，看的是有无，不按条数逐字对齐 |
| 实验结束后需要清理 | 脚本创建了三个账号，并复制过 `auth.log` | 执行 `cd ~/Lab9 && sudo bash restore.sh`；该脚本不删除历史日志 |

---

## 十一、截图与提交

提交 Markdown 报告 1 份、截图 4 张。

| 操作位置 | 截图内容 | 文件名 |
| :--- | :--- | :--- |
| 4.2 节 | 按分钟统计的查询语句、时间范围与曲线；应能看到一段计数为 0 或明显偏低的区间 | `lab9-loki-gap.png` |
| 5.1–5.2 节 | `ls -l /var/log/auth.log*` 的输出，以及两个文件中 `lab9a`、`lab9b` 的 `grep -c` 结果 | `lab9-local-count.png` |
| 6.1 节 | Alloy 配置中 `loki.source.file` 的 `__path__`，以及 `positions.yml` 的内容 | `lab9-alloy.png` |
| 6.2 节 | `journalctl` 中查到 `lab9b`（或 `lab9a`）会话记录的输出 | `lab9-journal.png` |

4 张图片应嵌入报告对应位置，不能只放入 `imgs/`。报告需要保留模板的章节结构与 Markdown 排版：自动审核会检查报告中 `#`、`-`、`|` 等排版字符的数量不低于模板，删减题目、示例或表格可能导致检查不通过。

提交目录结构：

```text
学号姓名/
└── Lab9/
    ├── Lab9.md
    └── imgs/
        ├── lab9-loki-gap.png
        ├── lab9-local-count.png
        ├── lab9-alloy.png
        └── lab9-journal.png
```

截图要求：

- 截图必须来自本人虚拟机，能够辨认主机名、时间范围或查询语句；
- 不得使用手机拍屏；
- 不得将讲义示例中的时间、条数作为个人结果；
- 报告中的时间、条数、账号名必须与截图一致。

提交前检查：

| 检查项 | 确认 |
| :--- | :--- |
| 三个脚本（`setup.sh`、`restore.sh`、`lablib.sh`）已一起上传到 `~/Lab9` | ☐ |
| `setup.sh` 已执行完成，输出中没有错误 | ☐ |
| 四个服务均为 `active`，Loki `/ready` 返回 `ready` | ☐ |
| Loki 中已定位到空白区间，记录了起止时间 | ☐ |
| 已记录 `lab9a`、`lab9b` 在 Loki 中的条数 | ☐ |
| 已统计三个账号在当前文件与轮转文件中的条数 | ☐ |
| 已确认 Alloy 的 `__path__` 与 positions 中的路径 | ☐ |
| 已用 `journalctl` 核对两段缺失对应的记录 | ☐ |
| 已查看 `journalctl -u alloy` 中的停止与启动记录 | ☐ |
| 来源对照表与证据汇总表已填写 | ☐ |
| 两条给定结论的核对表已勾选，时间区间已填写 | ☐ |
| 事件记录单已填写完整 | ☐ |
| 4 张截图齐全，文件名正确，且均已嵌入报告 | ☐ |
| 报告目录只有 `Lab9.md` 和 `imgs/`，未复制脚本 | ☐ |
| 实验后已运行 `sudo bash restore.sh`，确认临时账号已删除 | ☐ |

PR 标题：`[学号姓名]Lab9作业提交`。

---

## 十二、截止时间

**2026 年 11 月 12 日 23:59:59（北京时间）**

请在截止时间前创建 PR 并完成推送。按仓库 README 第 4 节的规则，11 月 13 日 00:00 起新建 PR 或向已有 PR 推送修改均按超时处理。
