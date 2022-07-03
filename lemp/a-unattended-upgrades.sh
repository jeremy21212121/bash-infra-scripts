#!/bin/bash

####
#
#  Automatically install updates via 'unattended-upgrades'
#
#  Installs and configures package for security updates only
#
####

# exit if any errors are encountered
# we don't want to continue if any steps fail
set -euo pipefail

#####
# Set variables

PACKAGE="unattended-upgrades"
# this is the file that makes it run.
AUTO_FILE="/etc/apt/apt.conf.d/20auto-upgrades"
# config lines we need
CONFIG1="APT::Periodic::Update-Package-Lists \"1\";"
CONFIG2="APT::Periodic::Unattended-Upgrade \"1\";"
CONFIG3="APT::Periodic::Download-Upgradeable-Packages \"1\";"
CONFIG4="APT::Periodic::AutocleanInterval \"7\";"
CONFIG_ARRAY=( "$CONFIG1" "$CONFIG2" "$CONFIG3" "$CONFIG4" )

RED="\e[31m"
ENDRED="\e[0m"
#
#####

echo ""
echo "Installing and configuring automatic security updates via '$PACKAGE'"
echo ""

# ensure package is installed
if [[ ! -f $(which $PACKAGE) ]]; then
  sudo apt install -y $PACKAGE;
else
  echo "$PACKAGE is already installed" && echo "";
fi;

# Check if it exists, if not create it.
if [[ ! -f $AUTO_FILE ]]; then
  echo "" && echo "auto-upgrades config file doesn't exist. Creating it now." && echo ""
  sudo touch $AUTO_FILE;
fi;

echo "Configuring to run daily..." && echo ""

# loop over config array
for CFG_STRING in "${CONFIG_ARRAY[@]}"
do
  # check if the file already contains the line to avoid duplication
  if ! grep -qE "^$CFG_STRING$" "$AUTO_FILE"; then
    # option doesn't exist in file, add it
    echo "Adding config:";
    echo $CFG_STRING | sudo tee -a $AUTO_FILE;
    echo "";
  else
    echo "Config option already exists, skipping: $CFG_STRING" && echo "";
  fi;
done

echo "Done! '$PACKAGE' is now configured to install security updates daily"
