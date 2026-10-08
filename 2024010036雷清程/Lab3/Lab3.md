Lab3：Linux 日志事件分析与对照
 
学号：2024010036　姓名：雷清程
 
 
 
三、生成并查询本次实验日志
 
3.1 产生成功、失败认证记录并查询
 
在 Ubuntu 终端执行：
 
whoami
hostname -I
hostname
 
 
记录：本次使用的 Ubuntu 用户名为 ubuntu（与 Lab2 相同）。
记录：本次 SSH 连接的 Ubuntu 目标 IP 为 192.168.18.128（2026-09-18 实测确认）。
记录：本机主机名为 ubuntu（即 4W1R 中 Where 的取值）。
 
在 Windows 中重新打开一个 Git Bash 窗口，用上面的用户名和 IP 登录（出现密码提示时故意输错一次密码，看到  Permission denied, please try again.  后再输入正确密码完成登录）：
 
ssh -o PubkeyAuthentication=no ubuntu@192.168.18.128
 
 
说明：本机已配置公钥免密登录，加  -o PubkeyAuthentication=no  可禁用公钥、强制使用密码认证，才能产生本次实验需要的密码认证成功与失败记录。
 
在已登录的 Ubuntu 会话中查询认证日志：
 
sudo journalctl -u ssh --since "15 minutes ago" --no-pager
 
 
sudo grep -E "Accepted password|Failed password" /var/log/auth.log | tail -n 20
 
 
认证结果表
 
认证事件 日志时间 尝试登录的账号 来源 IP 结果关键词 日志来源 
成功认证 9 月 18 日 14:06:34 ubuntu 192.168.18.1 Accepted password journal（sshd[3792]）， sudo journalctl -u ssh  查询输出 
失败认证 9 月 18 日 14:05:50 ubuntu 192.168.18.1 Failed password journal（sshd[3792]）， sudo journalctl -u ssh  查询输出 
 
说明：来源 IP 是 Ubuntu 看到的客户端地址（Windows/Git Bash 一侧），与  hostname -I  查到的 Ubuntu 目标 IP 不同，两者作用不同。
 
SSH 认证日志
 
3.2 写入并追踪自己的日志
 
在已登录的 Ubuntu 会话中执行，写入带有本人学号和姓名的日志：
 
logger -p user.notice -t lab3_read "student_id=2024010036 name=雷清程 action=write_test result=success"
 
 
两处查询（只是读取，不会再次写入，两处应是同一次写入留下的同一条消息）：
 
sudo journalctl -t lab3_read --since "5 minutes ago" --no-pager
 
 
grep -a "student_id=2024010036" /var/log/syslog | tail -n 5
 
 
（注：直接 grep 提示 binary file matches，加  -a  强制按文本处理即可正常显示）
 
两处查询结果对照
 
项目 记录 
journal 中是否查到 是： Sep 18 14:16:05 ubuntu lab3_read[3992]: student_id=2024010036 name=雷清程 action=write_test result=success  
/var/log/syslog 中是否查到 是： 2026-09-18T14:16:05.389300+08:00 ubuntu lab3_read: student_id=2024010036 name=雷清程 action=write_test result=success  
两处记录有哪些共同字段或正文 同一标签 lab3_read、同一主机 ubuntu、时间一致（14:16:05），正文完全相同： student_id=2024010036 name=雷清程 action=write_test result=success  
两处输出的主要区别 journal 使用短时间格式  Sep 18 14:16:05 ，不带年份与时区，附带进程号  [3992] ；syslog 使用ISO格式，包含年份、时区+08:00与毫秒，不显示进程号。二者存储格式不同，但保存的是同一条日志消息。 
 
同一日志的两套查询结果
 
 
 
四、完成三份事件分析
 
4.1 一条自定义日志： /var/log/syslog 
 
获取命令：grep -a "student_id=2024010036" /var/log/syslog | tail -n 5
日志原文：2026-09-18T14:16:05.389300+08:00 ubuntu lab3_read: student_id=2024010036 name=雷清程 action=write_test result=success
 
 
4W1R 根据本人原始日志填写 
When 什么时候 2026 年 9 月 18 日 14:16:05（+08:00 即北京时间；该日志自带年份和时区） 
Where 在哪里 主机 ubuntu 
Who 谁 标签 lab3_read 写入日志；正文标识本人雷清程，学号2024010036 
What 做了什么 使用 logger 工具向本机日志系统写入一条 write_test 测试消息 
Result 结果如何 正文标记 result=success；journal 和 syslog 均可查询到该日志，证明写入成功 
 
用一两句话解释这个事件：
 
2026 年 9 月 18 日 14 时 16 分 05 秒，本人在 ubuntu 主机上通过 logger 写入带有自己学号、姓名的测试日志，标记执行结果为 success。同一条消息同时保存在 journal 和 /var/log/syslog，正文一致但时间展示格式不同，体现 journald 和 rsyslog 两套日志系统的存储差异。
 
4.2 一条 SSH 认证记录： /var/log/auth.log 
 
获取命令：sudo grep -E "Accepted password|Failed password" /var/log/auth.log | tail -n 10
（注：只筛密码认证，过滤掉 publickey 免密记录）
日志原文：2026-09-18T14:05:50.357694+08:00 ubuntu sshd[3792]: Failed password for ubuntu from 192.168.18.1 port 50989 ssh2
 
 
4W1R 根据本人原始日志填写 
When 什么时候 2026 年 9 月 18 日 14:05:50（+08:00 即北京时间；该日志自带年份和时区） 
Where 在哪里 主机 ubuntu 
Who 谁 记录程序 sshd（进程号3792）；尝试登录账号 ubuntu；来源IP 192.168.18.1（Windows客户端地址） 
What 做了什么 客户端尝试使用密码进行SSH登录认证 
Result 结果如何 日志标记 Failed password，本次密码认证失败 
 
用一两句话解释这个事件：
 
2026 年 9 月 18 日 14 时 05 分 50 秒，来自 192.168.18.1 的客户端尝试使用 ubuntu 账号密码登录虚拟机，密码输入错误导致认证失败，sshd 将该事件记录在 auth.log。该记录是本次实验人为输错密码产生，并非真实网络攻击。
 
4.3 一条软件包状态记录： /var/log/dpkg.log 
 
先安装指定软件 htop：
 
sudo apt update
sudo apt install -y htop
 
 
查询 dpkg.log 中 htop 相关的状态记录，选取其中一条：
 
grep "htop" /var/log/dpkg.log | tail -n 10
 
 
实际日志来源（使用替代来源时说明原因）：本人 Ubuntu 虚拟机的 /var/log/dpkg.log
获取命令：grep "htop" /var/log/dpkg.log | tail -n 10
日志原文：2026-09-18 13:49:39 status installed htop:amd64 3.3.0-4build1
 
 
4W1R 根据本人原始日志填写 
When 什么时候 2026 年 9 月 18 日 13:49:39；该日志未提供时区 
Where 在哪里 记录取自本人 Ubuntu 虚拟机的 /var/log/dpkg.log 
Who 谁 记录工具为 dpkg；日志不记录操作人的账号 
What 做了什么 记录 htop 软件包的安装状态 
Result 结果如何 状态为 installed，代表软件包安装完成；单条记录无法区分是首次安装还是升级操作 
 
用一两句话解释这个事件：
 
2026 年 9 月 18 日 13 时 49 分 39 秒，dpkg 软件包管理器记录 htop 软件包状态为 installed，代表安装流程结束。dpkg.log 会记录软件解压、配置、安装等一系列中间状态，最终更新为 installed。
 
 
 
五、知识问答
 
systemd-journald 与 rsyslog 各负责什么？结合 3.2 节的结果，解释它们为什么可以同时保留同一条日志。
 
填写：systemd-journald 收集内核、系统服务、应用程序输出的日志，保存为二进制文件，使用 journalctl 读取；rsyslog 接收日志消息，按照规则分类，输出为 /var/log 下的文本日志文件，例如 syslog、auth.log。应用程序发送日志消息时，消息先交给 journald，journald 再转发消息给 rsyslog，两套系统各自存储一份副本。3.2 中 logger 写入的测试消息，在 journal 和 syslog 中都能查到，正文完全一致，只是存储格式不同，说明同一条日志被两套系统分别保存。
 
SSH 提示  Failed password  能证明什么，不能证明什么？请结合本次记录回答。
 
填写：可以证明：在该时间点，有来自指定IP的连接，尝试使用对应账号进行密码登录，并且本次密码校验失败。不能证明：登录操作者是谁、失败的根本原因、是否属于恶意攻击。本次实验我手动输入错误密码，同样产生 Failed password 日志。因此单凭这一条记录，无法判定是黑客暴力破解，用户输错密码等正常场景也会产生该日志。