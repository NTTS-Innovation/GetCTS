### OS installation

Select English and press ENTER<br>
![image](https://github.com/NTTS-Innovation/GetCTS/blob/master/doc/Ubuntu%2024.04/pictures/1.png?raw=true)
<br><br>
Select keyboard layout that match your needs and press ENTER on Done<br>
![image](https://github.com/NTTS-Innovation/GetCTS/blob/master/doc/Ubuntu%2024.04/pictures/2.png?raw=true)
<br><br>
Select minimized installation "Ubuntu Server (minimized)" and press ENTER on Done<br>
![image](https://github.com/NTTS-Innovation/GetCTS/blob/master/doc/Ubuntu%2024.04/pictures/3.png?raw=true)
<br><br>
Configure management interface by selecting the interface and press ENTER, use settings that match the local need for the current environment. Make sure to disable all monitoring interfaces. Once completed press ENTER on Done<br>
![image](https://github.com/NTTS-Innovation/GetCTS/blob/master/doc/Ubuntu%2024.04/pictures/4.png?raw=true)
<br><br>
Configure proxy if needed or leave it empty, press ENTER on Done<br>
![image](https://github.com/NTTS-Innovation/GetCTS/blob/master/doc/Ubuntu%2024.04/pictures/5.png?raw=true)
<br><br>
Leave "Mirror address" as is unless there are specific needs to use a custom mirror. This should almost never be needed. Press ENTER on Done<br>
![image](https://github.com/NTTS-Innovation/GetCTS/blob/master/doc/Ubuntu%2024.04/pictures/6.png?raw=true)
<br><br>
Configure system disk, make sure "Use an entire disk" is checked and that correct disk is selected.  "Set up this disk as an LVM group" should also be checked. Press ENTER on Done<br>
![image](https://github.com/NTTS-Innovation/GetCTS/blob/master/doc/Ubuntu%2024.04/pictures/7.png?raw=true)
<br><br>
The disk will not be fully used unless we change allocated size on root partition. Select system disk and press Enter<br>
![image](https://github.com/NTTS-Innovation/GetCTS/blob/master/doc/Ubuntu%2024.04/pictures/8.png?raw=true)
<br><br>
Select root mount "/" and press Enter<br>
![image](https://github.com/NTTS-Innovation/GetCTS/blob/master/doc/Ubuntu%2024.04/pictures/9.png?raw=true)
<br><br>
Select Edit and press Enter<br>
![image](https://github.com/NTTS-Innovation/GetCTS/blob/master/doc/Ubuntu%2024.04/pictures/10.png?raw=true)
<br><br>
Modify Size to the value defined as "max", select Save and press Enter<br>
![image](https://github.com/NTTS-Innovation/GetCTS/blob/master/doc/Ubuntu%2024.04/pictures/11.png?raw=true)
<br><br>
Select Done and press Enter<br>
![image](https://github.com/NTTS-Innovation/GetCTS/blob/master/doc/Ubuntu%2024.04/pictures/12.png?raw=true)
<br><br>
Confirm changes by selecting Continue and press ENTER<br>
![image](https://github.com/NTTS-Innovation/GetCTS/blob/master/doc/Ubuntu%2024.04/pictures/13.png?raw=true)
<br><br>
Define your name, servers's name, username and password according to your standards. Make sure your credentials are stored in a safe place and depending of the deployment send them to NTT using a secure channel. Press ENTER on Done<br>
![image](https://github.com/NTTS-Innovation/GetCTS/blob/master/doc/Ubuntu%2024.04/pictures/14.png?raw=true)
<br><br>
If you have Ubuntu Pro, please enable it or check "Skip for now" and press ENTER on Continue<br>
![image](https://github.com/NTTS-Innovation/GetCTS/blob/master/doc/Ubuntu%2024.04/pictures/15.png?raw=true)
<br><br>
Check "Install OpenSSH server" and press ENTER on Done<br>
![image](https://github.com/NTTS-Innovation/GetCTS/blob/master/doc/Ubuntu%2024.04/pictures/16.png?raw=true)
<br><br>
Install optional 3rd party drivers, press Continue when done<br>
![image](https://github.com/NTTS-Innovation/GetCTS/blob/master/doc/Ubuntu%2024.04/pictures/17.png?raw=true)
<br><br>
Do not select any features, just press ENTER on Done<br>
![image](https://github.com/NTTS-Innovation/GetCTS/blob/master/doc/Ubuntu%2024.04/pictures/18.png?raw=true)
<br><br>
Wait until the installation has been completed and the "Reboot Now" button appears. Eject installation media from the host and press ENTER on "Reboot Now"<br>
![image](https://github.com/NTTS-Innovation/GetCTS/blob/master/doc/Ubuntu%2024.04/pictures/19.png?raw=true)


Once the machine has been rebooted login using SSH to the IP address that was assigned to the management interface.

You will need the enrollment key to proceed with the actual installation of the CTS software.
Execute the following command that will start the installation and ask you some questions. You need to know the following:
* Type of service
* NTP (net time protocol) server
* Init key (enrollment key)
* Sensor name

```
wget -q -O install.sh https://git.io/JZmVM && sudo bash ./install.sh
```
