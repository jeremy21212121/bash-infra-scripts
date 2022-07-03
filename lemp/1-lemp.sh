#!/bin/bash

# exit if any errors are encountered
# we don't want to continue if any steps fail
set -euo pipefail

######################################################
# Check for .env file and load environment variables
echo -e "\nChecking for .env file and required environment variables...\n"

## check
if [[ ! -f .env ]]; then
  echo -e "\nNo .env file found. Please create a .env file with the following properties: DBUSERPASS\n"
  echo "Exiting."
  exit 1
fi

echo -e "\n.env file found, loading variables..."

# load env vars, ignoring lines that start with "#"
export $(grep -v '^#' .env | xargs)

echo -e "...loaded env vars.\n"

echo -e "\nEnsuring required environment variables have been set...\n"

if [ -z "$DBUSERPASS" ]; then
  echo -e "\nDBUSERPASS environment variables is unset or empty. Unable to proceed"
  exit 1
fi

if [ -z "$DOMAINNAME" ]; then
  echo -e "\nDOMAINNAME environment variables is unset or empty. Unable to proceed"
  exit 1
fi

echo -e "... required environment variables have been loaded.\n"

# inject $DBUSERPASS into wordpress.sql
sed -i "s/{{DBUSERPASS}}/$DBUSERPASS/" wordpress.sql
echo -e "\nInjected DBUSERPASS into 'wordpress.sql'\n"

#
#####################################################

CH_L="[~~"
CH_R="~~]"

echo "$CH_L  Installing LEMP stack  $CH_R"
echo ""

# install nginx
echo "Updating package info and installing 'nginx'..."
trap "echo \"...failed to install 'nginx' :(" ERR

sudo apt update

# check if it is already installed
if [[ ! -f /lib/systemd/system/nginx.service ]]; then
  sudo apt install -y nginx;
  echo "";
  echo "...'nginx' has been installed!";
else
  echo "...'nginx' is already installed, skipping this step.";
fi;

echo ""

# stop trapping ERR
trap - ERR

echo -e "\nInstalling PHP and extensions (php-fpm, -mysql, -curl, -gd, -mbstring, -xml, -xmlrpc, -soap, -intl, -zip)..."
echo ""
sudo apt install -y php-fpm php-mysql php-curl php-gd php-mbstring php-xml php-xmlrpc php-soap php-intl php-zip

echo -e "\n... PHP has been installed!\n"

# restart which ever version of php-fpm we have, probably 7.3, to load the extensions
sudo systemctl restart php*-fpm.service

echo -e "\nChecking for 'ufw' firewall..."

# if `ufw` is installed then allow Nginx preset
if [[ -f $(which ufw) ]]; then
  echo "...'ufw' firewall found, adding allow rule for nginx"
  sudo ufw allow 'Nginx HTTP';
else
  echo "...'ufw' firewall not installed, skipping";
fi;
echo ""

# check for `curl`
if [[ ! -f $(which curl) ]]; then
  echo "'curl' is not installed. Installing it now...";
  sudo apt install -y curl;
  echo "...'curl' has been installed :)";
fi;

echo "Checking if 'nginx' is responding on localhost:80..."

# trap error so we can print an error message before exiting
trap "echo -e \"\n...'nginx' doesn't seem to be working :(\" && echo \"exiting\"" ERR

# disable progress meter while still showing errors
NGINX_RESPONSE=$(curl -sS http://localhost)

# stop trapping ERR
trap - ERR

if [[ "$NGINX_RESPONSE" == *"nginx"* ]]; then
  echo "...'nginx' appears to be working!";
else
  echo "...'nginx' doesn't seem to be working :(";
  echo "'nginx' responded with: $NGINX_RESPONSE";
  exit 1;
fi;

echo ""

echo "Installing 'mariadb-server' (open-source MySQL)..."
echo ""

# check if it is already installed
if [[ ! -f $(which mariadb) ]]; then
  sudo apt install -y mariadb-server;
  echo "";
  echo "...'mariadb-server' has been installed!";
  echo ""

  # TODO: mysql_secure_installation is also a bash script.
  #       There is not reason we couldn't patch it to just use the values we want
  #       and avoid this user input, making the script fully automated.
  echo ""
  echo ""
  echo "Securing mariadb installation."
  echo -e "\e[31m This step requires user input. Here is what you need to type for each prompt:\e[0m"
  echo -e "\e[31m 1. press ENTER \e[0m"
  echo -e "\e[31m 2. type N press ENTER \e[0m"
  echo -e "\e[31m 3+ type Y press ENTER to accept the defaults \e[0m"
  echo ""

  sudo mysql_secure_installation

else
  echo "...'mariadb-server' is already installed, skipping this step.";
fi;

echo ""
echo -e "\nCreating database and database user for wordpress by running 'wordpress.sql' ... \n"

sudo mysql < wordpress.sql

echo -e "\n... database configured! \n"

echo -e "Listing wordpress DB. Should see one result: \n"

DB_RESULTS=$(sudo mysql < show_db.sql)
echo "$DB_RESULT"

echo ""

echo -e "Showing permissions for new DB user \"wordpressuser\". Should see permissions for wordpress DB: \n"

DB_PERMISH=$(sudo mysql < show_grants.sql)

echo -e "\n * Investigate further if you didn't see what was described. Yes, I could have done it programatically but I'm tired :P \n \n"

echo "'nginx', 'mariadb' and 'php' have been installed. 'mariadb' has been configured for wordpress. 'ufw' firewall, if present, has been opened for 'nginx'. :D"

echo -e "\nNow we need to configure nginx for your domain: $DOMAINNAME ...\n"

# webroot path
WEBROOTPATH="/var/www/$DOMAINNAME"
# create webroot folder for site
sudo mkdir "$WEBROOTPATH"
# set current user as owner
sudo chown -R $USER:$USER "$WEBROOTPATH"

# get php-fpm string including version, eg. php7.3-fpm
PHPFPM=$(sudo systemctl status php*-fpm.service | head -n 1 | sed 's/^..\(php...-fpm\).*/\1/')
# replace PHP-FPM version from nginx template
sed -i "s/{{PHPFPM}}/$PHPFPM/g" site-config.nginx
# replace domain name from nginx template
sed -i "s/{{DOMAINNAME}}/$DOMAINNAME/g" site-config.nginx

NGINXCONF=$(echo -n $DOMAINNAME | sed 's/\./_/')

sudo cp site-config.nginx /etc/nginx/sites-available/$NGINXCONF

sudo ln -s /etc/nginx/sites-available/$NGINXCONF /etc/nginx/sites-enabled/

echo -e "\nEnsuring nginx conf is valid...\n"

sudo nginx -t

echo -e "\n... config is valid. Restarting nginx service.\n"
sudo systemctl restart nginx

echo -e "\nTesting NGINX PHP-FPM is working...\n"

# create a php file to try to render
echo "<?php phpinfo() ?>" > $WEBROOTPATH/index.php

# make HTTP request and check response
trap "echo -e \"\n...'nginx php-pfm' doesn't seem to be working :(\" && echo \"exiting\"" ERR

# disable progress meter while still showing errors. pass Host header for our new domain.
PHP_RESPONSE=$(curl -sS -H "Host: $DOMAINNAME" http://localhost)

# stop trapping ERR
trap - ERR

PHP_EXPECTED="phpinfo()</title>"

if [[ "$PHP_RESPONSE" == *"$PHP_EXPECTED"* ]]; then
  echo -e "...'nginx php-fpm' appears to be working! \n";
else
  echo -e "...'nginx php-fpm' doesn't seem to be working :(\n";
  echo "'nginx' responded with:\n$PHP_RESPONSE\n\n";
  exit 1;
fi;

# remove test php file
rm $WEBROOTPATH/index.php

# download wordpress
