require 'puppet'
require 'spec_helper'
require 'puppet/provider/keystone'
require 'tempfile'

setup_provider_tests

klass = Puppet::Provider::Keystone

class Puppet::Provider::Keystone
  @credentials = Puppet::Provider::Openstack::CredentialsV3.new
end

describe Puppet::Provider::Keystone do
  let(:set_env) do
    ENV['OS_USERNAME']     = 'test'
    ENV['OS_PASSWORD']     = 'abc123'
    ENV['OS_SYSTEM_SCOPE'] = 'all'
    ENV['OS_AUTH_URL']     = 'http://127.0.0.1:5000/v3'
  end

  let(:another_class) do
    class AnotherKlass < Puppet::Provider::Keystone
      @credentials = Puppet::Provider::Openstack::CredentialsV3.new
    end
    AnotherKlass
  end

  before(:each) { set_env }

  after :each do
    klass.reset
    another_class.reset
  end

  describe '#domain_id_from_name' do
    it 'should list all domains when requesting a domain name from an ID' do
      klass.expects(:openstack)
           .with('domain', 'list', '--quiet', '--format', 'csv', [])
           .returns('"ID","Name","Enabled","Description"
"someid","SomeName",True,"default domain"
')
      expect(klass.domain_id_from_name('SomeName')).to eq('someid')
    end
    it 'should lookup a domain when not found in the hash' do
      klass.expects(:openstack)
           .with('domain', 'show', '--format', 'shell', 'NewName')
           .returns('
name="NewName"
id="newid"
')
      expect(klass.domain_id_from_name('NewName')).to eq('newid')
    end
    it 'should print an error when there is no such domain' do
      klass.expects(:openstack)
           .with('domain', 'show', '--format', 'shell', 'doesnotexist')
           .returns('
')
      klass.expects(:err)
           .with('Could not find domain with name [doesnotexist]')
      expect(klass.domain_id_from_name('doesnotexist')).to eq(nil)
    end
  end

  describe '#fetch_project' do
    let(:set_env) do
      ENV['OS_USERNAME']     = 'test'
      ENV['OS_PASSWORD']     = 'abc123'
      ENV['OS_SYSTEM_SCOPE'] = 'all'
      ENV['OS_AUTH_URL']     = 'http://127.0.0.1:5000/v3'
    end

    before(:each) do
      set_env
    end

    it 'should be false if the project does not exist' do
      klass.expects(:request_timeout).returns(0)
      klass.expects(:openstack)
        .with('project', 'show', '--format', 'shell', ['no_project', '--domain', 'Default'])
        .once
        .raises(Puppet::ExecutionFailure, "Execution of '/usr/bin/openstack project show --format shell no_project' returned 1: No project with a name or ID of 'no_project' exists.")
      expect(klass.fetch_project('no_project', 'Default')).to be_falsey
    end

    it 'should return the project' do
      klass.expects(:openstack)
        .with('project', 'show', '--format', 'shell', ['The Project', '--domain', 'Default'])
        .returns('
name="The Project"
id="the_project_id"
')
      expect(klass.fetch_project('The Project', 'Default')).to eq({:name=>"The Project", :id=>"the_project_id"})
    end
  end

  describe '#fetch_user' do
    let(:set_env) do
      ENV['OS_USERNAME']     = 'test'
      ENV['OS_PASSWORD']     = 'abc123'
      ENV['OS_SYSTEM_SCOPE'] = 'all'
      ENV['OS_AUTH_URL']     = 'http://127.0.0.1:5000/v3'
    end

    before(:each) do
      set_env
    end

    it 'should be false if the user does not exist' do
      klass.expects(:request_timeout).returns(0)
      klass.expects(:openstack)
        .with('user', 'show', '--format', 'shell', ['no_user', '--domain', 'Default'])
        .once
        .raises(Puppet::ExecutionFailure, "Execution of '/usr/bin/openstack user show --format shell no_user' returned 1: No user with a name or ID of 'no_user' exists.")
      expect(klass.fetch_user('no_user', 'Default')).to be_falsey
    end

    it 'should return the user' do
      klass.expects(:openstack)
        .with('user', 'show', '--format', 'shell', ['The User', '--domain', 'Default'])
        .returns('
name="The User"
id="the_user_id"
')
      expect(klass.fetch_user('The User', 'Default')).to eq({:name=>"The User", :id=>"the_user_id", :description=>""})
    end
  end

  describe '#get_auth_url' do
    it 'should return the OS_AUTH_URL from the environment' do
      ENV.clear
      ENV['OS_AUTH_URL'] = 'http://127.0.0.1:5001'
      expect(klass.get_auth_url).to eq('http://127.0.0.1:5001')
    end

    it 'should return the OS_AUTH_URL from the openrc file when there is no OS_AUTH_URL in the environment' do
      home = ENV['HOME']
      ENV.clear
      mock = {'OS_AUTH_URL' => 'http://127.0.0.1:5001'}
      klass.expects(:get_os_vars_from_rcfile).with("#{home}/openrc").returns(mock)
      expect(klass.get_auth_url).to eq('http://127.0.0.1:5001')
    end

    it 'should use auth_endpoint when nothing else is available' do
      ENV.clear
      mock = 'http://127.0.0.1:5001'
      klass.expects(:auth_endpoint).returns(mock)
      expect(klass.get_auth_url).to eq('http://127.0.0.1:5001')
    end
  end

  describe '#set_domain_for_name' do
    it 'should raise an error if the domain is not provided' do
      expect do
        klass.set_domain_for_name('name', nil)
      end.to raise_error(Puppet::Error, /Missing domain name for resource/)
    end

    it 'should return the name only when the provided domain is the default domain id' do
      klass.expects(:default_domain_id)
        .returns('default')
      klass.expects(:openstack)
        .with('domain', 'show', '--format', 'shell', 'Default')
        .returns('
name="Default"
id="default"
')
      expect(klass.set_domain_for_name('name', 'Default')).to eq('name')
    end

    it 'should return the name and domain when the provided domain is not the default domain id' do
      klass.expects(:default_domain_id)
        .returns('default')
      klass.expects(:openstack)
        .with('domain', 'show', '--format', 'shell', 'Other Domain')
        .returns('
name="Other Domain"
id="other_domain_id"
')
      expect(klass.set_domain_for_name('name', 'Other Domain')).to eq('name::Other Domain')
    end

    it 'should return the name only if the domain cannot be fetched' do
      klass.expects(:default_domain_id)
        .returns('default')
      klass.expects(:openstack)
        .with('domain', 'show', '--format', 'shell', 'Unknown Domain')
        .returns('')
      expect(klass.set_domain_for_name('name', 'Unknown Domain')).to eq('name')
    end
  end

  describe 'when using domains' do
    before(:each) do
      set_env
    end

    it 'should list all domains when requesting a domain name from an ID' do
      klass.expects(:openstack)
           .with('domain', 'list', '--quiet', '--format', 'csv', [])
           .returns('"ID","Name","Enabled","Description"
"somename","SomeName",True,"default domain"
')
      expect(klass.domain_name_from_id('somename')).to eq('SomeName')
    end
    it 'should lookup a domain when not found in the hash' do
      klass.expects(:openstack)
           .with('domain', 'list', '--quiet', '--format', 'csv', [])
           .returns('"ID","Name","Enabled","Description"
"somename","SomeName",True,"default domain"
')
      klass.expects(:openstack)
           .with('domain', 'show', '--format', 'shell', 'another')
           .returns('
name="AnOther"
id="another"
')
      expect(klass.domain_name_from_id('somename')).to eq('SomeName')
      expect(klass.domain_name_from_id('another')).to eq('AnOther')
    end
    it 'should print an error when there is no such domain' do
      klass.expects(:openstack)
           .with('domain', 'list', '--quiet', '--format', 'csv', [])
           .returns('"ID","Name","Enabled","Description"
"somename","SomeName",True,"default domain"
')
      klass.expects(:openstack)
           .with('domain', 'show', '--format', 'shell', 'doesnotexist')
           .returns('
')
      klass.expects(:err)
           .with('Could not find domain with id [doesnotexist]')
      expect(klass.domain_name_from_id('doesnotexist')).to eq(nil)
    end
  end
end
