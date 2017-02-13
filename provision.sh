#!/usr/bin/env bash

echo "=== Starting provision script..."

cd /vagrant

echo "=== Adding 'cd /vagrant' to .profile"
cat >> /home/ubuntu/.profile <<EOL

cd /vagrant
EOL

echo "=== Updating apt..."
apt-get update >/dev/null 2>&1

# Used in many dependencies:
apt-get install python-software-properties curl git -y

echo "=== Installing Node.js 6.x..."
curl --silent --location https://deb.nodesource.com/setup_6.x | sudo bash -
apt-get install nodejs -y

echo "=== Installing Haxe 3.4.0..."
add-apt-repository ppa:haxe/releases -y
apt-get update
apt-get install haxe -y

sudo -i -u ubuntu sh -c 'echo /home/ubuntu/haxelib | haxelib setup'
sudo -i -u ubuntu haxelib install travix
echo "=== Installing Haxe targets:"

echo "=== Installing C++..."
apt-get install -y g++

echo "=== Installing C#..."
apt-get install -y mono-devel mono-mcs

echo "=== Installing Java..."
apt-get install -y openjdk-8-jdk

echo "=== Installing PHP..."
apt-get install -y php-cli

echo "=== Installing Flash (xvfb)..."
apt-get install -y xvfb
wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | sudo apt-key add -
sudo sed -i -e 's/deb http/deb [arch=amd64] http/' "/etc/apt/sources.list.d/google-chrome.list" "/opt/google/chrome/cron/google-chrome"
sudo dpkg --add-architecture i386
sudo apt-get update
apt-get install -y libcurl3:i386 libglib2.0-0:i386 libx11-6:i386 libxext6:i386 libxt6:i386 libxcursor1:i386 libnss3:i386 libgtk2.0-0:i386

echo "=== Installing Phantomjs (js testing)..."
npm install -g phantomjs-prebuilt

echo "=== Renaming host..."
sed -i "s/`cat /etc/hostname`/haxedci/g" /etc/hosts
echo haxedci > /etc/hostname
systemctl restart systemd-logind.service

echo "=== Provision script finished!"
echo "Start with 'vagrant reload && vagrant ssh'."
echo "Change timezone: sudo dpkg-reconfigure tzdata"
