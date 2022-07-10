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

if [ -z "$LE_EMAIL" ]; then
  echo -e "\nLE_EMAIL environment variables is unset or empty. This is needed for important updates from Let's Encrypt"
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
  sudo ufw allow 'Nginx Full';
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
echo """$DB_RESULTS"""

echo ""

echo -e "Showing permissions for new DB user \"wordpressuser\". Should see permissions for wordpress DB: \n"

DB_PERMISH=$(sudo mysql < show_grants.sql)

echo """$DB_PERMISH"""

echo -e "\n * Investigate further if you didn't see what was described. Yes, I could have done it programatically but I'm tired :P  *\n \n"

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

echo -e "Removing temp PHP file.\n"

# remove test php file
rm $WEBROOTPATH/index.php


######################################################################
# Setup TLS via let's encrypt
######################################
echo -e "\nEnabling TLS with Let's Encrypt. Cert will be renewed automagically....\n\nFirst we will install certbot deps...\n\n"

sudo apt install -y python3-acme python3-certbot python3-mock python3-openssl python3-pkg-resources python3-pyparsing python3-zope.interface

echo -e "\n\nInstalling certbot with nginx plugin...\n\n"

sudo apt install -y python3-certbot-nginx

# do the thing! This will get us a cert valid for $DOMAINNAME and www.$DOMAINNAME and auto updates.
# We are using the following options:
# -n is for non-interactive,
# --agree-tos is obvious,
# --redirect configures redirect to HTTPS,
# -m $LE_EMAIL env var should contain your email address to be notified if your cert is going to expire
echo -e "\n\nWe are about to configure certbot to get our cert, autorenew cert as needed and config nginx to redirect to HTTPS.\n\n***Check the output carefully to see that it works***\n\n"

sudo certbot --nginx -n --agree-tos --redirect -m "$LE_EMAIL" -d "$DOMAINNAME" -d "www.$DOMAINNAME"

echo -e "\n\nTest the autorenewal process with a dry run. Check the following output to see that it succeeds:\n\n\n"

sudo certbot renew --dry-run

echo -e "\n\n\n...Certbot is configured and TLS is enabled!\n\n"

###################################################################
# Install/configure wordpress
######################################

# download wordpress
echo -e "Downloading WordPress...\n"

mkdir /tmp/wp

curl -sSLo /tmp/wp/latest.tar.gz https://wordpress.org/latest.tar.gz

echo -e "...WordPress downloaded to /tmp/wp\n\nUnzipping WordPress...\n"

tar xzf /tmp/wp/latest.tar.gz -C /tmp/wp

echo -e "Configuring wp-config.php...\n"

# temporary path for wp-config.php. We'll copy to whole parent directory into place later
TMP_WPCFG_PATH=/tmp/wp/wordpress/wp-config.php

cp /tmp/wp/wordpress/wp-config-sample.php $TMP_WPCFG_PATH

# set required values in wp-config.php
# we are using `wordpress` as DB name and `wordpressuser` as DB username
sed -i "s/database_name_here/wordpress/" $TMP_WPCFG_PATH
sed -i "s/username_here/wordpressuser/" $TMP_WPCFG_PATH
sed -i "s/password_here/$DBUSERPASS/" $TMP_WPCFG_PATH

# We need to remove the dummy key/salt lines and replace them with random keys/salts
# We'll find the line number where this string appears so we can remove lines from there.
WPC_START_STRING="define( 'AUTH_KEY',         'put your unique phrase here' );"
WPC_END_STRING="define( 'NONCE_SALT',       'put your unique phrase here' );"
# get line numbers of above strings
WPC_START=$(sed -n "/$WPC_START_STRING/=" $TMP_WPCFG_PATH)
WPC_END=$(sed -n "/$WPC_END_STRING/=" $TMP_WPCFG_PATH)

# placeholder string
WPC_PLACEHOLDER="{{PLACEHOLDER}}"

# remove the key/salt section, to be replaced later with random values
sed -i "$WPC_START,$WPC_END""d" $TMP_WPCFG_PATH

# add placeholder at desired location so we can insert new keys/salts there
sed -i "$WPC_START"" i $WPC_PLACEHOLDER" $TMP_WPCFG_PATH

# download keys/salts into a temp file
TMP_SALT_PATH=/tmp/wp/wordpress/salt.txt
curl -sS https://api.wordpress.org/secret-key/1.1/salt > $TMP_SALT_PATH

# add salts/keys after placeholder
sed -e "/$WPC_PLACEHOLDER/r$TMP_SALT_PATH" $TMP_WPCFG_PATH > $TMP_WPCFG_PATH

# remove placeholder
sed -i "s/$WPC_PLACEHOLDER//" $TMP_WPCFG_PATH

rm $TMP_SALT_PATH

echo -e "\n...Done configuring wp-config.php!\n"

# move wordpress files into place. why did we put them in /tmp first? who knows!
sudo cp -a /tmp/wp/wordpress/. $WEBROOTPATH

# set WEBROOT folder ownership to that of nginx so auto updates hopefully work
sudo chown -R www-data:www-data $WEBROOTPATH

# Remove temp wordpress files now that we have copied them
rm -rf /tmp/wp

# huzzah! we should probably be done now. We need to setup wordpress manually via web browser from here.
echo -e "\n\nWordPress installation is complete! Visit $DOMAINNAME to finish config via web browser. Do it now before somebody else does it for you :D\n\n"

echo -e "We are all done here. If you are reading this, congrats! This whole file executed without an error and without encountering an undefined variable.\n\n"
