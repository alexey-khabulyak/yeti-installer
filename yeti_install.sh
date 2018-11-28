#!/bin/bash
#DEBUG="TRUE"
TITLE="Yeti-Switch installer"
POST_INSTALL="/tmp/postinstall.$$"
>${POST_INSTALL}
############  prestart checks ################
# find main interface
DEF_INTERFACE=`ip route | grep default | awk '{print $5}'`
if [[ "$DEF_INTERFACE" = "" ]]
then
    echo "No default route"
    IP="127.0.0.1"
else
    IP=`ip addr show dev ${DEF_INTERFACE} | grep -Po 'inet \K[\d.]+'`
fi

#check os version
OS_VERSION=`cat /etc/os-release | grep 'VERSION=' | awk -F '(' '{print $2}' | awk -F ')' '{print $1}'`
if [[ "$OS_VERSION" != "stretch" && "$OS_VERSION" != "jessie" ]]
    then
    whiptail --title  "$TITLE" --msgbox  "Unsupported debian version: ${OS_VERSION}. Aborting..." 8 60
    if [[ "$DEBUG" != "TRUE" ]]
    then
        exit
    fi
    OS_VERSION="stretch" #for debug
fi

#check internet connection
ping 8.8.8.8 -c 1 -W 2 > /dev/null 2>&1
if [[ "$?" -ne 0 ]]
    then 
    whiptail --title  "$TITLE" --msgbox  "No internet connection. Aborting" 8 60
    exit
fi

#check permissions
if [ "$EUID" -ne 0 ]
    then whiptail --title  "$TITLE" --msgbox  "Please run as root: sudo ./yeti_install.sh" 8 60
    exit
fi

#adding pgsql repos
check_pg_repo () {
    if [[ ! -f "/etc/apt/sources.list.d/postgresql.list" ]]
    then
        echo "PGSQL repo not found"
        if [[ "$DEBUG" != "TRUE" ]]
        then
            echo "deb http://apt.postgresql.org/pub/repos/apt/ ${OS_VERSION}-pgdg main" >> /etc/apt/sources.list.d/postgresql.list
            wget --quiet https://www.postgresql.org/media/keys/ACCC4CF8.asc -O - | apt-key add -
            apt update
        fi
    fi
}

check_yeti_repo () {
    if [[ ! -f "/etc/apt/sources.list.d/yeti.list" ]]
    then
        echo "Yeti-switch repo not found"
        if [[ "$DEBUG" != "TRUE" ]]
        then
            echo "deb http://ftp.us.debian.org/debian/ ${OS_VERSION} main contrib non-free" >> /etc/apt/sources.list.d/yeti.list
            echo "deb http://ftp.us.debian.org/debian/ ${OS_VERSION}-updates main" >> /etc/apt/sources.list.d/yeti.list
            echo "deb http://security.debian.org/ ${OS_VERSION}/updates main" >> /etc/apt/sources.list.d/yeti.list
            echo "deb http://pkg.yeti-switch.org/debian/${OS_VERSION} 1.7 main" >> /etc/apt/sources.list.d/yeti.list
            wget --quiet http://pkg.yeti-switch.org/key.gpg -O - | apt-key add -
            apt update
        fi
    fi
}

install_routing_db () {
    check_pg_repo
    check_yeti_repo
    if [[ "$OS_VERSION" = "stretch" ]]
    then 
        echo "Debian 9. Installing Postgresql 10"
        apt update && apt install -y postgresql-10 postgresql-10-prefix postgresql-10-pgq3 postgresql-10-pgq-ext postgresql-10-yeti pgqd
    else 
        echo "Debian 8. Installing Postgresql 9.4"
        apt update && apt install -y postgresql-9.4 postgresql-contrib-9.4 postgresql-9.4-prefix postgresql-9.4-pgq3 postgresql-9.4-pgq-ext postgresql-9.4-yeti pgqd
    fi

    #USER
    DB_USER=$(whiptail --title "${TITLE}" --inputbox "Provide routing db username" 10 60 yeti 3>&1 1>&2 2>&3)
    exitstatus=$?
    if [[ "$exitstatus" -ne 0 || "$DB_USER" = "" ]]
    then
        DB_USER="yeti"
        echo -n "User not specified. Using default value: "
        echo $DB_USER
    fi

    #PASSWORD
    DB_PASSWORD=$(whiptail --title  "${TITLE}" --passwordbox  "Enter your password and choose Ok to continue. Or leave empty to generate" 10 60 3>&1 1>&2 2>&3)
    exitstatus=$?
    if [[ $exitstatus -ne 0 || "$DB_PASSWORD" = "" ]]
    then
        DB_PASSWORD=`openssl rand -base64 16`
    fi
    if [[ "$DEBUG" != "TRUE" ]]
    then
        su - postgres -c "psql -c \"create user ${DB_USER} encrypted password '${DB_PASSWORD}' superuser;\""
        su - postgres -c "psql -c \"create database yeti owner ${DB_USER};\""
    fi
    #postinstall file:
    echo "Yeti routing DB: yeti, User: ${DB_USER}, Password: ${DB_PASSWORD}" >> ${POST_INSTALL}
}

install_cdr_db () {
    check_pg_repo
    check_yeti_repo
    if [[ "$OS_VERSION" = "stretch" ]]
    then 
        echo "Debian 9. Installing Postgresql 10"
        apt update && apt install -y postgresql-10 postgresql-10-prefix postgresql-10-pgq3 postgresql-10-pgq-ext postgresql-10-yeti pgqd
    else 
        echo "Debian 8. Installing Postgresql 9.4"
        apt update && apt install -y postgresql-9.4 postgresql-contrib-9.4 postgresql-9.4-prefix postgresql-9.4-pgq3 postgresql-9.4-pgq-ext postgresql-9.4-yeti pgqd
    fi

    #USER
    CDR_USER=$(whiptail --title "${TITLE}" --inputbox "Provide cdr db username" 10 60 cdr 3>&1 1>&2 2>&3)
    exitstatus=$?
    if [[ "$exitstatus" -ne 0 || "$CDR_USER" = "" ]]
    then
        CDR_USER="cdr"
        echo -n "User not specified. Using default value: "
        echo $CDR_USER
    fi

    #PASSWORD
    CDR_PASSWORD=$(whiptail --title  "${TITLE}" --passwordbox  "Enter your password and choose Ok to continue. Or leave empty to generate" 10 60 3>&1 1>&2 2>&3)
    exitstatus=$?
    if [[ $exitstatus -ne 0 || "$CDR_PASSWORD" = "" ]]
    then
        CDR_PASSWORD=`openssl rand -base64 16`
    fi
    if [[ "$DEBUG" != "TRUE" ]]
    then
        su - postgres -c "psql -c \"create user ${CDR_USER} encrypted password '${CDR_PASSWORD}' superuser;\""
        su - postgres -c "psql -c \"create database cdr owner ${CDR_USER};\""
    fi

    cat << EOF > /etc/pgqd.ini
[pgqd]
base_connstr = host=127.0.0.1 port=5432 dbname=cdr user=${CDR_USER} password=${CDR_PASSWORD}
initial_database = cdr
database_list = cdr
script = /usr/bin/pgqd
pidfile = /var/run/postgresql/pgqd.pid
ticker_max_count=1
ticker_max_lag=3
ticker_idle_period=360
EOF
    service pgqd start

    echo "Yeti cdr DB: cdr, User: ${CDR_USER}, Password: ${CDR_PASSWORD}" >> ${POST_INSTALL}
}

install_yeti_web () {
    check_yeti_repo
    apt update && apt install -y yeti-web nginx
    if [[ "$DB_USER" = "" || "$DB_PASSWORD" = "" ]]
    then
        echo "No ROUTING db username or password. Please specify it manually: /home/yeti-web/config/database.yml" >> ${POST_INSTALL}
        echo "Then make migrations: https://yeti-switch.org/docs/en/installation/web.html" >> ${POST_INSTALL}
    fi
    if [[ "$CDR_USER" = "" || "$CDR_PASSWORD" = "" ]]
    then
        echo "No CDR db username or password. Please specify it manually: /home/yeti-web/config/database.yml" >> ${POST_INSTALL}
        echo "Then make migrations: https://yeti-switch.org/docs/en/installation/web.html" >> ${POST_INSTALL}
    fi

    DB_IP=$(whiptail --title "${TITLE}" --inputbox "Provide routing db IP" 10 60 127.0.0.1 3>&1 1>&2 2>&3)
    exitstatus=$?
    if [[ "$exitstatus" -ne 0 || "$DB_IP" = "" ]]
    then
        DB_IP="127.0.0.1"
    fi

    CDR_IP=$(whiptail --title "${TITLE}" --inputbox "Provide CDR db IP" 10 60 127.0.0.1 3>&1 1>&2 2>&3)
    exitstatus=$?
    if [[ "$exitstatus" -ne 0 || "$CDR_IP" = "" ]]
    then
        CDR_IP="127.0.0.1"
    fi

cat << EOF > /home/yeti-web/config/database.yml
production:
  adapter: postgresql
  encoding: unicode
  database: yeti
  pool: 5
  username: ${DB_USER}
  password: ${DB_PASSWORD}
  host: ${DB_IP}
  schema_search_path: 'gui, public, switch, billing, class4, runtime_stats, sys, logs, data_import'
  port: 5432
  min_messages: notice

secondbase:
  production:
    adapter: postgresql
    encoding: unicode
    database: cdr
    pool: 5
    username: ${CDR_USER}
    password: ${CDR_PASSWORD}
    host: ${CDR_IP}
    schema_search_path: 'cdr, reports, billing'
    port: 5432
    min_messages: notice
EOF


    if (whiptail --title  "${TITLE}" --yesno  "Initialize empty database" 10 60)  then
        echo "Starting db initialization."
        cd /home/yeti-web
        RAILS_ENV=production ./bin/bundle.sh exec rake db:structure:load db:migrate
        RAILS_ENV=production ./bin/bundle.sh exec rake db:second_base:structure:load db:second_base:migrate
        RAILS_ENV=production ./bin/bundle.sh exec rake db:seed
    else
        echo "Initialize DB manualy: https://yeti-switch.org/docs/en/installation/web.html#databases-data-initialization" >> ${POST_INSTALL}
    fi

    rm /etc/nginx/sites-enabled/default
    cp /home/yeti-web/config/yeti-web.dist.nginx /etc/nginx/sites-enabled/yeti
    service nginx restart
    service yeti-web start
    service yeti-cdr-billing@cdr_billing start
    service yeti-delayed-job start

}

install_redis () {
    apt update && apt install -y redis-server
}


whiptail --title "${TITLE}" --clear --yesno "This script will isntall the Yeti-Switch. Continue?" 10 60

case $? in
    0)
        echo "Installing";;
    1)
        echo "Abort the installation"
        exit;;
    255)
        exit;;

esac

whiptail --title "${TITLE}" --separate-output --checklist \
"Select components to install:" 15 33 7 \
1 "Routing database" on \
2 "CDR database" on \
3 "WEB interface" on \
4 "Redis" on \
5 "Management server" on \
6 "SEMS node" on \
7 "Load balancer" off 2>/tmp/results

while read choice
do
    case $choice in
        1)
            echo "Routing database installation"
            install_routing_db
            ;;
        2)
            echo "CDR database installation"
            install_cdr_db
            ;;
        3)
            echo "WEB interface installation"
            install_yeti_web
            ;;
        4)
            echo "Redis installation"
            install_redis
            ;;
        5)
            echo "Management server installation"
            ;;
        6)
            echo "SEMS node installation"
            ;;
        7)
            echo "Load balancer installation"
            ;;
    esac
done < /tmp/results