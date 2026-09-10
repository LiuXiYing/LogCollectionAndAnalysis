# Lab1 实验报告
## 实验名称：Ubuntu基础环境与服务安装验证
### 一、实验目的
1. 掌握Ubuntu系统软件包安装、查询命令
2. 学会查看系统服务状态、开机自启配置
3. 验证Open-VM-Tools、OpenSSH、rsyslog服务功能
4. 验证系统日志记录功能

### 二、实验环境
操作系统：Ubuntu 24.04（Live环境）
虚拟化平台：VMware Workstation

### 三、实验步骤与命令
#### 1. 更新软件源（可选）
```bash
sudo apt update
 
 
2. 安装所需软件包
 
sudo apt install open-vm-tools open-vm-tools-desktop openssh-server rsyslog
 
 
3. 查询软件包版本，验证安装
 
dpkg-query -W -f='${Package}\t${Version}\n' open-vm-tools open-vm-tools-desktop openssh-server rsyslog
 
 
预期输出：四个包均输出版本号，代表安装成功
 
4. 查看open-vm-tools版本与运行状态
 
vmware-toolbox-cmd -v
systemctl is-active open-vm-tools
 
 
5. 查看ssh、rsyslog开机自启状态
 
systemctl is-enabled ssh rsyslog
 
 
6. 查看ssh.socket、rsyslog当前运行状态
 
systemctl is-active ssh.socket
systemctl is-active rsyslog
 
 
7. 查看SSH 22端口监听
 
ss -lnt | grep ':22'
 
 
8. rsyslog日志测试
 
logger -t lab1-check "Lab1 rsyslog test 学号姓名"
sudo tail -n 10 /var/log/syslog
 
 
四、实验结果
 
软件包查询结果
 
open-vm-tools	        2:13.0.10-0ubuntu0.24.04.1
open-vm-tools-desktop	2:13.0.10-0ubuntu0.24.04.1
openssh-server	        1:9.6p1-3ubuntu13.19
rsyslog	                8.2312.0-3ubuntu9.1
 
 
vmware-toolbox版本： 13.0.10 (build-25056151) 
open-vm-tools状态： active ，服务正常运行
开机自启：ssh、rsyslog默认 disabled （开机不自动启动）
SSH端口：22端口处于LISTEN监听状态，可以接收ssh连接
rsyslog：logger命令成功写入自定义测试日志，可在 /var/log/syslog 查看
 
五、实验总结
 
使用 apt install 可以在Ubuntu安装软件包，包名中间短横线不能替换成空格。
 dpkg-query 用于查询已安装deb软件包的版本信息。
 systemctl is-active 查看服务当前是否运行； systemctl is-enabled 查看是否开机自启。
Ubuntu 24.04的ssh采用ssh.socket套接字激活机制，直接查询ssh.service会显示not-found，应查看ssh.socket。
 ss 命令用于查看端口监听状态， logger 命令向系统日志写入消息，rsyslog负责管理系统日志。