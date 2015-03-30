#!/bin/bash
set -x

cd /drupal

drush site-install -v -y --account-name=admin --account-pass=$(cat /tmp/drupal_admin_pass) --site-name=$(cat /tmp/site_name)

# Set admin password
test -f /tmp/drupal_admin_pass && drush upwd admin --password=***REMOVED***

# Make it nice to use
drush vset theme_default bartik
drush vset admin_theme bartik
drush dis -y toolbar overlay
drush en -y admin_menu devel
