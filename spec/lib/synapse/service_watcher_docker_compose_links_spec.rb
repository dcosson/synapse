require 'spec_helper'
require 'logging'

class Synapse::DockerComposeLinksWatcher
  # make writeable for test setup
  attr_writer :default_servers
end

describe Synapse::DockerComposeLinksWatcher do
  let(:mock_synapse) { double }
  subject { Synapse::DockerComposeLinksWatcher.new(basic_config, mock_synapse) }

  let(:basic_config) do
    { 'name' => 'docker_compose_links_test',
      'haproxy' => {
        'port' => '8080',
        'server_port_override' => '8081'
      },
      "discovery" => {
        "method" => "docker_compose_links",
        "link_name" => "foobar",
      }
    }
  end

  def remove_discovery_arg(name)
    args = basic_config.clone
    args['discovery'].delete name
    args
  end

  describe '#new' do
    it 'instantiates cleanly with basic config' do
      expect { subject }.not_to raise_error
    end

    it 'requires a link_name argument' do
      expect {
        Synapse::DockerComposeLinksWatcher.new(remove_discovery_arg('link_name'), mock_synapse)
      }.to raise_error
    end
  end

  describe 'start' do
    it 'discovers backends and configures them' do
      fake_backends = ['fake', 1, 2]
      expect(subject).to receive(:discover_backends).and_return(fake_backends)
      expect(subject).to receive(:configure_backends).with(fake_backends)

      subject.send(:start)
    end
  end

  describe 'discover_backends' do
    it 'finds backends from contiguously numbered env variables in the format created by docker-compose' do
      allow(ENV).to receive(:[]).with("FOOBAR_1_PORT").and_return("127.0.0.1:8001")
      allow(ENV).to receive(:[]).with("FOOBAR_2_PORT").and_return("127.0.0.2:8002")
      allow(ENV).to receive(:[]).with("FOOBAR_3_PORT").and_return(nil)

      backends = subject.send(:discover_backends)
      expect(backends.length).to be(2)
      expect(backends[0]['name']).to eq('foobar')
      expect(backends[0]['host']).to eq('127.0.0.1')
      expect(backends[0]['port']).to eq('8001')
      expect(backends[1]['name']).to eq('foobar')
      expect(backends[1]['host']).to eq('127.0.0.2')
      expect(backends[1]['port']).to eq('8002')
    end

    it 'does not use non-contiguous backends' do
      allow(ENV).to receive(:[]).with("FOOBAR_1_PORT").and_return("127.0.0.1:8001")
      allow(ENV).to receive(:[]).with("FOOBAR_2_PORT").and_return(nil)
      allow(ENV).to receive(:[]).with("FOOBAR_3_PORT").and_return("127.0.0.2:8002")

      backends = subject.send(:discover_backends)
      expect(backends.length).to be(1)
      expect(backends[0]['name']).to eq('foobar')
      expect(backends[0]['host']).to eq('127.0.0.1')
      expect(backends[0]['port']).to eq('8001')
    end

    it 'expects numbers starting at 1 not 0' do
      allow(ENV).to receive(:[]).with("FOOBAR_0_PORT").and_return("127.0.0.0:8000")
      allow(ENV).to receive(:[]).with("FOOBAR_1_PORT").and_return(nil)

      backends = subject.send(:discover_backends)
      expect(backends.length).to be(0)
    end
  end

  describe 'configure_backends' do
    context 'with no default servers' do
      before do
        subject.default_servers = []
      end

      it 'reconfigures without setting backends if no new backends and no new default servers' do
        expect(subject).not_to receive(:set_backends)
        expect(mock_synapse).to receive(:reconfigure!)

        subject.send(:configure_backends, [])
      end
    end

    context 'with default servers' do
      let(:default_servers) do
        [{ 'name' => 'foobar',
          'host' => '127.0.0.1',
          'port' => '8001'
        }]
      end
      before do
        subject.default_servers = default_servers
      end

      it 'reconfigures with default servers if no new backends' do
        expect(subject).to receive(:set_backends).with(default_servers)
        expect(mock_synapse).to receive(:reconfigure!)

        subject.send(:configure_backends, [])
      end

      it 'reconfigures with new backends' do
        new_backends = [
          { 'name' => 'foobar',
            'host' => '127.0.0.2',
            'port' => '8002'
          }]
        expect(subject).to receive(:set_backends).with(new_backends)
        expect(mock_synapse).to receive(:reconfigure!)

        subject.send(:configure_backends, new_backends)
      end
    end

  end
end
