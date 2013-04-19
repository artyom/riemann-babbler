require File.expand_path('../deep_merge', __FILE__)
require File.expand_path('../riemann/babbler/plugin', __FILE__)

def set_logger_lvl(logger, configatron)
  case configatron.logger.level
  when "INFO"
    logger.level = Logger::INFO
  when "WARN"
    logger.level = Logger::WARN
  when "ERROR"
    logger.level = Logger::ERROR
  when "FATAL"
    logger.level = Logger::FATAL
  when "UNKNOWN"
    logger.level = Logger::UNKNOWN
  else
    logger.level = Logger::DEBUG
  end
end

# merge configs
def merge_config(logger, opts, configatron)
  config_file =  if File.exist?( opts[:config] )
    YAML.load_file( opts[:config] ).to_hash
  else
    logger.error "Can't load config file #{opts[:config]}"
    Hash.new
  end

  config_default = YAML.load_file( File.expand_path('../../config.yml', __FILE__) )

  config = config_default.deep_merge( config_file )
  configatron.configure_from_hash config
end

# получаем список все плагинов
def load_plugins(configatron)
  plugins = []
  default_plugins_dir = File.expand_path('../riemann/babbler/plugins/', __FILE__)
  Dir.glob( default_plugins_dir + "/*.rb" ) do |file|
    plugins <<  file
  end

  unless configatron.plugins.dirs.nil?
    configatron.plugins.dirs.each do |dir|
      next unless Dir.exist? dir
      Dir.glob( dir + "/*.rb" ) do |file|
        plugins << file
      end
    end
  end

  unless configatron.plugins.files.nil?
    configatron.plugins.files.each do |file|
      plugins << file
    end
  end
  plugins.each { |plugin| require plugin }
end

def get_riemann(configatron)
  riemann_ip =  Resolv.new.getaddress(configatron.riemann.host)
  riemann = Riemann::Client.new(
    :host => riemann_ip,
    :port => configatron.riemann.port
  )
  riemann = ( configatron.riemann.proto == 'tcp' ) ? riemann.tcp : riemann
  riemann
end

# логика стартования плагинов
def start_plugins(registered_plugins, riemann, logger, configatron)

  if run_only = configatron.plugins.run_only
    registered_plugins.delete_if {|plugin| ! run_only.include? plugin.to_s.split("::").last.downcase }
  end unless ( configatron.plugins.run_only.nil? || configatron.plugins.run_only.empty? )

  plugin_threads = registered_plugins.map do |plugin|
    Thread.new {
      plugin.new( configatron, logger, riemann ).run
    }
  end

  # plugin control
  Signal.trap "TERM" do
    plugin_threads.each( &:kill )
  end

  plugin_threads.each( &:join )
end

def load_parent(configatron)
  configatron.to_hash[:plugins].each do |plugin, opts|
    next if opts.nil?
    next unless opts.kind_of? Hash
    create_class(plugin.capitalize, opts[:parent].capitalize) if opts.has_key? :parent
  end
end

# plugin load parent
def create_class(new_class, parent_class)
  cmd = "class Riemann::Babbler::#{new_class} < Riemann::Babbler::#{parent_class}; end;"
  cmd += "Riemann::Babbler.registered_plugins << Riemann::Babbler::#{new_class}"
  eval(cmd)
end


