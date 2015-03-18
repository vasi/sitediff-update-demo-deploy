#!/bin/bash
set -x

cd /drupal

drush site-install -v -y --account-name=admin --account-pass=$(cat /tmp/drupal_admin_pass) --site-name=AllSeen-CAWT

 Set admin password
 test -f /tmp/drupal_admin_pass && drush upwd admin --password=$(cat /tmp/drupal_admin_pass)
