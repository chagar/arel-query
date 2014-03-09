#require 'active_record/relation/delegation'
#require 'active_support/core_ext/module/delegation'
#require 'active_support/dependencies/autoload'
#require 'active_record/connection_adapters/abstract_adapter'

require 'yaml'
require 'pathname'

require 'active_record/connection_handling'
require 'active_record/runtime_registry'

require 'active_record/errors'
require 'active_record/connection_adapters/abstract/connection_pool'
require 'active_record/connection_adapters/connection_specification'

require 'active_record/sanitization'

module ArelQuery
  module Connector
    class ActiveRecordConnector
      include ActiveRecord::Sanitization
      extend ActiveRecord::ConnectionHandling
      cattr_accessor :configurations

      # Called in connection adapters. Ignore.
      def self.default_timezone; nil; end

      # Called by ActiveRecord::Relation::PredicateBuilder#build_from_hash. Ignore.
      def self.reflect_on_association(x); nil; end

      # Compare Rails::Application::Bootstrap#initialize_logger
      def self.logger
        return @logger unless @logger.nil?
        
        path = "log/development.log" # TODO handle environments
        unless File.exist? File.dirname path
          FileUtils.mkdir_p File.dirname path
        end

        f = File.open path, 'a'
        f.binmode
  
        @logger = ActiveSupport::Logger.new f
      end
  
      def self.connection
        begin
          retrieve_connection
        rescue ActiveRecord::ConnectionNotEstablished
          self.configurations = database_configuration
          establish_connection(:development) # TODO Handle this when it is supposed to be :production, etc.
          retrieve_connection
        end
      end
  
      # From ActiveRecord::Core::connection_handler, called by ActiveRecord::ConnectionHandling
      def self.connection_handler
        # TODO Figure this out
        #ActiveRecord::RuntimeRegistry.connection_handler || ActiveRecord::ConnectionAdapters::ConnectionHandler.new
        @connection_handler ||= ActiveRecord::ConnectionAdapters::ConnectionHandler.new
      end
  
      # Compare Rails::Application::Configuration#database_configuration
      # Loading the whole file 'rails/application/configuration' is especially slow
      def self.database_configuration
        yaml = Pathname.new("config/database.yml") # TODO Make absolute?
  
        config = if yaml.exist?
          require "erb"
          YAML.load(ERB.new(yaml.read).result) || {}
        elsif ENV['DATABASE_URL']
          # Value from ENV['DATABASE_URL'] is set to default database connection
          # by Active Record.
          {}
        else
          raise "Could not load database configuration. No such file - #{yaml}"
        end
  
        config
      rescue Psych::SyntaxError => e
        raise "YAML syntax error occurred while parsing database configuration. " \
              "Please note that YAML must be consistently indented using spaces. Tabs are not allowed. " \
              "Error: #{e.message}"
      rescue => e
        raise e, "ArelQuery: cannot load database_configuration:\n#{e.message}", e.backtrace
      end
  
    end
  end
end

module ActiveRecord
  Base = ArelQuery::Connector::ActiveRecordConnector
end
