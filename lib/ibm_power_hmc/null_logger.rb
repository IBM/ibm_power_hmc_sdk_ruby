# frozen_string_literal: true

require "logger"

module IbmPowerHmc
  class NullLogger < Logger
    def initialize(*_args)
      super(nil)
    end

    def add(*_args, &)
    end

    def debug?
      false
    end

    def info?
      false
    end

    def warn?
      false
    end

    def error?
      false
    end

    def fatal?
      false
    end
  end
end
