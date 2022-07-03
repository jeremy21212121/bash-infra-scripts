--- replace $DBUSERPASS with the desired password

CREATE DATABASE wordpress DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;

CREATE USER 'wordpressuser'@'localhost' IDENTIFIED WITH mysql_native_password BY '{{DBUSERPASS}}';

GRANT ALL ON wordpress.* TO 'wordpressuser'@'localhost';

FLUSH PRIVILEGES;
