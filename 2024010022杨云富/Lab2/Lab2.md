# Lab2 Linux日志认识与查询实验

## 1. SSH登录验证
环境检查结果：
- Ubuntu用户名：yunfu
- 虚拟机私有IPv4地址：192.168.122.100
- SSH服务状态：active（正在运行）
- TCP 22端口：处于监听状态

Windows Git Bash SSH登录成功，登录后执行命令输出：
```bash
whoami
yunfu
hostname
ubuntu
pwd
/home/yunfu
作用：确认登录用户名、主机 IP、当前工作目录，验证 SSH 登录成功。
2. 日志盘点
表格
日志文件路径	用途	文件类型	读取命令
/var/log/syslog	系统通用日志，记录大部分系统服务运行信息	文本文件	tail -f /var/log/syslog
/var/log/auth.log	身份认证、SSH 登录、sudo 操作安全审计日志	文本文件	cat /var/log/auth.log
/var/log/wtmp	用户登录记录，二进制文件	二进制文件	last -f /var/log/wtmp
/var/log/btmp	登录失败记录，二进制格式	二进制文件	lastb -f /var/log/btmp
/var/log/dmesg	内核启动与硬件相关日志	文本文件	dmesg
3. journalctl 三类日志查询
① 最近 30 条日志
命令：
bash
sudo journalctl -n 30
观察结果：输出系统最近 30 条事件，其中包含 sshd 服务进程记录，记录 SSH 连接建立事件，显示客户端 IP 接入登录信息。
② 时间范围查询
命令：
bash
sudo journalctl --since "2026-09-17 08:00:00" --until "2026-09-17 18:00:00"
观察结果：查询 2026-09-17 08:00:00 至 2026-09-17 18:00:00 之间的系统日志，时间段内包含系统定时任务、内核信息与 ssh 登录审计记录。
③ 本次开机 warning 级别日志
命令：
bash
sudo journalctl -p warning -b
观察结果：本次开机后 warning 级别的系统告警日志，查看到一条磁盘预读性能警告记录。
4. 实验小结
本次实验完成 SSH 远程登录 Ubuntu 虚拟机，验证 22 端口与 ssh 服务状态；完成系统日志盘点，区分文本日志与二进制登录日志，掌握不同日志文件对应的读取命令；使用 journalctl 按条数、时间范围、日志严重等级查询系统日志，学会查看系统服务与内核事件，理解 Linux 系统日志存放位置与查看方式。