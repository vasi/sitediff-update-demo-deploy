FROM ubuntu:12.04

# for busting docker caches, simply increment this dummy variable
ENV docker_cache_id 1

# Detect a squid deb proxy on the docker host
ADD scripts/detect_squid_deb_proxy /var/build/scripts/detect_squid_deb_proxy
RUN /var/build/scripts/detect_squid_deb_proxy

# Configure apt and run apt-get update
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update

# Disable initctl as it conflicts with docker build,
RUN dpkg-divert --local --rename --add /sbin/initctl
RUN ln -s -f /bin/true /sbin/initctl

# Install all the things. Best to have this at the start, for better image
# caching.
RUN apt-get install -y wget git gzip pwgen \
  python-setuptools apache2 mysql-server php5-cli \
  libapache2-mod-php5 php5-mysql php5-curl php5-gd \
  openssh-server cron logrotate sysklogd exim4 \
  vim nano pv curl make ack-grep man-db python-software-properties sudo
# Fix ack-grep name
RUN dpkg-divert --local --divert /usr/bin/ack --rename --add /usr/bin/ack-grep

# Generate some locales
RUN locale-gen en_US.UTF-8 en_CA.UTF-8

# install memcached
RUN apt-get install -y memcached php5-memcache
ADD files/supervisor/memcached.conf /etc/supervisor/conf.d/memcached.conf

# Install xhprof
RUN apt-get install -y php-pear && pecl install -f xhprof
RUN echo "extension=xhprof.so\nxhprof.output_dir=/tmp" > /etc/php5/conf.d/xhprof.ini

RUN apt-get install -y php5-xdebug
ADD assets/docker_host_ip /tmp/docker_host_ip
RUN (echo xdebug.remote_enable=1; echo xdebug.remote_host=$(cat /tmp/docker_host_ip)) >> /etc/php5/conf.d/xdebug.ini

# Install Composer and drush
RUN mkdir -p /usr/share/composer
ENV COMPOSER_HOME /opt
# Composer server is slow, cache composer.phar
ADD assets/composer.phar /usr/local/bin/composer
RUN chmod +x /usr/local/bin/composer
RUN composer global require drush/drush:dev-master
RUN ln -sf $COMPOSER_HOME/vendor/drush/drush/drush /usr/local/bin/drush

# Install PHP Code sniffer and Drupal{,Practice,Secure} standards
RUN composer global require "squizlabs/php_codesniffer:*" "drupal/coder:>7"
RUN ln -s $COMPOSER_HOME/vendor/bin/phpcs /usr/local/bin/phpcs
RUN ln -s $COMPOSER_HOME/vendor/drupal/coder/coder_sniffer/Drupal $COMPOSER_HOME/vendor/squizlabs/php_codesniffer/CodeSniffer/Standards/Drupal
RUN mkdir -p /var/build/phpcs
RUN git clone https://github.com/klausi/drupalpractice /var/build/phpcs/drupalpractice
RUN ln -s /var/build/phpcs/drupalpractice/DrupalPractice $COMPOSER_HOME/vendor/squizlabs/php_codesniffer/CodeSniffer/Standards/DrupalPractice
RUN git clone git://git.drupal.org/sandbox/coltrane/1921926.git /var/build/phpcs/drupalsecure
RUN ln -s /var/build/phpcs/drupalsecure/DrupalSecure/ $COMPOSER_HOME/vendor/squizlabs/php_codesniffer/CodeSniffer/Standards/DrupalSecure
ADD scripts/drupalcs /var/build/scripts/drupalcs
RUN ln -s /var/build/scripts/drupalcs /usr/local/bin/drupalcs

# Install supervisor
RUN easy_install supervisor

# Create docker user, set UID/GID to match host
# This allows us to use mounted volumes without causing permission conflicts
ADD assets/uid /tmp/uid
ADD assets/gid /tmp/gid
# sets www-data gid to /tmp/gid, if not conflicting (eg root)
RUN getent group $(cat /tmp/gid) || groupmod -g $(cat /tmp/gid) www-data
RUN useradd -m -g www-data -s /bin/bash -G sudo docker
# sets docker uid to /tmp/uid, if not conflicting (eg root)
RUN getent passwd $(cat /tmp/uid) || usermod -u $(cat /tmp/uid) docker
RUN rm /tmp/uid /tmp/gid
RUN echo '%sudo ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/override
RUN chmod 0440 /etc/sudoers.d/override
RUN echo 'cd /drupal' >> /home/docker/.bashrc

# Set pubkey for SSH
RUN install -d -m 0700 /root/.ssh
ADD assets/authorized_keys /root/.ssh/authorized_keys
RUN chmod 0600 /root/.ssh/authorized_keys
RUN install -d -m 0700 -o docker /home/docker/.ssh
ADD assets/authorized_keys /home/docker/.ssh/authorized_keys
RUN chmod 0600 /home/docker/.ssh/authorized_keys
RUN chown docker /home/docker/.ssh/authorized_keys

# Configure supervisor
RUN mkdir -p /etc/supervisor/conf.d
ADD files/supervisor/supervisord.conf /etc/supervisord.conf

# Configure ssh server, cron, syslog
RUN mkdir /var/run/sshd
ADD files/supervisor/syslog.conf /etc/supervisor/conf.d/syslog.conf

# Configure apache
RUN rm /etc/apache2/sites-enabled/*
ADD files/supervisor/apache.conf /etc/supervisor/conf.d/apache.conf

# Configure mysql server
# Install `mysql_start' and `mysql_stop` scripts for mysql provisioning steps
ADD scripts/mysql_start /usr/local/bin/mysql_start
RUN chmod +x /usr/local/bin/mysql_start
ADD scripts/mysql_stop /usr/local/bin/mysql_stop
RUN chmod +x /usr/local/bin/mysql_stop
ADD scripts/mysql_wait /usr/local/bin/mysql_wait
RUN chmod +x /usr/local/bin/mysql_wait
ADD files/supervisor/mysql.conf /etc/supervisor/conf.d/mysql.conf

# Set MySQL root password to the contents of a provided secret file, and
# Create an app user with full privileges on a given database using
# `mysql_{start,stop}'.
ADD assets/mysql_root_pass /tmp/mysql_root_pass
ADD assets/mysql_drupal_pass /tmp/mysql_drupal_pass
RUN mysql_start && \
    mysqladmin -u root password $(cat /tmp/mysql_root_pass) && \
    echo "CREATE DATABASE drupal; \
          GRANT ALL ON drupal.* TO 'drupal'@'localhost' \
          IDENTIFIED BY '$(cat /tmp/mysql_drupal_pass)'; \
          FLUSH PRIVILEGES;" | mysql -u root -p$(cat /tmp/mysql_root_pass) && \
    mysql_stop
RUN rm -f /tmp/mysql_root_pass

# Configure exim4 MTA
RUN echo 'dc_eximconfig_configtype=internet' >> /etc/exim4/update-exim4.conf.conf && dpkg-reconfigure -f noninteractive exim4-config

# Populate a MySQL database from a dump file
# FIXME: Turn off autocommit? Other speed hacks?
ADD assets/drupal.sql /tmp/drupal.sql
RUN mysql_start && \
    pv -f /tmp/drupal.sql | \
      mysql -u drupal -p$(cat /tmp/mysql_drupal_pass) -D drupal && \
    mysql_stop
RUN rm /tmp/mysql_drupal_pass

# Configure an Apache 2.2 virtual host for Drupal
RUN a2enmod rewrite
ADD files/drupal_apache_vhost /etc/apache2/sites-available/drupal
RUN a2ensite drupal

# Add code, handle silly permissions issue
ADD assets/code /tmp/code
ADD assets/files /tmp/files
ADD assets/settings.local.php /tmp/code/sites/default/settings.local.php
RUN cp -R /tmp/files /tmp/code/sites/default/ && \
  chmod -R 000 /tmp/code && chmod -R g-s /tmp/code && \
  chown -R docker:www-data /tmp/code && \
  chmod -R u=rwX,g=rX /tmp/code && \
  chown -R docker:www-data /tmp/code/sites/default/files && \
  chmod -R ug+w /tmp/code/sites/default/files && \
  find /tmp/code/sites/default/files -type d -print0 | xargs -0 chmod g+s && \
  mkdir /drupal && \
  cp -a /tmp/code /drupal/site && \
  rm -rf /tmp/code /tmp/files

# Setup Drupal cron
RUN echo "0 *  *    *  *  /usr/bin/env COLUMNS=72 /usr/local/bin/drush --root=/drupal --uri=http://default --quiet cron" | crontab -u www-data -

# Setup drupal
ADD assets/drupal_admin_pass /tmp/drupal_admin_pass
ADD assets/site_name /tmp/site_name
ADD scripts/provision.sh /var/build/scripts/provision.sh

# XXX: "drush status" must first be run as root to download Console_Table
RUN supervisord -c /etc/supervisord.conf && mysql_wait \
    # && drush -r /drupal status \
    && su docker -c "bash /var/build/scripts/provision.sh" \
    && supervisorctl stop mysql
RUN rm /tmp/drupal_admin_pass

# Add things we didn't want supervisor to touch before
ADD files/supervisor/sshd.conf /etc/supervisor/conf.d/sshd.conf
ADD files/supervisor/cron.conf /etc/supervisor/conf.d/cron.conf

CMD ["supervisord",  "-c", "/etc/supervisord.conf", "-n"]
