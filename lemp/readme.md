# LEMP stack + Wordpress for Debian

Scripts for installing/configuring LEMP stack with Wordpress. This is just for my benefit, not intended to be used by anybody else. It definitely takes more time than just banging out the commands, but it is also more fun. That's right, I actually enjoy writing bash scripts and yes, I am a lot of fun at parties.

## WHy

I had to spin up a new web server for a client so I decided to script the process to make it easily repeatable. I know it isn't as hip as using terraform or ansible, but it is practical for my needs and saves me having to learn a new tool in my limited spare time.

## How

The target is a Debian 11 VM on Digital Ocean, but it should work for other providers and Debian-based distros.

This isn't fully automated. There are a few prompts that require user input as part of `mysql_secure_installation`, but instructions are printed ahead of time. Accordingly, this can be run over SSH but it is not fully unattended. `mysql_secure_installation` is actually itself a bash script, so it wouldn't be too difficult to remove the prompts and hard-code the options I want, so maybe I will do that in the future.

## Overview

These scripts perform the following tasks:

- Create a non-root user with passwordless-sudo for SSH access (DO provides SSH as root only by default)
- Installs/configures `unattended-upgrades` to automatically install security updates
- Installs LEMP stack (nginx, mariadb, php-fpm) and some PHP extensions commonly used by wordpress plugins
- Creates a database for wordpress to use
- Installs latest Wordpress (it is available in the Debian repos, but the version is old and I'm concerned about plugin compatibility)

Still work-in-progress:

- Configure site in nginx
- Setup TLS with Let's Encrypt

## Environment variables

Create a `.env` file with the following key/values:

- `DBUSERPASSWORD` - For the mariadb user password. We will look for this value and swap it into `wordpress.sql`
- `DOMAINNAME` - The domain name of the site. We're assuming it's a second level domain (eg. `thing.com`). No `www.`, that is so 20th century. If you need to use a third level domain you are SOL. 

