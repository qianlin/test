#!/bin/bash
# Author: lin.qian@huawei.com  2014/8/16

set -e
home_dir=/home
rally_src=/home/rally
controller=''
username=admin
password=admin
tenant_name=admin
deployid=''
log_file=$home_dir/rally_install.log
mkdir -p $rally_src
touch $log_file
echo `date` | tee -a $log_file


function usage() {
  echo "Usage: $0 [OPTION]..."
  echo "Install rally and run tempest"
  echo ""
  echo "  -c, --controller       controllerip of openstack"
  echo "  -u, --username         admin user of openstack"
  echo "  -p, --password         passwd of admin user"
  echo "  -t, --tenant           tenant name for openstack"
  echo "  -h  --help             Print this usage message"
}

if ! options=$( getopt -o c:u:p:t:h -l controller:,username:,password:,tenant:,help -- "$@" )
then
  usage
  exit 1
fi

eval set -- $options
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit;;
    -c|--controller) controller=$2; shift;;
    -u|--username) username=$2; shift;;
    -p|--password) password=$2; shift;;
    -t|--tenant) tenant_name=$2; shift;;
  esac
  shift
done

function update_python() {
  echo "-----update python begin-----" | tee -a $log_file
  cd $home_dir
  yum -y install gcc openssl openssl-devel
  yum update wget -y
  wget https://www.python.org/ftp/python/2.7.8/Python-2.7.8.tgz
  tar zxvf Python-2.7.8.tgz
  cd Python-2.7.8
  ./configure
  sed -i "s/#zlib zlibmodule.c -I$(prefix)/zlib zlibmodule.c -I$(prefix)/g" Modules/Setup.dist
  ./configure
  make all
  make install
  make clean
  make distclean
  mv /usr/bin/python /usr/bin/python2.6.6
  ln -s /usr/local/bin/python2.7 /usr/bin/python
  sed -i "s/\/usr\/bin\/python/\/usr\/bin\/python2.6.6/g" /usr/bin/yum
  echo "-----update python end-----" | tee -a $log_file
}

function add_repo() {
  echo "-----add repo begin-----" | tee -a $log_file
  yum -y install http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm
  echo "-----add repo end-----" | tee -a $log_file
}

function preinstall() {
  echo "-----preinstall begin-----" | tee -a $log_file
  cd $home_dir
  yum -y install git zlib* bzip2* sqlite-devel
  #close iptables
  /etc/init.d/iptables stop
  chkconfig --level 35 iptables off
  cd $home_dir
  wget https://raw.github.com/pypa/pip/master/contrib/get-pip.py --no-check-certificate
  python get-pip.py
#  config_pip
  pip install pysqlite

  cp /usr/lib64/python2.6/lib-dynload/bz2.so /usr/local/lib/python2.7/
}

function config_pip() {
  mkdir -p ~/.pip
  echo "[global]" >> ~/.pip/pip.conf
  echo "index-url=http://10.1.4.65/pypi/simple" >> ~/.pip/pip.conf
}

function install_rally() {
  echo "-----install rally begin-----" | tee -a $log_file
  cd $home_dir
  git clone https://git.openstack.org/stackforge/rally  $rally_src
  sh rally/install_rally.sh
  #pip install -r rally/requirements.txt
  #sh rally/install_rally.sh
  #modify conf
  sed -i '1alog_file=rally-log.log' /etc/rally/rally.conf
  sed -i '1alog_dir=/etc/rally' /etc/rally/rally.conf
  sed -i '1adebug=true' /etc/rally/rally.conf 
  sed -i '1averbose=true' /etc/rally/rally.conf
  echo "-----install rally end-----" | tee -a $log_file
}

function add_deployment() {
  echo "-----add deployment begin-----" | tee -a $log_file
  cp $rally_src/doc/samples/deployments/existing.json /etc/rally/
  sed -i "s/example\.net/$controller/g" /etc/rally/existing.json
  sed -i "s/admin/$username/g" /etc/rally/existing.json
  sed -i "s/admin/$username/g" /etc/rally/existing.json
  sed -i "s/myadminpass/$password/g" /etc/rally/existing.json
  sed -i "s/demo/$tenant_name/g" /etc/rally/existing.json
  rally deployment create --name $controller --filename /etc/rally/existing.json

  deployid = `rally deployment list | grep $controller | awk {'print $2'}`
  echo "-----add deployment end-----" | tee -a $log_file
}

function run_tempest() {
  echo "-----install tempest begin-----" | tee -a $log_file
  rally-manage tempest install --deploy-id $deployid | tee -a log_file
#  cp tempest.conf /root/.rally/tempest/for-deployment-$deployid/
  rally verify start --deploy-id $deployid 
  verifyid = `rally verify list | grep smoke | grep finished | grep $deployid| awk {'print $2'}`
  rally verify results --uuid $verifyid --html --output-file /home/smoke.html
  echo "-----install tempest end-----" | tee -a $log_file
}

function run_rally_scenarios() {
  echo "-----run scenarios begin-----" | tee -a $log_file
  cp -r $rally_src/doc/samples/tasks /etc/rally/
}

update_python
#add_repo
yum -y update
preinstall
install_rally
add_deployment
