# Lab3 Linux日志认证与自定义日志
学号：2024010022
姓名：杨云富

## 一、实验目的
1. 查看SSH认证日志，区分成功登录与失败登录的日志记录。
2. 使用logger命令生成自定义日志。
3. 验证同一条日志，会同时保存到syslog与journal两套日志系统。

## 二、实验环境
VMware Ubuntu虚拟机，Git Bash通过SSH远程连接Ubuntu。

## 三、实验步骤
### 3.1 SSH认证日志查询
新开终端进行SSH登录，故意输入错误密码制造失败认证；正常SSH登录产生成功认证记录。
执行命令查询auth.log和journal中的ssh认证日志：
```bash
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
观察结果：
logger 产生的日志，会同时写入传统 syslog 文件与 systemd journal 日志库，两处都能检索到同一条日志消息，验证了双日志管道。添加-a参数可以解决 grep 识别 syslog 为二进制文件的警告。


四、实验小结
SSH 登录行为会被系统完整记录，登录审计日志可以用于溯源账号登录行为。logger 可以手动生成自定义系统日志。Linux 同时存在 syslog 和 journal 两套日志体系，同一条日志会同时进入两套系统，提供不同的日志查询方式。