# Kitchen::Docker

A Test Kitchen Driver for Docker. This driver utilizes the
[docker-api](https://github.com/swipely/docker-api) gem as the docker
client making a CLI client unnecessary. If you would prefer a docker
driver which uses the docker CLI you should look at the original
[kitchen-docker](https://github.com/portertech/kitchen-docker) from
which this fork originated. 

Substantial credit for this driver goes to Sean Porter for the CLI
implementation & his support in developing the docker-api based version.
We ultimately decided it would be best to have two versions so folks
could choose to use the CLI or docker-api based client. 

## Requirements

* [Docker][docker_getting_started] server. This driver does not require the docker cli to be installed. 

NOTE: As of version 0.4.0 of this driver, you must be running Docker
v0.9 or higher. This is due to a backward incompatible change in the
docker-api gem this driver uses. If you must use an older Docker version
you should run v0.3.0 or lower of this driver. 

## Installation and Setup

Please read the Test Kitchen [docs][test_kitchen_docs] for more details.

Example `.kitchen.local.yml`:

```
---
driver_plugin: docker

platforms:
- name: ubuntu
  run_list:
  - recipe[apt]
- name: centos
  driver_config:
    image: centos
    platform: rhel
  run_list:
  - recipe[yum]
```

## Default Configuration

This driver can determine an image and platform type for a select number of
platforms. Currently, the following platform names are supported:

```
---
platforms:
- name: ubuntu-12.04
- name: centos-6.4
```

This will effectively generate a configuration similar to:

```
---
platforms:
- name: ubuntu-12.04
  driver_config:
    image: ubuntu:12.04
    platform: ubuntu
- name: centos-6.4
  driver_config:
    image: centos:6.4
    platform: centos
```

## Configuration

* [socket](#socket) - Configure the socket to connect to Docker daemon
* [image](#image) - base image used for Docker container
* [platform](#platform) - platform of Docker container
* [require_chef_omnibus](#require_chef_omnibus) - Install Chef?
* [container_name](#container_name) - Customize container name
* [disable_upstart](#disable_upstart) - Disable upstart tweaks during container build
* [dockerfile](#dockerfile) - Specify a custom Dockerfile 
* [provision_command](#provision_command) - List of RUN commands during container build
* [remove_images](#remove_images) - Remove intermediate images after image creation
* [run_command](#run_command) - Command to run at container start
* [memory](#memory) - Memory limits for container
* [cpu](#cpu) - CPU limits for container
* [volume](#volume) - Volumes to mount in container
* [dns](#dns) - DNS servers to configure in container
* [forward](#forward) - Ports to forward to running container
* [privileged](#privileged) - Run container in privileged mode

### socket

The Docker daemon socket to use. By default, Docker will listen on
`unix:///var/run/docker.sock`, and no configuration here is required. If
Docker is binding to another host/port or Unix socket, you will need to set
this option. If a TCP socket is set, its host will be used for SSH access
to suite containers.

Examples:

```
  socket: unix:///tmp/docker.sock
```

```
  socket: tcp://docker.example.com:4242
```

### image

The Docker image to use as the base for the suite containers. You can find
images using the [Docker Index][docker_index].

The default will be determined by the Platform name, if a default exists
(see the Default Configuration section for more details). If a default
cannot be computed, then the default value is `base`, an official Ubuntu
[image][docker_default_image].

### platform

The platform of the chosen image. This is used to properly bootstrap the
suite container for Test Kitchen. Kitchen Docker currently supports:

* `debian` or `ubuntu`
* `rhel` or `centos`

The default will be determined by the Platform name, if a default exists
(see the Default Configuration section for more details). If a default
cannot be computed, then the default value is `ubuntu`.

### require\_chef\_omnibus

Determines whether or not a Chef [Omnibus package][chef_omnibus_dl] will be
installed. There are several different behaviors available:

* `true` - the latest release will be installed. Subsequent converges
  will skip re-installing if chef is present.
* `latest` - the latest release will be installed. Subsequent converges
  will always re-install even if chef is present.
* `<VERSION_STRING>` (ex: `10.24.0`) - the desired version string will
  be passed the the install.sh script. Subsequent converges will skip if
  the installed version and the desired version match.
* `false` or `nil` - no chef is installed.

The default value is `true`.

### container\_name

Allows for specification of a container name which will be visible in
`docker ps`. This makes tracking down containers associated w/ cookbook
testing easier. 

This defaults to a calculated value which is a combination of 4 attributes:

- platform name
- CWD basename (where kitchen was run from)
- suite name
- hostname of initiating system

For example, a cookbook named `test-gem` has this name when run from my
laptop on a remote system:

`ubuntu-12.04..test-gem..default..anichols-mbr`

### disable\_upstart

Disables upstart on Debian/Ubuntu containers, as many images do not
support a working upstart.

The default value is `true`.

### dockerfile

This allows you to point to a specific dockerfile used to prepare an
image for testing under test-kitchen. It is expected that this
Dockerfile will do everything necessary to configure the image for use
by kitchen-docker-api including:

* Setup the username & password kitchen-docker-api expects to use
* Provide the user with NOPASSWD sudo rights
* Ensure ssh is installed and will work at container start
* If using /sbin/init as `run_command` ensure ssh is started on start
* Install any requisite packages
* Specify a CMD, the driver will still use `config[:run_command]` at
  container start but docker requires a CMD is specified

If you specify a dockerfile path kitchen-docker-api will take no action
to make sure your image is setup correctly, it will simply build an
image using the specified dockerfile & run that image. 

Note that the dockerfile is parsed as ERB and the `config` hash from
`kitchen-docker-api` is passed into the template so any configuration in
your yml may be referenced inside the Dockerfile. This allows you to
place conditionals and other logic directly in your Dockerfile.

This parameter supports 3 types of values:
* File path (eg. `Dockerfile` or `/path/to/Dockerfile`)
* Http URL (eg. `http://someurl.com/Dockerfile` )
* `internal` will use the internal Dockerfile generator

Default value: `internal`

Example Dockerfile:
```erb
FROM tianon/centos:6.5
RUN yum clean all
RUN yum install -y sudo openssh-server openssh-clients curl
RUN ssh-keygen -t rsa -f /etc/ssh/ssh_host_rsa_key
RUN ssh-keygen -t dsa -f /etc/ssh/ssh_host_dsa_key
RUN mkdir -p /var/run/sshd
RUN useradd -d /home/<%= @username %> -m -s /bin/bash <%= @username %>
RUN echo <%= "#{@username}:#{@password}" %> | chpasswd
RUN echo '<%= @username %> ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
CMD [ "/usr/sbin/sshd", "-D", "-o", "UseDNS=no", "-o", "UsePAM=no" ]
```

### provision\_command

Custom command(s) to be run when provisioning the base for the suite containers.

Examples:

```
  provision_command: curl -L https://www.opscode.com/chef/install.sh | bash
```

```
  provision_command:
    - apt-get install dnsutils
    - apt-get install telnet
```

```
driver_config:
  provision_command: curl -L https://www.opscode.com/chef/install.sh | bash
  require_chef_omnibus: false
```

### remove\_images

This determines if intermediate images are removed after container
creation. Equivalent to `-rm` docker cli option.

The default value is `true`.

### run_command

Sets the command used to run the suite container.

The default value is `/usr/sbin/sshd -D -o UseDNS=no -o UsePAM=no`.

Examples:

```
  run_command: /sbin/init
```

### memory

Sets the memory limit for the suite container in bytes. Otherwise use Dockers
default. You can read more about `memory.limit_in_bytes` [here][memory_limit].

### cpu

Sets the CPU shares (relative weight) for the suite container. Otherwise use
Dockers defaults. You can read more about cpu.shares [here][cpu_shares].

### volume

Adds a data volume(s) to the suite container.

Examples:

```
  volume: /ftp
```

```
  volume:
  - /ftp
  - /srv
```

## dns

Adjusts `resolv.conf` to use the dns servers specified. Otherwise use
Dockers defaults.

Examples:

```
  dns: 8.8.8.8
```

```
  dns:
  - 8.8.8.8
  - 8.8.4.4
```

### forward

Set suite container port(s) to forward to the host machine. You may specify
the host (public) port in the mappings, if not, Docker chooses for you.

Examples:

```
  forward: 80
```

```
  forward:
  - 22:2222
  - 80:8080
```

### hostname

Set the suite container hostname. Otherwise use Dockers default.

Examples:

```
  hostname: foobar.local
```

### privileged

Run the suite container in privileged mode. This allows certain functionality
inside the Docker container which is not otherwise permitted.

The default value is `false`.

Examples:

```
  privileged: true
```

## Development

* Source hosted at [GitHub][repo]
* Report issues/questions/feature requests on [GitHub Issues][issues]

Pull requests are very welcome! Make sure your patches are well tested.
Ideally create a topic branch for every separate change you make. For
example:

1. Fork the repo
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

## Authors

Created and maintained by [Aaron Nichols][author] (<anichols@trumped.org>)

Original kitchen-docker by [Sean Porter](<portertech@gmail.com>)

## License

Apache 2.0 (see [LICENSE][license])


[author]:                 https://github.com/adnichols
[issues]:                 https://github.com/adnichols/kitchen-docker-api/issues
[license]:                https://github.com/adnichols/kitchen-docker-api/blob/master/LICENSE
[repo]:                   https://github.com/adnichols/kitchen-docker-api
[docker_getting_started]: http://www.docker.io/gettingstarted/
[docker_upstart_issue]:   https://github.com/dotcloud/docker/issues/223
[docker_index]:           https://index.docker.io/
[docker_default_image]:   https://index.docker.io/_/base/
[test_kitchen_docs]:      http://kitchen.ci/docs/getting-started/
[chef_omnibus_dl]:        http://www.opscode.com/chef/install/
[cpu_shares]:             https://docs.fedoraproject.org/en-US/Fedora/17/html/Resource_Management_Guide/sec-cpu.html
[memory_limit]:           https://docs.fedoraproject.org/en-US/Fedora/17/html/Resource_Management_Guide/sec-memory.html
