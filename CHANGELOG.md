## 0.4.0

* Bump docker-api to 0.10.x. This version is incompatible with docker <
  0.9, so be sure you are running 0.9+ before using this version.
* Default to enabling Tty option in docker

## 0.3.0

* Added support for the `dockerfile` config option
* Added config TOC to README

## 0.2.2

* Added epoch seconds to name to create uniqueness across multiple runs.
  Prevents a failing run from having a name collision.

## 0.2.1

* Discovered issue where client was trying to remove images after the
  container was destroyed, triggering a docker error

## 0.2.0

* Added support for container_name
* Pulled in disable_upstart from kitchen-docker

## 0.1.0 

* Initial fork from kitchen-docker
* Supports docker version < 0.9
