#!/bin/bash
set -x

cd /drupal/site

drush site-install -v -y --account-name=admin --account-pass=$(cat /tmp/drupal_admin_pass) --site-name=$(cat /tmp/site_name)

# Set admin password
test -f /tmp/drupal_admin_pass && drush upwd admin --password=***REMOVED***

# Make it nice to use
drush vset theme_default bartik
drush vset admin_theme bartik
drush dis -y toolbar overlay
drush en -y admin_menu devel

# Save the old DB
drush sql-dump > /drupal/orig.sql

# Run an update script
UPDATE_SCRIPT="/drupal/site/scripts/update-container.sh"
if [ -f "$UPDATE_SCRIPT" ]; then
  bash $UPDATE_SCRIPT
fi
