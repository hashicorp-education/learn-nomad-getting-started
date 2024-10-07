#!/bin/bash

set -e

exec > >(sudo tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

ACL_DIRECTORY="/ops/shared/config"
NOMAD_BOOTSTRAP_TOKEN="/tmp/nomad_bootstrap"
NOMAD_USER_TOKEN="/tmp/nomad_user_token"
CONFIGDIR="/ops/shared/config"
NOMADVERSION=${nomad_version}
NOMADDOWNLOAD=https://releases.hashicorp.com/nomad/$${NOMADVERSION}/nomad_$${NOMADVERSION}_linux_amd64.zip
NOMADCONFIGDIR="/etc/nomad.d"
NOMADDIR="/opt/nomad"
HOME_DIR="ubuntu"
CLOUD_ENV=${cloud_env}

# Install phase begin ---------------------------------------

# Install dependencies
case $CLOUD_ENV in
  aws)
    echo "CLOUD_ENV: aws"
    sudo apt-get update && sudo apt-get install -y software-properties-common
    TOKEN=$(curl -X PUT "http://instance-data/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

    IP_ADDRESS=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://instance-data/latest/meta-data/local-ipv4)
    PUBLIC_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://instance-data/latest/meta-data/public-ipv4)
    ;;

  gce)
    echo "CLOUD_ENV: gce"
    sudo apt-get update && sudo apt-get install -y software-properties-common
    IP_ADDRESS=$(curl -H "Metadata-Flavor: Google" http://metadata/computeMetadata/v1/instance/network-interfaces/0/ip)
    ;;

  azure)
    echo "CLOUD_ENV: azure"
    sudo apt-get update && sudo apt-get install -y software-properties-common jq
    IP_ADDRESS=$(curl -s -H Metadata:true --noproxy "*" http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0?api-version=2021-12-13 | jq -r '.["privateIpAddress"]')
    ;;

  alicloud)
    echo "CLOUD_ENV: alicloud"
    sudo apt-get update && sudo apt-get install -y software-properties-common
    IP_ADDRESS=$(curl http://100.100.100.200/latest/meta-data/private-ipv4)
    PUBLIC_IP=$(curl http://100.100.100.200/latest/meta-data/eipv4)
    ;;

  *)
    exit "CLOUD_ENV not set to one of aws, gce, azure, or alicloud - exiting."
    ;;
esac

sudo apt-get update
sudo apt-get install -y unzip tree redis-tools jq curl tmux
sudo apt-get clean


# Disable the firewall

sudo ufw disable || echo "ufw not installed"

# Download and install Nomad
curl -L $NOMADDOWNLOAD > nomad.zip

sudo unzip nomad.zip -d /usr/local/bin
sudo chmod 0755 /usr/local/bin/nomad
sudo chown root:root /usr/local/bin/nomad

sudo mkdir -p $NOMADCONFIGDIR
sudo chmod 755 $NOMADCONFIGDIR
sudo mkdir -p $NOMADDIR
sudo chmod 755 $NOMADDIR

# Docker
distro=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
sudo apt-get install -y apt-transport-https ca-certificates gnupg2 
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/$${distro} $(lsb_release -cs) stable"
sudo apt-get update
sudo apt-get install -y docker-ce

# Java
sudo add-apt-repository -y ppa:openjdk-r/ppa
sudo apt-get update 
sudo apt-get install -y openjdk-8-jdk
JAVA_HOME=$(readlink -f /usr/bin/java | sed "s:bin/java::")

# CNI plugins
curl -L -o cni-plugins.tgz "https://github.com/containernetworking/plugins/releases/download/v1.0.0/cni-plugins-linux-$( [ $(uname -m) = aarch64 ] && echo arm64 || echo amd64)"-v1.0.0.tgz
sudo mkdir -p /opt/cni/bin
sudo tar -C /opt/cni/bin -xzf cni-plugins.tgz

echo 1 | sudo tee /proc/sys/net/bridge/bridge-nf-call-arptables
echo 1 | sudo tee /proc/sys/net/bridge/bridge-nf-call-ip6tables
echo 1 | sudo tee /proc/sys/net/bridge/bridge-nf-call-iptables

# Install phase finish ---------------------------------------

RETRY_JOIN="${retry_join}"
DOCKER_BRIDGE_IP_ADDRESS=(`ifconfig docker0 2>/dev/null|awk '/inet addr:/ {print $2}'|sed 's/addr://'`)

sed -i "s/IP_ADDRESS/$IP_ADDRESS/g" $CONFIGDIR/nomad_client.hcl
sed -i "s/RETRY_JOIN/$RETRY_JOIN/g" $CONFIGDIR/nomad_client.hcl
sudo cp $CONFIGDIR/nomad_client.hcl $NOMADCONFIGDIR/nomad.hcl
sudo cp $CONFIGDIR/nomad.service /etc/systemd/system/nomad.service

sudo systemctl enable nomad.service
sudo systemctl start nomad.service

# Wait for Nomad to restart
for i in {1..9}; do
    # capture stdout and stderr
    set +e
    sleep 1
    OUTPUT=$(nomad -v 2>&1)
    if [ $? -ne 0 ]; then
        continue
    else
        exit 0
    fi
done

export NOMAD_ADDR=http://$IP_ADDRESS:4646

# Add hostname to /etc/hosts

echo "127.0.0.1 $(hostname)" | sudo tee --append /etc/hosts

# Add Docker bridge network IP to /etc/resolv.conf (at the top)

echo "nameserver $DOCKER_BRIDGE_IP_ADDRESS" | sudo tee /etc/resolv.conf.new
cat /etc/resolv.conf | sudo tee --append /etc/resolv.conf.new
sudo mv /etc/resolv.conf.new /etc/resolv.conf

# Set env vars
echo "export NOMAD_ADDR=http://$IP_ADDRESS:4646" | sudo tee --append /home/$HOME_DIR/.bashrc
echo "export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64/jre"  | sudo tee --append /home/$HOME_DIR/.bashrc

# Server setup phase finish -----------------------------------