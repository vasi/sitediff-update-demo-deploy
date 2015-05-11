This is a demo of [SiteDiff](https://github.com/evolvingweb/sitediff), a tool for comparing websites with each other. The demo uses [Docker](https://github.com/docker/docker) to deploy the target website.

The demo shows how SiteDiff can find the bug introduced in the Drupal 7.36 update, where [node types may end up disabled](https://www.drupal.org/node/2465159) under certain conditions.

To perform the demo:
* Run ```make build run``` to deploy the site using Docker
* Visit the site, at http://localhost:9180
* Install SiteDiff: ```gem install sitediff```
* Initialize a SiteDiff configuration: ```sitediff init --rules=yes http://localhost:9180```
* Check that SiteDiff diffs cleanly: ```sitediff diff```
* Update the site to Drupal 7.36: ```make drush DRUSH_CMD='up -y drupal-7.36'```
* Run SiteDiff again, to check for changes: ```sitediff diff```. It should find some changes!
* Run the SiteDiff web UI, for a better view of the changes: ```sitediff serve```
