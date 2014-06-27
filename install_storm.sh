#!/bin/bash

pp() {
	echo -e "\e[00;32m"$1"\e[00m"
}

#########################################
# System dependencies.
#########################################

deps() {
	pp "Checking system dependencies..."
	echo
	sudo apt-get --assume-yes install curl supervisor
	echo
}

#########################################
# ZooKeeper.
#########################################

zookeeper() {
	ZK_PORT=5181	
	
	if [ "$HOST" != "$NIMBUS" ]
	then
		pp "Skipping ZooKeeper installation on all hosts but nimbus!"
		return
	fi

	ZK_URL="http://archive.cloudera.com/cdh4/ubuntu/precise/amd64/cdh"
	ZK_VERSION="precise-cdh4"
	ZK_DIR="/usr/lib/zookeeper/bin"
	ZK_CONF="/etc/zookeeper/conf.dist/zoo.cfg"
	ZK_DATADIR=$BASEDIR"/zookeeper"
	
	REP_FILE="/etc/apt/sources.list.d/cloudera.list"
	PINNING_FILE="/etc/apt/preferences"
	UBUNTU_VERSION="trusty"
	
	pp "Installing ZooKeeper on nimbus host '"$HOST"'..."

	mkdir $ZK_DATADIR >/dev/null
	
	sudo bash -c "cat << EOF > $REP_FILE
deb [arch=amd64] $ZK_URL $ZK_VERSION contrib
deb-src $ZK_URL $ZK_VERSION contrib
EOF"
	
	curl -s $ZK_URL/archive.key | sudo apt-key add -
	
	pp "Updating apt repositories..."
	
	sudo apt-get update
	
	sudo bash -c "cat << EOF > $PINNING_FILE
Package: *
Pin: release n=$UBUNTU_VERSION
Pin-Priority: 100

Package: *
Pin: release n=$ZK_VERSION
Pin-Priority: 600
EOF"

	pp "Downloading ZooKeeper..."
	
	sudo apt-get --assume-yes install zookeeper-server
	
	pp "Configuring ZooKeeper..."

	# Cluster config.
	sudo bash -c "cat << EOF > $ZK_CONF
maxClientCnxns=50
tickTime=2000
dataDir=$ZK_DATADIR
initLimit=10
syncLimit=5
clientPort=$ZK_PORT
autopurge.purgeInterval=24
autopurge.snapRetainCount=5
EOF"

}

#########################################
# Storm 
#########################################

storm() {
	STORM_URL="http://ftp.fau.de/apache/incubator/storm/apache-storm-0.9.1-incubating/apache-storm-0.9.1-incubating.zip"
	STORM_VERSION="apache-storm-0.9.1-incubating"
	STORM_DIR=$BASEDIR"/storm"
	STORM_DATADIR=$STORM_DIR"/data"
	STORM_CONF=$STORM_DIR"/"$STORM_VERSION"/conf/storm.yaml"

	pp "Installing Storm "$STORM_VERSION"..."
	mkdir $STORM_DIR >/dev/null
	mkdir $STORM_DATADIR >/dev/null

	pp "Downloading Storm..."
	wget -cv  $STORM_URL
	unzip -qq $STORM_VERSION".zip" -d $STORM_DIR
	rm $STORM_VERSION".zip"

	pp "Configuring Storm..."

	echo "storm.local.dir: \""$STORM_DATADIR"\"" > $STORM_CONF
	echo "storm.zookeeper.servers:" >> $STORM_CONF
	echo " - \""$NIMBUS"\"" >> $STORM_CONF
	echo "nimbus.host: \""$NIMBUS"\"" >> $STORM_CONF
	echo "storm.zookeeper.port: $ZK_PORT" >> $STORM_CONF
}

#########################################
# Supervisor (to run under supervision)
#########################################

supervisor() {
	SUP_CONF="/etc/supervisor/supervisord.conf"

	pp "Configuring Supervisor..."
	
	if [ "$HOST" != "$NIMBUS" ]
	then
		sudo bash -c "cat << EOF >> $SUP_CONF

[program:storm-supervisor]
command=$STORM_DIR/$STORM_VERSION/bin/storm supervisor
autostart=true
autorestart=true
startsecs=10
startretries=999
log_stdout=true
log_stderr=true
logfile=$STORM_DIR/log/supervisor.out
logfile_maxbytes=20MB
logfile_backups=10
EOF"
	else
		sudo bash -c "cat << EOF >> $SUP_CONF

[program:zookeeper]
command=sh $ZK_DIR/zkServer.sh start-foreground
autostart=true
autorestart=true
startsecs=10
startretries=999
log_stdout=true
log_stderr=true
logfile=$ZK_DATADIR/log/zookeeper.out
logfile_maxbytes=20MB
logfile_backups=10

[program:storm-nimbus]
command=$STORM_DIR/$STORM_VERSION/bin/storm nimbus
autostart=true
autorestart=true
startsecs=10
startretries=999
log_stdout=true
log_stderr=true
logfile=$STORM_DIR/log/nimbus.out
logfile_maxbytes=20MB
logfile_backups=10

[program:storm-ui]
command=$STORM_DIR/$STORM_VERSION/bin/storm ui
autostart=true
autorestart=true
startsecs=10
startretries=999
log_stdout=true
log_stderr=true
logfile=$STORM_DIR/log/ui.out
logfile_maxbytes=20MB
logfile_backups=10	
EOF"
	fi

	pp "Starting Supervisor..."

	sudo unlink /var/run/supervisor.sock
	sudo /usr/bin/supervisord -c $SUP_CONF
}

#########################################
# Main app.
#########################################

if [ $# -eq 3 ]
then
	HOST=$1
	NIMBUS=$2
	BASEDIR=$3
	
	pp "Installing Storm on "$HOST" with nimbus on '"$NIMBUS"'..."
	
	deps
	zookeeper
	storm
	supervisor
else
	echo "Usage: ./install_storm <hostname> <nimbus> <basedir>"
fi
