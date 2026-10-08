# Lab3：Linux 日志事件分析与对照

本实验承接 [Lab2：Linux 日志认识与查询](../Lab2/Lab2.md)，继续使用同一台 Ubuntu 虚拟机。开始前应能通过 SSH 登录 Ubuntu，并能读取 journal、`/var/log/syslog` 和 `/var/log/auth.log`。

本次重点是根据原始记录解释事件，并观察同一条自定义消息在 journal 与文本日志中的保存情况。Lab3 单独填写报告、单独提交 PR。

---

## 一、实验目标与完成顺序

将本文件复制到自己的“学号姓名”文件夹下，保存为 `Lab3/Lab3.md`，并在 `Lab3/` 中创建 `imgs/` 目录。**填写区和图片引用都在对应任务旁边，每做完一项就就地记录。**

| 任务 | 完成内容 | 操作与填写位置 |
| :--- | :--- | :--- |
| 学习分析方法 | 用 4W1R 区分时间、位置、主体、动作和结果 | 第二节 |
| 取得真实日志 | 查询本人的成功、失败认证；写入自定义日志并对照两处结果 | 3.1、3.2 节 |
| 解释三个事件 | 各分析一条自定义日志、SSH 认证记录和软件包状态记录 | 第四节 |
| 简短总结 | 回答 2 道简答题 | 第五节 |

**必做成果：认证结果表、两处日志对照表、3 份完整分析、2 道简答题、2 张截图。** 分析所需的前两条记录直接取自第三节，不必反复生成；第三题先安装指定软件 `htop` 产生软件包状态记录，安装失败时按题目提示改选内核记录。

选读内容不要求执行、填写或额外截图。遇到问题时查阅第七节，完成后按第八、九节核对文件和截止时间。

---

## 二、用 4W1R 读懂一个事件

4W1R 用五个问题解释事件：什么时候（When）、在哪里（Where）、谁（Who）、做了什么（What）、结果如何（Result）。先找原文中的依据，再组织成自己的说明。

先看一条 SSH 密码认证失败的**格式示例**。报告中要换成自己查询到的真实记录：

```text
Sep  8 10:11:04 ubuntu sshd[1204]: Failed password for student from 192.168.80.1 port 50219 ssh2
```

这类文本通常按“时间、主机、程序、消息正文”排列。`sshd` 是 SSH 服务端程序，`[1204]` 表示进程号；冒号后面的文字说明发生了什么。

| 4W1R 问题 | 从哪里找 | 本例怎样填写 |
| :--- | :--- | :--- |
| When 什么时候 | 开头的时间 | 9 月 8 日 10:11:04；该显示未提供年份和时区 |
| Where 在哪里 | 时间后面的主机名 | 主机 `ubuntu` |
| Who 谁 | 程序名，以及正文中的账号和来源地址 | `sshd`（进程号 1204）记录；连接来源为 `192.168.80.1`，尝试使用的账号为 `student` |
| What 做了什么 | 消息正文 | 尝试用密码登录 SSH |
| Result 结果如何 | 正文中的结果词 | 这次密码认证失败，依据是 `Failed password` |

**人话解释**：9 月 8 日 10:11:04，来自 192.168.80.1 的连接尝试用 student 账号和密码登录 ubuntu 主机，这次密码认证失败了。

实际阅读时，再注意五点：

1. **只填写有依据的信息。** 缺少的字段写“该日志未提供”，不要自行补上年份、用户名或失败原因。如果时间显示为 `2026-09-08T10:11:04+08:00`，则已经包含年份和时区，可以直接按实际记录填写。
2. **4W1R 是分析框架，不是每条日志都天然带齐五个字段。** 依据仍然只有这一行原文：原文里有就填，没有就写“该日志未提供”。已经确知、但来自日志之外的信息可以另加说明（例如“从本人 Ubuntu 虚拟机的 `/var/log/dpkg.log` 取得”），但不要补猜年份、用户或原因。
3. **Who 可以是用户、程序或服务。** 软件安装、内核和服务日志不一定有远程用户或来源 IP；Result 也可能只是“已解包”“服务已启动”等状态。Who 里通常同时出现两类信息：**记录这条日志的程序**，以及**事件里涉及的主体**（账号、来源地址、写入者等）。日志里有谁就写谁，不必硬找“真正的操作者”。
4. **Where 里的主机名来自本机。** 这类日志中，时间后面紧跟着的就是**写下这条日志的那台机器的主机名**。在自己虚拟机上，它的值就是 `hostname` 命令的输出：安装时填的计算机名是什么，这一格就是什么。**报告里要填自己的实际主机名，不要照抄格式示例中的 `ubuntu`**——那只是 Ubuntu 安装时默认建议的计算机名。
5. **把结果与原因分开，也把 Who 和 What 分开。** `Failed password` 能说明这次密码认证失败，不能单凭这一行判断是谁在操作、为什么失败，或是否发生了入侵。Who 是参与事件的主体，What 是这个主体做了什么，不要把同一句话填进两格。

接下来要接触 journal 和文本文件两个查询入口，先把这几个名字的关系理清：

```text
程序 / 服务 / 你执行的命令
          │
          ▼
   systemd-journald ──────> 二进制 journal ──────> journalctl 查询
          │
          └── 部分消息 ────> rsyslog ────> /var/log/syslog
                                          /var/log/auth.log
                                          （文本文件，用 grep、tail 查看）
```

`journal`、`journald`、`rsyslog`、`syslog`、`auth.log` 这几个名字看起来很像，但本实验不要求掌握完整的日志架构，只要求观察一件事：**同一次事件能从不同入口查到。** 3.1 和 3.2 节就是从 journal 和文本文件两侧分别去看同一件事，两者为什么能保留同一条日志，在第五节第 1 题里回答。

完成分析时，保留“获取命令 → 日志原文 → 4W1R 表格 → 人话解释”。第四节只要求分析 3 个事件，查询方法、阅读提示和填写表格都在各题旁边；其他日志格式的读法放在第六节，供选读。

---

## 三、生成并查询本次实验日志

本实验直接生成所需的 SSH 认证记录和自定义日志，避免依赖 Lab2 的旧日志。

### 3.1 产生成功、失败认证记录并查询

使用完成 Lab2 时的 Ubuntu 虚拟机。先在 **Ubuntu 终端**查看用户名：

```bash
whoami
```

> 记录：本次使用的 Ubuntu 用户名为 ___xdj___。

再查看当前 IP：

```bash
hostname -I
```

> 记录：本次 SSH 连接的 Ubuntu 目标 IP 为 ___192.168.156.128___。

再确认本机主机名，第二节 4W1R 中的 Where 就填这个值：

```bash
hostname
```

> 记录：本机主机名为 ___xdj-VMware-Virtual-Platform___（即 4W1R 中 Where 的取值）。

然后在 Windows 中**重新打开一个 Git Bash 窗口**，将下面的用户名和 IP 换成刚才的真实值：

```bash
ssh student@192.168.80.128
```

出现密码提示时，只故意输入一次错误密码；看到 `Permission denied, please try again.` 后，输入正确密码完成登录。这样会在本次实验中生成失败和成功认证记录。本步骤使用本人账号，完成一次失败记录即可。

**在已登录的 Ubuntu 会话中查询认证日志**

先查询最近 15 分钟的 SSH journal 记录：

```bash
sudo journalctl -u ssh --since "15 minutes ago" --no-pager
```

`sudo` 用于读取系统日志，`-u ssh` 指定 SSH 服务，`--since "15 minutes ago"` 指定时间范围，`--no-pager` 表示直接输出。（服务单元名不一致、筛不出结果时，见第七节的备用查询。）

再查询文本认证日志：

```bash
sudo grep -E "Accepted|Failed password" /var/log/auth.log | tail -n 20
```

`grep -E` 按扩展正则表达式筛选；引号内的 `|` 表示“或者”，匹配 `Accepted` 或 `Failed password`。引号外的 `|` 是管道，把结果交给 `tail -n 20`，只保留最后 20 行。

核对用户名、时间和来源 IP，找到本人成功与失败认证记录。**日志中 `from` 后的来源 IP 是 Ubuntu 看到的客户端地址；刚才查到的虚拟机 IP 是本次连接的目标地址，两者作用不同。**

```text
Windows / Git Bash                          Ubuntu 虚拟机
  192.168.80.1  ──────── SSH 连接 ────────>  192.168.80.128
                                                   │
                                                   ▼
                             journal 与 auth.log 里：
                             sshd[1204]: ... from 192.168.80.1
                             （客户端地址，写在日志正文里）

  刚才 hostname -I 查到的 192.168.80.128
  （Ubuntu 自己的地址，填在 ssh 命令的 @ 右边）
```

两个地址不一样是正常的：一个是发起连接的 Windows，一个是接受连接的 Ubuntu。`from` 后面是前者，`hostname -I` 查到的是后者。

**在此填写本人认证结果**，注明所依据的日志来源。可以从两处输出中选取同一次成功和同一次失败认证进行核对，原始日志也可用于 4.2 节的分析。

| 认证事件 | 日志时间 | 尝试登录的账号 | 来源 IP | 结果关键词 | 日志来源 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| 成功认证 |2026-09-17 16:34:56 |xdj | 192.168.156.1|Accepted password |/var/log/auth.log |
| 失败认证 |2026-09-17 16:34:38 |xdj |192.168.156.1 |Failed password |/var/log/auth.log |

保存 `imgs/lab3_ssh_auth.png`，保留 journal 与 `auth.log` 的查询命令及本人成功、失败记录。两处输出**合起来**能辨认本人一次成功认证和一次失败认证即可，不要求每一处都同时出现两条记录。

![SSH 认证日志](imgs/lab3_ssh_auth.png)

接下来继续使用这个已登录 Ubuntu 的 SSH 会话完成 3.2 节。

### 3.2 写入并追踪自己的日志

将“你的学号”和“你的姓名”替换为真实信息：

```bash
logger -p user.notice -t lab3_read "student_id=你的学号 name=你的姓名 action=write_test result=success"
```

`logger` 将这条测试消息发送给本机日志系统，通常没有终端输出。接下来通过查询确认它是否被保存。

> **注意**：正文里的 `action=write_test` 和 `result=success` 是**你自己写在双引号里的文本**，不是日志系统作出的判断。日志里出现 `result=success`，只说明有人写下了这几个字符，不代表系统验证过任何事——日志里的字段不等于系统认可的事实。这一点在 4.1 节会用到。

| 命令部分 | 含义 |
| :--- | :--- |
| `logger` | 向本机日志系统发送消息 |
| `-p user.notice` | `-p` 指定 `facility.priority`；`user` 是普通用户程序类别，`notice` 是“值得注意但不代表故障”的级别 |
| `-t lab3_read` | `-t` 指定 tag，日志中会以 `lab3_read` 作为程序标签，便于精确查询 |
| 双引号中的内容 | 日志正文；空格分隔的 `key=value` 字段便于人和程序识别 |

先通过 journald 查询：

```bash
sudo journalctl -t lab3_read --since "5 minutes ago" --no-pager
```

再通过 rsyslog 文本文件查询：

```bash
sudo grep "student_id=你的学号" /var/log/syslog | tail -n 5
```

**`logger` 只执行一次。** 上面两条命令都只是“读取”日志，不会再次写入任何内容；所以两处出现的应该是**同一次写入**留下的同一条消息，而不是各写了一次。

两处应出现正文相同的记录，但显示格式和附带字段可能不同。先核对学号、姓名、时间与正文，再比较两条输出的共同点和不同点。

**在此填写两处查询结果的对照**：

| 项目 | 你的记录 |
| :--- | :--- |
| journal 中是否查到 |是 |
| `/var/log/syslog` 中是否查到 |是 |
| 两处记录有哪些共同字段或正文 |ab3_read，student_id=2024010038 name = 许定佳 action=write_test result=success，主机名称一致 |
| 两处输出的主要区别 |journal 是本地中文时间格式，附带进程 PID；syslog 是 ISO 标准时间，没有 PID。journal 是 systemd-journald 的日志，syslog 是 rsyslog 写入的文本日志。 |

保存 `imgs/lab3_dual_pipeline.png`，在同一张截图中保留 `logger` 命令、journal 和 syslog 两处查询结果，结果必须包含本人学号姓名。

![同一日志的两套查询结果](imgs/lab3_dual_pipeline.png)

> **知识点｜为什么写成 key=value**
> `student_id=20260001 action=write_test result=success` 这种“键=值”写法叫结构化日志：机器好解析，人也好读。即使只用 `grep` 搜索，字段名也比一整句自然语言更容易定位。

两套体系为什么能记录同一事件，在第五节第 1 题中解释。

#### logger 参数补充（选读）

以下是常见变体，供理解参数时参考。省略 `-p` 时通常使用 `user.notice`：

```bash
logger -t lab3_read "message=test"
```

指定 `user.err`，可以写入一条 err 级别测试消息：

```bash
logger -p user.err -t lab3_read "result=failed"
```

加 `-s`，可以在写入日志的同时把消息显示在当前终端：

```bash
logger -s -p user.notice -t lab3_read "message=test"
```

`-s` 表示同时写到标准错误；是否保存成功仍需通过查询确认。这些变体仅供参考，本次只需完成前面的 `notice` 消息写入和两处查询。

---

## 四、完成三份事件分析

**本节只需完成下面 3 题。** 前两题使用第三节取得的 SSH 认证记录和自定义日志；第三题再找一条软件包状态记录。其他日志不要求逐项检查、补写缺失说明或另做分析。

每题保留获取命令和原文，填写一张 4W1R 表，再用一两句话解释事件。缺少的字段写“该日志未提供”，不要补猜年份、用户或失败原因。格式示例仅用于理解，答案应来自本人的实际日志。本节不另要求截图。

填写时把 Who 和 What 分开：**Who 是参与事件的主体**（记录日志的程序、账号、来源地址或写入者），**What 是这个主体做了什么**。例如 Who 写 `lab3_read`，What 写“写入一条测试消息”，不要两格都写同一句话。

### 4.1 一条自定义日志：`/var/log/syslog`

直接选用 3.2 节中本人写入的一条 `lab3_read` 日志。已有原文时不用重查；需要重新获取时，把“你的学号”换成真实学号再执行：

```bash
sudo grep -F "student_id=你的学号" /var/log/syslog | tail -n 5
```

先找时间、主机名、程序标签和消息正文。`lab3_read` 是自己指定的日志标签，不是 Linux 用户名；正文中的学号、姓名用于标识这条测试记录。`action=write_test` 和 `result=success` 分别是自己写入的测试动作和结果标记，不是系统自动作出的成功判定。

**格式示例：自定义日志（lab3_read）**

下面这行格式示例展示 syslog 中这类记录的读法，报告中的表格要换成自己查到的真实记录：

```text
Sep  8 10:15:32 ubuntu lab3_read[2310]: student_id=20260001 name=张三 action=write_test result=success
```

| 4W1R 问题 | 本例怎样填写 |
| :--- | :--- |
| When 什么时候 | 9 月 8 日 10:15:32；该显示未提供年份和时区 |
| Where 在哪里 | 主机 `ubuntu` |
| Who 谁 | 自己指定的标签 `lab3_read`（进程号 2310）写入；正文中标识的本人姓名为张三，学号 20260001 |
| What 做了什么 | 向本机日志系统写入一条 `write_test` 测试消息 |
| Result 结果如何 | 正文写明 `result=success`，这是自己写入的测试标记，需结合两处查询均能查到来印证 |

**人话解释**：9 月 8 日 10:15:32，本人在 ubuntu 主机上用 `logger` 写入一条学号为 20260001 的测试消息，正文标记结果为 success。

**本题填写：**

```text
获取命令：sudo grep -a "student_id=2024010038" /var/log/syslog | tail -n 5
日志原文：Sep 17 16:53:46 ubuntu lab3_read[2310]: student_id=2024010038 name=许定佳 action=write_test result=success
```

| 4W1R | 根据本人原始日志填写 |
| :--- | :--- |
| When 什么时候 |9 月 17 日  16:53:46 ；日志未记录年份与时区 |
| Where 在哪里 |主机 ubuntu |
| Who 谁 |标签`lab3_read`（进程号 2310）写入；正文标识姓名许定佳，学号 2024010038 |
| What 做了什么 |使用 logger 命令向本机系统日志写入一条 write_test 测试消息 |
| Result 结果如何 |日志正文标记`result=success`，journal 与 syslog 两处日志都可以查询到这条记录 |

**用一两句话解释这个事件：**

> 填写：9 月 17 日  16:53:46 ，本人在 ubuntu 主机上使用 logger 命令写入一条学号 2024010038 的测试日志，日志标记执行结果为 success。

### 4.2 一条 SSH 认证记录：`/var/log/auth.log`

直接选用 3.1 节中本人 SSH 成功或失败的一条记录，只分析其中一条即可。已有原文时不用重查；需要重新获取时再执行：

```bash
sudo grep -E "Accepted|Failed password|sudo" /var/log/auth.log | tail -n 30
```

核对记录中的账号、时间和来源地址，选择自己的事件。`Accepted password` 表示密码认证成功，`Failed password` 表示这次密码认证失败。填写 Who 时区分“记录程序 `sshd`”和“尝试登录的账号”；来源 IP 不能单独证明实际操作者的身份。

模式中同时列出 `sudo`，是因为前面用 `sudo` 查日志也会在 `auth.log` 里留下记录。本题只选本人的 SSH 认证记录（`Accepted password` 或 `Failed password`），`sudo` 行忽略即可。

**本题填写：**

```text
获取命令：sudo grep -a -E "Accepted|Failed password" /var/log/auth.log | tail -n 20
日志原文：2026-09-17T16:34:38.233514+08:00 xdj-VMware-Virtual-Platform sshd[4003]: Failed password for xdj from 192.168.156.1 port 3417 ssh2
```

| 4W1R | 根据本人原始日志填写 |
| :--- | :--- |
| When 什么时候 |2026-09-17 16:34:38，时区 + 08:00 |
| Where 在哪里 |目标主机：xdj-VMware-Virtual-Platform；登录来源 IP：192.168.156.1 |
| Who 谁 |记录程序 sshd；尝试登录账号 xdj |
| What 做了什么 |从 192.168.156.1 发起 SSH 登录，尝试对 xdj 账号进行密码认证 |
| Result 结果如何 |Failed password，本次 SSH 密码认证失败 |

**用一两句话解释这个事件：**

> 填写：2026 年 09 月 17 日 16:34:38，IP 地址 192.168.156.1 的客户端向虚拟机 xdj-VMware-Virtual-Platform 发起 SSH 登录，尝试使用 xdj 账号密码登录，密码错误，认证失败。

### 4.3 一条软件包状态记录：`/var/log/dpkg.log`

前两题分析的都是登录类事件，本题换成另一种事件类型：**软件包安装事件**，用来观察 4W1R 是否同样适用于非登录类日志。要分析的对象是“一次软件包状态变化”，`htop` 只是用来制造这个事件的小工具，不需要学习或使用它。

为保证每位同学都有一条可分析的软件包状态记录，先在 Ubuntu 中安装一款指定的小工具 `htop`：

```bash
sudo apt update
sudo apt install -y htop
```

安装完成后查询 dpkg.log 中 htop 相关的状态记录，选取其中一条：

```bash
grep "htop" /var/log/dpkg.log | tail -n 10
```

**格式示例：软件包状态记录**

```text
2026-09-08 10:05:00 status installed htop:amd64 3.3.0-4build1
```

先把这行分成“时间、状态、软件包、版本”。其中 `status installed` 表示软件包处于已安装状态，`amd64` 表示软件包的处理器架构。

如果查到的记录时间是**很早以前**，说明这台虚拟机此前已经装过 `htop`，本次安装没有产生新的安装记录；此时如实注明情况，继续分析这条历史记录即可，不必反复重装。

| 问题 | 本例怎样填写 |
| :--- | :--- |
| When 什么时候 | 2026 年 9 月 8 日 10:05:00；该日志未提供时区 |
| Where 在哪里 | 该日志未提供主机名；可以另注“从本人 Ubuntu 虚拟机的 `/var/log/dpkg.log` 取得” |
| Who 谁 | 记录工具为 `dpkg`；该日志未提供执行操作的用户账号 |
| What 做了什么 | 记录 `htop` 软件包的状态 |
| Result 结果如何 | 状态为 `installed`，即已安装；仅凭这一行不能判断此前执行的是首次安装还是升级 |

**人话解释**：9 月 8 日 10:05，软件包管理工具记录了 `htop` 已安装的状态。这一行没有说明是哪位用户执行的操作。

如果读到的是 `status unpacked`，只能写“已解包”，不能写成“安装已完成”。结果要按自己那条日志中的状态词填写。

如果 `htop` 安装失败或查询不到对应记录，先执行 `sudo apt update` 再重试；仍不成功时，用一句话说明情况，改选下面命令查到的一条内核消息即可：

```bash
sudo journalctl -k -b -n 30 --no-pager
```

`-k` 筛选 journal 中的内核消息。Who 往往是内核或驱动，Result 可能是“设备已识别”“链路已连接”等状态；在下方注明实际来源。

**本题填写：**

```text
实际日志来源（使用替代来源时说明原因）：/var/log/dpkg.log
获取命令：grep "htop" /var/log/dpkg.log | tail -n 10
日志原文：2026-09-17 17:21:14 status installed htop:amd64 3.3.0-4build1
```

| 4W1R | 根据本人原始日志填写 |
| :--- | :--- |
| When 什么时候 |2026-09-17 17:21:14 |
| Where 在哪里 |主机：xdj-VMware-Virtual-Platform |
| Who 谁 |dpkg 包管理程序，操作用户 xdj |
| What 做了什么 |使用 dpkg 工具完成 htop 软件包（版本 3.3.0-4build1）的安装配置 |
| Result 结果如何 |status installed，htop 软件包成功安装 |

**用一两句话解释这个事件：**

> 填写：2026 年 09 月 17 日 17:21:14，在 xdj-VMware-Virtual-Platform 虚拟机上，通过 dpkg 包管理器完成 htop 软件包的安装，软件最终状态为 installed，安装成功。

---

## 五、知识问答

每题用一至三句话回答，无需另外做实验。

1. systemd-journald 与 rsyslog 各负责什么？结合 3.2 节的结果，解释它们为什么可以同时保留同一条日志。

   > 填写：systemd-journald 是 systemd 自带日志服务，收集内核、服务等日志，存为二进制 journal 日志；rsyslog 是传统 syslog 服务，接收日志并输出文本日志到`/var/log`目录。日志消息会同时发送给两者，因此同一条日志会被分别保存。

2. SSH 提示 `Failed password` 能证明什么，不能证明什么？请结合本次记录回答。

   > 填写：Failed password 可以证明：来自对应 IP 的客户端尝试使用该账号登录，输入的密码错误，本次 SSH 密码认证失败。
不能证明：该 IP 对应的真实操作者身份，无法确定是不是账号本人在操作。

---

## 六、其他日志格式的阅读方法（选读）

**本节完全不计入本次作业的完成要求：不需要执行、不需要截图、不需要填写。** 以下内容供感兴趣时查阅。登录历史的读取方法见 [Lab2](../Lab2/Lab2.md) 第四节；工具或数据缺失时可跳过。

#### apt 的操作历史与过程输出

**操作历史：`/var/log/apt/history.log`**

```bash
sudo less /var/log/apt/history.log
```

按 `G` 到末尾，按 `q` 退出。读取同一次操作的完整段落；原文没有结束时间时，不要补写。

**格式示例：一次 apt 安装操作**

这个文件通常用多行记录一次操作，应保留从 `Start-Date` 到 `End-Date` 的同一段内容，不要只截取一个软件包名：

```text
Start-Date: 2026-09-08  10:04:30
Commandline: apt install htop
Requested-By: student (1000)
Install: htop:amd64 (3.3.0-4build1)
End-Date: 2026-09-08  10:05:01
```

| 问题 | 本例怎样填写 |
| :--- | :--- |
| When 什么时候 | `Start-Date` 是开始时间，`End-Date` 是结束时间：2026 年 9 月 8 日 10:04:30 至 10:05:01；该日志未提供时区 |
| Where 在哪里 | 该日志未提供主机名；可另注日志的取得位置 |
| Who 谁 | `Requested-By` 中的 `student`，括号中的 `1000` 是用户 ID；记录工具为 `apt` |
| What 做了什么 | `Commandline` 中的 `apt install htop`，即请求安装 htop 工具 |
| Result 结果如何 | 有 `Install` 安装清单和结束时间；是否安装成功还应对照 `dpkg.log` 的最终状态或 `apt/term.log` 的输出 |

**人话解释**：用户 student 发起了安装 htop 的操作，这段记录列出了软件包和操作起止时间。确认安装结果时，还要查看软件包状态或安装过程输出。

`Commandline` 记录的是**执行的命令**，`Requested-By` 才记录**发起操作的用户**。如果实际记录没有 `Requested-By`，Who 中的用户账号就写“该日志未提供”；仅出现 `End-Date` 也不能直接写成“安装成功”。

**过程输出：`/var/log/apt/term.log`**

```bash
sudo less /var/log/apt/term.log
```

结合 `Log started`、`Log ended` 的时间和具体软件包输出阅读。单独一行过程输出，或仅有结束时间，不能证明整个安装成功。

#### 文本内核日志：kern.log

```bash
sudo tail -n 30 /var/log/kern.log
```

主要查看内核、驱动、硬件等消息。文件不存在时，也可用 `journalctl -k` 查询 journal 中的内核记录；两者是不同来源，不要把它们记成同一个文件。

#### journal 的详细字段

```bash
sudo journalctl -n 1 -o verbose --no-pager
```

`-o verbose` 显示最近一条记录的详细字段。`_SYSTEMD_UNIT` 是所属服务单元，`_COMM` 是进程名，`_PID` 是进程号；`MESSAGE` 是正文。**`PRIORITY` 只表示严重程度，不能单独证明操作成功或失败。**

不同记录包含的字段可能不同。查看同一条记录的实际内容，不要把不同事件的字段拼在一起。

#### nginx 的访问日志（本机已安装时）

如果本机已安装 nginx，并且保存了访问记录，可以查看：

```bash
sudo tail -n 20 /var/log/nginx/access.log
```

客户端地址对应 Who，请求方法和路径对应 What，HTTP 状态码对应 Result。例如 200 表示请求成功响应，404 表示未找到请求的资源。

没有安装 nginx，或没有这个文件时，直接跳过。无需安装软件、制造访问记录或写缺失说明。

---

## 七、常见问题与排错

| 现象 | 处理方法 |
| :--- | :--- |
| SSH 提示 `Connection refused` | 在 Ubuntu 中用 `systemctl is-active ssh` 检查服务，用 `ss -lnt` 检查 22 端口；确认输入的是当前虚拟机 IP |
| 故意输入错误密码后提示 `Permission denied` | 这是本实验要产生的一次失败记录；接着输入正确密码。正确密码也失败时，核对用户名、键盘输入法和密码 |
| `journalctl -u ssh` 没有对应记录 | 确认刚才已连接到本机，核对系统时间，必要时将时间范围扩大到 `--since "2 hours ago"`；仍无结果时改用下方的备用查询 |
| 读取文本日志提示 `Permission denied` | 在读取命令前加 `sudo`，不要修改系统日志权限 |
| `syslog` 或 `auth.log` 不存在 | 检查 rsyslog；按 [Lab1 操作手册](../Lab1/操作手册.md) 修复后再完成必做任务 |
| `logger` 后立刻搜索不到 | 等 1～2 秒后再查，核对标签为 `lab3_read`，学号姓名使用本人的真实信息 |
| `htop` 安装失败、dpkg.log 查不到记录，或查到的记录日期很早 | 先执行 `sudo apt update` 再重试安装；记录日期很早说明此前已安装过，按 4.3 节如实注明后继续分析即可；仍不成功时改用一条内核日志，并注明原因 |
| 选读日志或工具缺失 | 直接跳过，不要求补装工具或补交说明 |

**`journalctl -u ssh` 筛不出结果时的备用查询**

`-u ssh` 是按服务单元名筛选，单元名不一致的环境可能查不到记录。改用下面的命令按关键字筛选全部 journal，效果相同：

```bash
sudo journalctl --since "2 hours ago" --no-pager | grep -E "sshd|Accepted|Failed password"
```

使用备用查询时，在报告的日志来源处注明实际使用的命令。

更多 SSH 连接排错方法可查阅 [Lab2](../Lab2/Lab2.md) 第五节。

---

## 八、截图与提交要求

本次单独提交 **1 份 Markdown 报告和 2 张截图**。

| 操作位置 | 截图必须体现的内容 | 文件名 |
| :--- | :--- | :--- |
| 3.1 节 | journal 与 `auth.log` 中本人成功、失败认证记录及查询命令（两处输出合起来有两条记录即可） | `lab3_ssh_auth.png` |
| 3.2 节 | 含本人学号姓名的 `logger` 命令，以及 journal、syslog 两处查询结果 | `lab3_dual_pipeline.png` |

- 使用电脑截图功能，文字清晰可读，严禁手机拍摄屏幕。
- 截图应显示命令和对应输出，并能辨认本人账号或学号姓名。
- 可合理拼图或裁剪无关区域，但不能裁掉命令、时间或关键结果。
- 使用本人实验结果，截图中不得出现密码、私钥或访问令牌。
- 图片保存在 `imgs/`，文件名、扩展名和大小写与表格一致。

提交前确认自己的文件夹结构为：

```text
学号姓名/
└── Lab3/
    ├── Lab3.md
    └── imgs/
        ├── lab3_ssh_auth.png
        └── lab3_dual_pipeline.png
```

检查第三节的认证和对照结果、第四节的 3 份分析，以及第五节的 2 道简答题。每份分析都应保留获取命令、日志原文、4W1R 和简短解释；选读内容无需填写。

打开 `Lab3.md`，确认两张图片能够显示，再按仓库 README 的流程单独提交 Lab3。PR 标题为 `[学号姓名]Lab3作业提交`，Lab2 仍使用自己的报告和 PR。

---

## 九、截止时间

**暂定：2026 年 9 月 24 日 23:59:59（北京时间）**

请在截止前创建 Lab3 的 PR 并完成最后一次推送。提交时间按仓库 `README.md` 第 4 节规定，以最后一次推送到 PR 的时间计算。
