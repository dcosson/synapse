require 'synapse/service_watcher/base'

module Synapse
  class DockerComposeLinksWatcher < BaseWatcher

    def start
      # Docker won't change env vars while the container is running, so don't need to poll
      # anything in a separate thread. Just check once and write values.

      log.info "synapse: docker-compose links watcher looking for env vars for #{@discovery['link_name']}"
      new_backends = discover_backends
      configure_backends new_backends
    end

    private

    def validate_discovery_opts
      raise ArgumentError, "link_name is required for service #{@name}" \
        unless @discovery['link_name']
    end

    def discover_backends
      backends = []
      # each docker compose link can be to multiple URL's, e.g. if the
      # linked app exposes multiple ports. They get named in order beginning
      # with 1, so look for all of them
      i = 1
      link_name = @discovery['link_name']
      while true do
        varname = "#{link_name.upcase}_#{i}_PORT"
        addr = ENV[varname]
        if !addr
          break
        end
        # remove the protocol in the specified link
        host_and_port = addr.sub(/^.*:\/\//, '')
        host, port = host_and_port.split ':'
        backends << {
          'name' => link_name,
          'host' => host,
          'port' => port
        }
        i += 1
      end
      backends
    end

    def configure_backends(new_backends)
      if new_backends.empty?
        if @default_servers.empty?
          log.warn "synapse: no backends and no default servers for service #{@name};"
        else
          log.warn "synapse: no backends for service #{@name};" \
            " using default servers: #{@default_servers.inspect}"
          set_backends @default_servers
        end
      else
        log.info "synapse: discovered #{new_backends.length} backends for service #{@name}"
        set_backends new_backends
      end
      @synapse.reconfigure!
    end
  end
end
