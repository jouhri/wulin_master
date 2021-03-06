# frozen_string_literal: true

module WulinMaster
  def self.configure(configuration = WulinMaster::Configuration.new)
    yield configuration if block_given?
    @config = configuration
  end

  def self.config
    @config ||= WulinMaster::Configuration.new
  end

  class Configuration
    attr_accessor :app_title, :app_title_height, :always_reset_form, :default_year, :color_theme

    def initialize
      self.app_title = 'Undefined App'
      self.app_title_height = '42px'
      self.always_reset_form = false
      self.default_year = Time.zone.today.year
      self.color_theme = 'blue'
    end
  end
end
