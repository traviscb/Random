#!/bin/bash
# push-button installer for CDS invenio onto a carefully prepared RHEL5 host
#
# provides a perfectly clean installation free of legacy cruft on either the 
# filesystem or database

# CONFIGFILE should be a regular file in the home directory with the following 
# contents:
## INVENIO_DB="cdsinvenio"
## INVENIO_DB_USER="cdsinvenio"
## INVENIO_DB_PASS="some_invenio_password"
## MYSQL_ROOT_PASS="some_mysql_password"
## INSPIRE_REPO="/opt/inspire-old" (if needed)
## INSPIRE_DB="inspiretest" (if needed)
## INSPIRE_CONF="/opt/inspire/inspire-local.conf" (if needed)
## BIBSCHED_USER="apache"
## PREFIX="/opt/invenio"
# ...except without being commented out.
# 
# It must be readable only by the owner and have no other permissions

export CONFIGURE_OPTS="--with-python=/usr/bin/python"
CONFIGFILE="/opt/inspire/.invenio_install.conf"
export G_DB_RESET="FALSE"
export G_OLD_INSPIRE="FALSE"
export INSPIRE_REPO="/opt/inspire-old/"
export INSPIRE_CONF="/opt/inspire/inspire-local.conf"
export LOCAL_CONF="/opt/inspire/invenio-local.conf"
export BIBSCHED_USER="apache"
export PREFIX="/opt/invenio"
export G_INSPIRE_DB="FALSE"
export INSPIRE_RECORDS="/opt/inspire/inspire_test.marcxml"
export APACHE_RESTART="sudo /etc/init.d/httpd restart"


#if [ `stat --printf %a $CONFIGFILE` == 400 ]; then 
source $CONFIGFILE
#fi


for arg in $@; do
  if [ $arg == '--help' ]; then
    echo "You must have /opt/inspire/ with configuration files:"
    echo " .invenio-install.conf for me"
    echo " invenio-local.conf for invenio"
    echo " invenio-apache-vhost*.conf for apache"
    echo "And I won't blow away the MySQL database by default.  Inspect my source"
    echo "to learn what you need to know."
    echo "By default I will install invenio from a single repo"
    echo "call me with --inspire-old to install from a separate inspire repo"
    echo "call me with --inspire-db to switch to a preexisting inspire db"
    echo "combine w/ --reset-db might create the inspire-test db from scratch"
    exit 0
  elif [ $arg == '--reset-db' ]; then
    echo "Ok, I'll reset the DB"
    export G_DB_RESET="TRUE"
  elif [ $arg == '--inspire-old' ]; then
    echo "Ok, I'll install INSPIRE from the separate repo"
    export G_OLD_INSPIRE="TRUE"
  elif [ $arg == '--inspire-db' ]; then
    echo "Ok, I'll use the INSPIRE db"
    export INVENIO_DB=$INSPIRE_DB
    export LOCAL_CONF=$INSPIRE_CONF
    export G_INSPIRE_DB="TRUE"
  fi
done

sudo -v; 
# Stop running bibsched so that we don't create zombies
sudo -u $BIBSCHED_USER $PREFIX/bin/bibsched stop


if [ $G_DB_RESET == 'TRUE' ]; then
    echo -e "DROPPING AND RECREATING THE DATABASE...";
    echo "drop database $INVENIO_DB;" | mysql -u root --password=$MYSQL_ROOT_PASS; 
    echo "CREATE DATABASE $INVENIO_DB DEFAULT CHARACTER SET utf8; GRANT ALL PRIVILEGES ON $INVENIO_DB.* TO $INVENIO_DB_USER@localhost IDENTIFIED BY '$INVENIO_DB_PASS';" | 
mysql -u root --password=$MYSQL_ROOT_PASS; 
    echo "DONE.";
fi

sudo rm -rf $PREFIX; 
sudo git clean -x -f; 


aclocal && automake -a -c && autoconf -f && ./configure $CONFIGURE_OPTS  0</dev/null \
        && make && sudo make install \
        && sudo chown -R $BIBSCHED_USER:$BIBSCHED_USER $PREFIX \
        && sudo install -m 660 -o $BIBSCHED_USER -g $BIBSCHED_USER $LOCAL_CONF $PREFIX/etc; 
if [ $? -eq 0 ]; then
  echo -e "\n** INVENIO INSTALLED SUCCESSFULLY\n";
else
  exit 1;
fi

if [ $G_OLD_INSPIRE = 'TRUE' ]; then
    echo -e "Installing INSPIRE from old repo"
    cd $INSPIRE_REPO
    sudo make install
    make install-dbchanges
    sudo chown -R $BIBSCHED_USER:$BIBSCHED_USER $PREFIX
    echo "DONE."
fi


sudo -u $BIBSCHED_USER $PREFIX/bin/inveniocfg --update-all 

if [ $? -eq 0 ]; then
  echo -e "\n** CONFIGURATION UPDATED SUCCESSFULLY\n"; 
else
  exit 1;
fi

if [ $G_DB_RESET == 'TRUE' ]; then
   echo -e "SETTING UP THE INVENIO TABLES AND DEMO SITE..."
   sudo -u $BIBSCHED_USER $PREFIX/bin/inveniocfg --create-tables \
   && echo -e "\n** MYSQL TABLES CREATED SUCCESSFULLY\n" \
   && sudo -u $BIBSCHED_USER $PREFIX/bin/inveniocfg --load-webstat-conf \
   && echo -e "\n** WEBSTAT CONF LOADED SUCCESSFULLY\n" \
   && sudo -u $BIBSCHED_USER $PREFIX/bin/inveniocfg --create-demo-site \
   && echo -e "\n** DEMO SITE INSTALLED\n" \
   && sudo -u $BIBSCHED_USER $PREFIX/bin/inveniocfg --load-demo-records \
   && echo -e "\n** DEMO RECORDS INSTALLED\n" \
   echo "DONE."
   
#   if [ $G_INSPIRE_DB == 'TRUE' ]; then
#       sudo -u $BIBSCHED_USER $PREFIX/bin/inveniocfg --drop-demo-site --yes-i-know
#       echo -e "\n** DROPPED DEMO SITE\n" 
#       sudo -u $BIBSCHED_USER $PREFIX/bin/bibupload -u admin $INSPIRE_RECORDS \
#       && echo -e "\n** UPLOADED INSPIRE RECORDS\n" \    
#       && sudo -u  $BIBSCHED_USER $PREFIX/bin/webcoll -uadmin \
#       && sudo -u  $BIBSCHED_USER $PREFIX/bin/bibindex -uadmin \
#       && echo -e "\n** webcoll/indexing done\n"     
#   fi
fi



sudo -u $BIBSCHED_USER $PREFIX/bin/inveniocfg --create-apache-conf \
   && sudo install -p -m 660 -g $BIBSCHED_USER -o $BIBSCHED_USER /opt/inspire/invenio-apache-vhost*.conf $PREFIX/etc/apache \
   && $APACHE_RESTART

if [ $? -eq 0 ]; then
  echo -e "\n** APACHE SET UP CORRECTLY\n";
else
  exit 1;
fi

echo -e "\nOk, now everything should work.\nInstalling a cron job for feedbox updates...."
echo -e "\n3,23,46 * * * * $PREFIX/bin/inspire_update_feedboxes -d\n" >>/tmp/apache_entry
#sudo cat /var/spool/cron/apache /tmp/apache_entry >/tmp/apache_cron
#sudo mv /tmp/apache_cron /var/spool/cron/apache && sudo chmod 600 /var/spool/cron/apache
echo -e " done.\nPlease cat /var/spool/cron/apache to make sure I didn't\n"
echo -e "accidentally create multiple entries.\n"
#sudo -u apache $PREFIX/bin/inspire_update_feedboxes -d


echo -e "\nSo we've gotten this far, let's try starting the standard system\nservices, such as webcoll.\n"

#start fresh bibsched process (not positive this works - may still pick up
#old processes)
sudo -u $BIBSCHED_USER $PREFIX/bin/bibsched start

sudo -u $BIBSCHED_USER $PREFIX/bin/webcoll -u admin

#Not supposed to run as sudo, will sudo inside...
$PREFIX/bin/inveniocfg --start-admin-jobs

exit 0