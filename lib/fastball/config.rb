require 'erb'
require 'forwardable'
require 'json'
require 'yaml'

module Fastball

  # The Fastball::Config generates environment specific configuration files.
  #
  # == usage
  #
  # Set up your application's configuration templates and +app_config.yml+ file
  # as described below, then run the following rake task:
  #
  #     `rake fastball:config`
  #
  # == Conventions
  #
  # Fastball looks for ERB configuration templates in the following locations
  # relative to the current working directory:
  #
  #     - .env.erb
  #     - config/*.erb
  #
  # The generated config files will have the same path as the config templates
  # but with the +.erb+ extension removed.
  #
  #     config/database.yml.erb --> rake fastball:config --> config/database.yml
  #
  # You should <b>never edit the generated config file</b> by hand because Fastball will
  # overwrite your changes.
  #
  # == app_config.yml
  #
  # To customize the configuration for a specific environment, Fastball expects
  # to find an +app_config.yml+ file in the current directory containing the
  # environment specific values for the variables refenced in the config templates.
  # Fastball will complain if this file does not exist or is missing a config value
  # required by one of the templates.
  #
  # Fastball does not generate +app_config.yml+ for you. Typically, your configuration
  # management tool (ansible, chef, puppet, etc.) will generate +app_config.yml+ for
  # deployment environments, and developers will create and edit +app_config.yml+
  # locally. It is recommended that you don't commit this file to version control.
  # Instead, you should create an +app_config.yml.example+ with dummy config values
  # to use in development/test environments that other team members can copy to
  # +app_config.yml+ and modify for their specific environment.
  #
  # == Example
  #
  # To generate the following +config/database.yml+ file,
  #
  #     !!!yaml
  #     ---
  #     staging:
  #       adapter: mysql2
  #       host: localhost
  #       username: dbuser
  #       password: secret
  #
  # you would create a +config/database.yml.erb+ template like this,
  #
  #     !!!yaml
  #     ---
  #     <%= rails_env %>:
  #       adapter: mysql2
  #       host: <%= db.host %>
  #       username: <%= db.username %>
  #       password: <%= db.password %>
  #
  # and save the following config values to +app_config.yml+.
  #
  #     !!!yaml
  #     ---
  #     rails_env: staging
  #     db:
  #       host: localhost
  #       username: dbuser
  #       password: secret
  #
  class Config
    attr_reader :config
    attr_reader :environment

    extend Forwardable
    def_delegators Fastball, :headline, :progress

    class << self
      # See {Config} for information about +.generate+.
      def generate(environment=nil)
        self.new.generate environment
      end
    end

    # See {Config} for information about +#generate+.
    def generate(environment=nil)
      @environment ||= environment

      load_config_values

      headline "Rendering config files from provided templates.\n"
      results = template_paths.map do |path|
        render_template path
      end

      headline "Saving new config files.\n"
      template_paths.zip(results) do |path, result|
        save_result path, result
      end
    end

    private

    def template_paths
      @template_paths ||= Dir['.env.erb', 'config/*.erb'].to_a
    end

    def load_config_values
      @config ||= HashDot.new load_config_hash
    end

    def load_config_hash
      file = @environment ? "app_config.#{@environment}" : 'app_config'

      if File.exists?("#{file}.yml")
        YAML.load File.read("#{file}.yml")
      elsif File.exists?("#{file}.json")
        JSON.parse File.read("#{file}.json")
      else
        raise MissingAppConfig.new("expecting #{file}.yml to exist in the current directory")
      end
    end

    def render_template(path)
      progress  "rendering '#{path}'"
      template = ERB.new pre_process_template(path)
      template_binding = config.instance_eval { binding }
      template.result template_binding
    end

    def save_result(path, result)
      real_path = path.sub(/\.erb$/, '')
      progress "saving '#{real_path}'"
      File.write real_path, result
    end

    def pre_process_template(path)
      File.read(path)
          .gsub(/\{\{ */, '<%= ')
          .gsub(/ *\}\}/, ' %>')
    end

  end

end
