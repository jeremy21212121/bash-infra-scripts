#!/bin/bash

####
#
#  Create non-root user for SSH access. DO droplets only allow root SSH access by default.
#
#  Creates the user $USRNAME with passwordless sudo. Needs to be run as root (duh).
#
####

# exit if any errors are encountered
# we don't want to continue if any steps fail
set -euxo pipefail
# echo failure message on error so it is obvious that the script did not complete.
trap "echo -e \" *\n **\n *** Error! Script did not complete. See above for last command executed *** \"" ERR


# Desired username for new user
USRNAME=debian

echo -e "\nAdding non-root user '$USRNAME' for SSH access...\n"

# Create the user
adduser --quiet --disabled-password $USRNAME

# create .ssh dir
mkdir /home/$USRNAME/.ssh

# give owner full permissions and none to anybody else
chmod 0700 /home/$USRNAME/.ssh/

# copy the contents of root .ssh folder so we get the authorized_keys
cp -Rfv /root/.ssh /home/$USRNAME/

# give the new user ownership of his home folder recursively
chown -R $USRNAME:$USRNAME /home/$USRNAME/.ssh

# add user to sudo group
gpasswd -a $USRNAME sudo

# add user to sudoers file for passwordless-sudo priveleges
echo "$USRNAME ALL=(ALL) NOPASSWD: ALL" | (EDITOR="tee -a" visudo)

echo -e "\n ...user has been added. Restarting SSH service now. Re-connect as new user: $USRNAME \n"

# restart ssh
systemctl restart ssh

# stop trapping ERR
trap - ERR
