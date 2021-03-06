# -*- encoding: utf-8 -*-
#
# Copyright (C) 2014, Aaron Nichols
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'kitchen'
require 'json'
require 'docker'
require 'socket'


module Kitchen
  module Driver
    # Docker driver
    class Docker < Kitchen::Driver::SSHBase

      default_config :socket,        ::Docker.url
      default_config :privileged,    false
      default_config :remove_images, true
      default_config :run_command,   '/usr/sbin/sshd -D -o UseDNS=no -o UsePAM=no'
      default_config :username,      'kitchen'
      default_config :password,      'kitchen'
      default_config :read_timeout,  300
      default_config :dockerfile,    'internal'

      default_config :image do |driver|
        driver.default_image
      end

      default_config :platform do |driver|
        driver.default_platform
      end

      default_config :container_name do |driver|
        driver.default_container_name
      end

      default_config :disable_upstart, true

      def initialize(*args)
        super(*args)
        @docker_connection = ::Docker::Connection.new(config[:socket], :read_timeout => config[:read_timeout])
        if Kitchen.logger.debug?
          ::Docker.logger = Kitchen.logger
        end
      end

      def default_container_name
        platform = instance.platform.name
        suite = instance.suite.name
        cookbook = instance.provisioner.instance_variable_get("@config")[:kitchen_root].split('/').last
        hostname = Socket.gethostname.split('.').first
        ts = Time.now().strftime("%s")
        [platform,cookbook,suite,hostname,ts].join('..')
      end

      def default_image
        platform, release = instance.platform.name.split('-')
        release ? [platform, release].join(':') : platform
      end

      def default_platform
        platform, release = instance.platform.name.split('-')
        release ? platform : 'ubuntu'
      end

      def create(state)
        state[:image_id] = create_image(state) unless state[:image_id]
        state[:container_id] = create_container(state) unless state[:container_id]
        state[:hostname] = container_ssh_host
        state[:port] = container_ssh_port(state)
        wait_for_sshd(state[:hostname], nil, :port => state[:port])
      end

      def destroy(state)
        destroy_container(state) if state[:container_id]
      end

      protected

      def socket_uri
        URI.parse(config[:socket])
      end

      def remote_socket?
        config[:socket] ? %w{tcp http https}.include?(socket_uri.scheme) : false
      end

      def dockerfile
        if config[:dockerfile] == 'internal'
          return internal_dockerfile
        else
          return fetch_dockerfile
        end
      end

      def internal_dockerfile
        from = "FROM #{config[:image]}"
        
        env_variables = ''
        if config[:http_proxy]
          env_variables << "ENV http_proxy #{config[:http_proxy]}\n" 
          env_variables << "ENV HTTP_PROXY #{config[:http_proxy]}\n"
        end
        
        if config[:https_proxy]
          env_variables << "ENV https_proxy #{config[:https_proxy]}\n" 
          env_variables << "ENV HTTPS_PROXY #{config[:https_proxy]}\n"
        end
        
        if config[:no_proxy]
          env_variables << "ENV no_proxy #{config[:no_proxy]}\n"
          env_variables << "ENV NO_PROXY #{config[:no_proxy]}\n"
        end
        
        platform = case config[:platform]
        when 'debian', 'ubuntu'
          disable_upstart = <<-eos
            RUN dpkg-divert --local --rename --add /sbin/initctl
            RUN ln -sf /bin/true /sbin/initctl
          eos
          packages = <<-eos
            ENV DEBIAN_FRONTEND noninteractive
            RUN apt-get update
            RUN apt-get install -y sudo openssh-server curl lsb-release
         eos
         config[:disable_upstart] ? disable_upstart + packages : packages
        when 'rhel', 'centos'
          <<-eos
            RUN yum clean all
            RUN yum install -y sudo openssh-server openssh-clients curl
            RUN ssh-keygen -t rsa -f /etc/ssh/ssh_host_rsa_key
            RUN ssh-keygen -t dsa -f /etc/ssh/ssh_host_dsa_key
          eos
        else
          raise ActionFailed,
            "Unknown platform '#{config[:platform]}'"
        end
        username = config[:username]
        password = config[:password]
        base = <<-eos
          RUN mkdir -p /var/run/sshd
          RUN useradd -d /home/#{username} -m -s /bin/bash #{username}
          RUN echo #{username}:#{password} | chpasswd
          RUN echo '#{username} ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
        eos
        custom = ''
        Array(config[:provision_command]).each do |cmd|
          custom << "RUN #{cmd}\n"
        end
        [from, env_variables, platform, base, custom].join("\n")
      end

      def fetch_dockerfile
        require 'open-uri'
        require 'erb'
        erb = ERB.new(open(config[:dockerfile]) { |f| f.read })
        erb.result(ERBContext.new(config).get_binding)
      end

      def container_config(state)
        data = {
          :Cmd => config[:run_command].split,
          :Image => state[:image_id],
          :AttachStdout => true,
          :AttachStderr => true,
          :Privileged => config[:privileged],
          :PublishAllPorts => false,
          :Tty => true
        }
        # Yes, this key must be a string
        data['name'] = config[:container_name]
        data[:CpuShares] = config[:cpu] if config[:cpu]
        data[:Dns] = config[:dns] if config[:dns]
        data[:Hostname] = config[:hostname] if config[:hostname]
        data[:Memory] = config[:memory] if config[:memory]
        forward = ['22'] + Array(config[:forward]).map { |mapping| mapping.to_s }
        forward.compact!
        data[:PortSpecs] = forward
        data[:PortBindings] = forward.inject({}) do |bindings, mapping|
          guest_port, host_port = mapping.split(':').reverse
          bindings["#{guest_port}/tcp"] = [{
            :HostIp => '',
            :HostPort => host_port || ''
          }]
          bindings
        end
        data[:Volumes] = Hash[Array(config[:volume]).map { |volume| [volume, {}] }]
        data
      end

      def parse_log_chunk(chunk)
        if ::Kitchen.logger.debug?
          logger.debug chunk
        else
          parsed_chunk = JSON.parse(chunk)
          parsed_chunk.each do |k, v|
            if [ "stream", "status" ].include? k
              logger.info parsed_chunk[k].strip
            end
          end
        end
      end

      def create_image(state, opts = {})
        opts[:rm] = config[:remove_images]
        image = ::Docker::Image.build(dockerfile, opts, @docker_connection) do |chunk|
          parse_log_chunk(chunk)
        end
        image.id
      end

      def create_container(state)
        config_data = container_config(state)
        container = ::Docker::Container.create(config_data, @docker_connection)
        container.start(config_data)
        container.id
      end

      def docker_image(state)
        ::Docker::Image.get(state[:image_id], nil, @docker_connection)
      end

      def docker_container(state)
        ::Docker::Container.get(state[:container_id], nil, @docker_connection)
      end

      def container_ssh_host
        remote_socket? ? socket_uri.host : 'localhost'
      end

      def container_ssh_port(state)
        container = docker_container(state)
        container.json['NetworkSettings']['Ports']['22/tcp'].first['HostPort']
      end

      def destroy_container(state)
        container = docker_container(state)
        container.stop
        container.wait
        container.delete
      end
    end
    # Erb class
    class ERBContext
      def initialize(config)
        config.each_pair do |k, v|
          instance_variable_set('@' + k.to_s, v)
        end
      end

      def get_binding
        binding
      end
    end
  end
end
