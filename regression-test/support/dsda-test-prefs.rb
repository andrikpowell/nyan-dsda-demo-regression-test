# frozen_string_literal: true

# Paths to engines
EXE_PATH         = File.expand_path('../../build/nyan-doom.exe', __dir__)
OLD_EXE_PATH     = File.expand_path('../../build/build-old/dsda-doom.exe', __dir__)

# Core build/data paths
BUILD_PATH          = File.expand_path('../../build', __dir__)
IWAD_WAD_PATH       = File.expand_path('wads/', __dir__)
EXTRA_WAD_PATH      = File.expand_path('wads/EX/', __dir__)
COMMERCIAL_WAD_PATH = File.expand_path('wads/EX/CM/', __dir__)
MASTER_LEVELS_PATH  = File.expand_path('wads/EX/CM/ML/', __dir__)

# Demo locations + tmp workspace
DEMOS_ROOT       = File.expand_path('demos', __dir__)
TMP_ROOT         = File.expand_path('cache/tmp', __dir__)

# Override file
OVERRIDE_IMPORT  = File.expand_path("../overrides.csv", __dir__)

# Output files
CSV_OUTPUT       = File.expand_path('../data-export/results.csv', __dir__)
FAILURES_OUTPUT  = File.expand_path('../data-export/failures.csv', __dir__)

# Defaults
DEFAULT_IWAD     = 'doom2.wad'
TIMEOUT_SECS     = 900

# Amount of CPU cores to use (default: 75% of total)
PERCENT_OF_CORES = 0.75

module Utility
  extend self

  class Analysis
    def initialize(path = "analysis.txt")
      @path = path

      unless File.exist?(@path)
        @data = {}
        return
      end

      @data = Hash[
        File.readlines(@path, chomp: true).map(&:split).map do |a|
          [a[0], a[1..].join(' ')]
        end
      ]
    end

    def skill
      @data['skill'].to_i
    end

    def nomonsters?
      @data['nomonsters'] == '1'
    end

    def respawn?
      @data['respawn'] == '1'
    end

    def fast?
      @data['fast'] == '1'
    end

    def pacifist?
      @data['pacifist'] == '1'
    end

    def stroller?
      @data['stroller'] == '1'
    end

    def reality?
      @data['reality'] == '1'
    end

    def almost_reality?
      @data['almost_reality'] == '1'
    end

    def hundred_k?
      @data['100k'] == '1'
    end

    def hundred_s?
      @data['100s'] == '1'
    end

    def missed_monsters
      @data['missed_monsters'].to_i
    end

    def missed_secrets
      @data['missed_secrets'].to_i
    end

    def tyson_weapons?
      @data['tyson_weapons'] == '1'
    end

    def turbo?
      @data['turbo'] == '1'
    end

    def weapon_collector?
      @data['weapon_collector'] == '1'
    end

    def category
      @data['category']
    end
  end

  class Levelstat
    def initialize(filename)
      @data = File.readlines(filename, chomp: true).map(&:split)
    end

    def total
      return '00:00' unless @data.last

      raw = @data.last.join(' ')

      # Extract the time inside parentheses, e.g. (14:49)
      time = raw[/\(\s*(\d{1,3}:\d{2})\s*\)/, 1]

      # Fallback just in case it's missing
      time ||= '00:00'

      time
    end
  end
end