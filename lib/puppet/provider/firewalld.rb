require 'puppet'
require 'puppet/type'
require 'puppet/provider'
class Puppet::Provider::Firewalld < Puppet::Provider


  attr_reader :running

  def initialize(*args)
    if running.nil?
      check_running_state
    end
    super
  end

  def check_running_state
    begin
      ret = self.class.execute_firewall_cmd(['--state'], nil, false, false)
      @running = ret.exitstatus == 0 ? true : false
    rescue Puppet::MissingCommand => e
      # This exception is caught in case the module is being run before
      # the package provider has installed the firewalld package, if we
      # cannot find the firewalld-cmd command then we silently continue
      # leaving @running set to nil, this will cause it to be re-checked
      # later in the execution process.
      #
      # See: https://github.com/crayfishx/puppet-firewalld/issues/96
      #
      self.debug('Could not determine state of firewalld because the executable is not available')
    end
  end

  # v3.0.0
  def self.execute_firewall_cmd(args,  zone=nil, perm=true, failonfail=true, shell_cmd='firewall-cmd')
    cmd_args = []
    cmd_args << '--permanent' if perm
    cmd_args << [ '--zone', zone ] unless zone.nil?

    # Add the arguments to our command string, removing any quotes, the command
    # provider will sort the quotes out.
    cmd_args << args.flatten.map { |a| a.delete("'") }

    # We can't use the commands short cut as some things, like exists? methods need to
    # allow for the command to fail, and there is no way to override that.  So instead
    # we interact with Puppet::Provider::Command directly to enable us to override
    # the failonfail option
    #
    firewall_cmd = Puppet::Provider::Command.new(
      :firewall_cmd,
      shell_cmd,
      Puppet::Util,
      Puppet::Util::Execution,
      { :failonfail => failonfail }
    )
   firewall_cmd.execute(cmd_args.flatten)
  end



  def execute_firewall_cmd(args, zone=@resource[:zone], perm=true, failonfail=true)
    if online?
      self.class.execute_firewall_cmd(args, zone, perm, failonfail)
    else
      self.class.execute_firewall_cmd(args, zone, false, true, 'firewall-offline-cmd')
    end
  end

  # Arguments should be parsed as separate array entities, but quoted arg
  # eg --log-prefix 'IPTABLES DROPPED' should include the whole quoted part
  # in one element
  #
  def parse_args(args)
    if args.is_a?(Array)
      args = args.flatten.join(" ")
    end
    args.split(/(\'[^\']*\'| )/).reject { |r| [ "", " "].include?(r) }
  end

  # Occasionally we need to restart firewalld in a transient way between resources
  # (eg: services) so the provider needs an an-hoc way of doing this since we can't
  # do it from the puppet level by notifying the service.
  def reload_firewall
    execute_firewall_cmd(['--reload'], nil, false) if online?
  end

  def offline?
    check_running_state if running.nil?
    @running == false || @running.nil?
  end

  def online?
    check_running_state if running.nil?
    @running == true
  end


end
