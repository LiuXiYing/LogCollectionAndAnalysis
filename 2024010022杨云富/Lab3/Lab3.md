# Lab3 Linux日志认证与自定义日志
学号：2024010022
姓名：杨云富

## 一、实验目的
1. 查看SSH认证日志，区分成功登录与失败登录的日志记录。
2. 使用logger命令生成自定义日志。
3. 验证同一条日志，会同时保存到syslog与journal两套日志系统。

## 二、实验环境
VMware Ubuntu虚拟机，Git Bash通过SSH远程连接Ubuntu。
### 2.2 SSH认证结果表
|日志时间|账号|来源IP|结果关键词|日志来源|
| ---- | ---- | ---- | ---- | ---- |
|2026-09-24 08:37:14|www|192.168.75.1|Failed password|/var/log/auth.log|
|2026-09-24 08:37:18|www|192.168.75.1|Accepted password|/var/log/auth.log|

## 3.1 实验环境信息
- 用户名：www
- 主机名：www-VMware-Virtual-Platform
- IP地址：192.168.75.128

执行命令：
```bash
whoami
hostname
hostname -I
新开终端进行 SSH 登录，故意输入错误密码制造失败认证；正常 SSH 登录产生成功认证记录。
执行命令查询 auth.log 和 journal 中的 ssh 认证日志：
bash
grep ssh /var/log/auth.log
journalctl -u ssh
观察结果：
/var/log/auth.log记录 SSH 登录事件，成功登录会出现Accepted password，密码错误会记录Failed password。
journalctl -u ssh读取 ssh 服务的 systemd 日志，同样捕获登录成功、失败的审计记录。


3.2 logger 自定义日志，双日志管道验证
使用 logger 生成包含本人学号姓名的日志消息，分别从 syslog、journal 查询。
bash
logger "2024010022杨云富 Lab3自定义日志测试"
grep -a "2024010022杨云富" /var/log/syslog
journalctl | grep "2024010022杨云富"
日志对照表
表格
项目	内容
journal 中是否查到	是
/var/log/syslog 中是否查到	是
两处共同字段或正文	2024010022 杨云富 Lab3 自定义日志测试
两处主要区别	syslog 为文本文件存储，journal 为二进制数据库存储；输出格式、时间展示样式略有差异
观察结果：
logger 产生的日志，会同时写入传统 syslog 文件与 systemd journal 日志库，两处都能检索到同一条日志消息，验证了双日志管道。添加-a参数可以解决 grep 识别 syslog 为二进制文件的警告。


4.1 SSH 失败登录事件（4W1R 表）
获取命令：grep ssh /var/log/auth.log
日志原文：pam_unix(sshd:auth): authentication failure; logname= uid=0 euid=0 tty=ssh ruser= rhost=192.168.75.1 user=www
表格
4W1R	内容
When（时间）	2026-09-24 08:37:14
Where（位置）	来源 IP：192.168.75.1，本机 Ubuntu 系统
Who（主体）	尝试登录账号 www
What（事件）	SSH 密码认证失败
Result（结果）	登录拒绝，记录 Failed password 审计日志
事件解释：外部主机尝试 SSH 连接本机 www 账号，输入错误密码，系统记录认证失败日志。
4.2 SSH 成功登录事件（4W1R 表）
获取命令：grep ssh /var/log/auth.log
日志原文：Accepted password for www from 192.168.75.1 port 59370 ssh2
表格
4W1R	内容
When（时间）	2026-09-24 08:37:18
Where（位置）	来源 IP：192.168.75.1，本机 Ubuntu 系统
Who（主体）	登录账号 www
What（事件）	SSH 密码认证成功
Result（结果）	成功建立 SSH 会话，session opened
事件解释：客户端输入正确密码，通过 SSH 身份验证，成功登录 Ubuntu 虚拟机。
4.3 Logger 自定义日志事件（4W1R 表）
获取命令：journalctl | grep "2024010022杨云富"
日志原文：9月 24 08:41:53 www-VMware-Virtual-Platform www[3485]: 2024010022杨云富 Lab3自定义日志测试
表格
4W1R	内容
When（时间）	2026-09-24 08:41:53
Where（位置）	本机 Ubuntu 虚拟机
Who（主体）	当前登录用户 www
What（事件）	使用 logger 生成自定义系统日志
Result（结果）	日志同时写入 syslog 与 journal 两套日志系统
事件解释：使用 logger 工具手动生成一条带学号姓名的用户自定义系统日志。
5.1
systemd-journald 负责接收 systemd 服务、程序输出的日志，保存在 journal 二进制数据库；rsyslog 将系统日志持久化写入 /var/log 下文本日志文件（syslog）。
一条消息会被 journald 捕获，同时转发给 rsyslog，所以同一条日志会同时在 journal 和 syslog 两处保留。
5.2
Failed password仅代表本次密码验证不匹配。无法证明操作人真实身份，有可能是别人尝试猜密码；失败原因只知道密码不对，不知道是输错、账号不存在等；单凭这一条日志，不能直接判定是入侵行为，需要结合更多日志综合分析。
六、实验小结
SSH 登录行为会被系统完整记录，登录审计日志可以用于溯源账号登录行为。logger 可以手动生成自定义系统日志。Linux 同时存在 syslog 和 journal 两套日志体系，同一条日志会同时进入两套系统，提供不同的日志查询方式。日志审计不能单凭单条记录下定结论，需要多条日志交叉验证。
